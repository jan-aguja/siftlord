import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/pricing/catalog.dart';
import 'package:siftlord/pricing/price_check.dart';
import 'package:siftlord/pricing/text_match.dart';

final catalog = Catalog.parse(File('assets/catalog.json').readAsStringSync());
final check = PriceCheck(catalog);

var _rank = 0;
Item item(String title, double price, {bool official = false, bool ad = false}) => Item(
      storeId: 'lazada',
      title: title,
      price: price,
      url: Uri.parse('https://example.invalid/$_rank'),
      rank: _rank++,
      isAd: ad,
      sellerTier: official ? SellerTier.mall : SellerTier.regular,
    );

void main() {
  group('text matching', () {
    test('normalizes how sellers write names', () {
      expect(normalizeText('AirPods Pro3 (2025)!'), 'airpods pro 3 2025');
      expect(normalizeText('Stanley 40oz'), 'stanley 40 oz');
      expect(normalizeText('🍎 𝑨𝑰𝑹𝑷𝑶𝑫𝑺 𝑮𝒆𝒏 𝟑 🍎'), 'airpods gen 3');
      expect(normalizeText('ＡｉｒＰｏｄｓ'), 'airpods');
    });

    test('numbers match whole words, other tokens also as prefixes', () {
      expect(titleHasTokens(words('Apple iPad A16 (11th Generation)'), queryTokens('ipad 11th gen')), isTrue);
      expect(titleHasTokens(words('AirPods Pro 2'), queryTokens('airpods pro 3')), isFalse);
      expect(titleHasTokens(words('Rice cooker 3L'), queryTokens('rice cooker 3')), isTrue);
    });
  });

  group('catalog', () {
    test('the shipped catalog parses', () {
      expect(catalog.entries, isNotEmpty);
      for (final e in catalog.entries) {
        expect(e.minPrice, lessThanOrEqualTo(e.maxPrice), reason: e.id);
      }
    });

    test('matches the longest name the query contains', () {
      expect(catalog.match('AirPods Pro 3 white')?.id, 'airpods-pro-3');
      expect(catalog.match('apple airpods 4')?.id, 'airpods-4');
      expect(catalog.match('airpods pro')?.id, isNull, reason: 'could be either generation');
      expect(catalog.match('nintendo switch 2 mario kart bundle')?.id, 'nintendo-switch-2');
    });

    test('suggests products while typing', () {
      expect(catalog.suggest('airp').map((e) => e.id), containsAll(['airpods-pro-3', 'airpods-4']));
      expect(catalog.suggest('flip').map((e) => e.id), contains('jbl-flip-7'));
      expect(catalog.suggest('jbl flip').map((e) => e.id), ['jbl-flip-7']);
      expect(catalog.suggest('a'), isEmpty);
    });
  });

  group('reference price', () {
    test('catalog product uses the catalog range', () {
      final ref = check.reference('airpods pro 3', const [])!;
      expect(ref.source, PriceSource.catalog);
      expect((ref.low, ref.high), (14290, 16990));
    });

    test('unknown product uses official stores, ignoring games and stray earbuds', () {
      // Real mix from LazMall "nintendo switch 2"-style results.
      final items = [
        item('Nintendo Switch Two OLED Console', 32999, official: true),
        item('Nintendo Switch Two OLED Console', 33990, official: true),
        item('Nintendo Switch Two OLED Console', 34995, official: true),
        item('Nintendo Switch Two OLED Console Reanimal Game', 2195, official: true),
        item('Nintendo Switch Two OLED Console Stellar Blade', 3145, official: true),
        item('Nintendo Switch Two OLED Console', 900, official: false),
      ];
      final ref = check.reference('nintendo switch two oled console', items)!;
      expect(ref.source, PriceSource.officialStores);
      expect(ref.low, 33990);
      expect(ref.officialCount, 3);
    });

    test('official accessories don\'t drag the reference down', () {
      final items = [
        item('Bose QuietComfort Ultra Earbuds', 15990, official: true),
        item('Bose QuietComfort Ultra Earbuds', 16490, official: true),
        item('Case for Bose QuietComfort Ultra Earbuds', 990, official: true),
      ];
      expect(check.reference('bose quietcomfort ultra earbuds', items)!.low, 16240);
    });

    test('needs two official listings, otherwise nothing', () {
      final items = [item('Bose QuietComfort Ultra Earbuds', 15990, official: true)];
      expect(check.reference('bose quietcomfort ultra earbuds', items), isNull);
      expect(check.reference('bose quietcomfort ultra earbuds', const []), isNull);
    });
  });

  group('verdicts', () {
    final ref = check.reference('airpods pro 3', const [])!;

    test('a listing claiming the product far below usual is flagged', () {
      expect(check.verdict(item('Apple AirPods Pro 3', 1290), ref, 'airpods pro 3'), PriceVerdict.tooLow);
      expect(check.verdict(item('AirPods Pro 3 TWS Earbuds Original', 899), ref, 'airpods pro 3'), PriceVerdict.tooLow);
    });

    test('an official store far below usual is a big sale', () {
      expect(check.verdict(item('Apple AirPods Pro 3', 7999, official: true), ref, 'airpods pro 3'), PriceVerdict.bigSale);
      expect(check.verdict(item('Apple AirPods Pro 3', 1499, official: true), ref, 'airpods pro 3'), PriceVerdict.none,
          reason: 'a tenth of the price is another item naming it, not a sale');
    });

    test('far above usual is flagged too', () {
      expect(check.verdict(item('Apple AirPods Pro 3', 29990), ref, 'airpods pro 3'), PriceVerdict.tooHigh);
    });

    test('normal prices, honest accessories and other products get nothing', () {
      expect(check.verdict(item('Apple AirPods Pro 3', 14500), ref, 'airpods pro 3'), PriceVerdict.none);
      expect(check.verdict(item('Apple AirPods Pro 3 with MagSafe Charging Case', 14290), ref, 'airpods pro 3'), PriceVerdict.none);
      expect(check.verdict(item('AirPods Pro 3 Replacement Ear Tips', 299), ref, 'airpods pro 3'), PriceVerdict.none);
      expect(check.verdict(item('Pro 5S Wireless Earbuds', 135), ref, 'airpods pro 3'), PriceVerdict.none);
    });

    test('"made for" listings are third-party, whatever the price', () {
      expect(check.verdict(item('For Original AirPods Pro 3 TWS', 899), ref, 'airpods pro 3'), PriceVerdict.thirdParty);
      expect(check.verdict(item('Silicone Case for AirPods Pro 3', 199), ref, 'airpods pro 3'), PriceVerdict.thirdParty);
      expect(check.verdict(item('Ear tips compatible with AirPods Pro 3', 299), ref, 'airpods pro 3'),
          PriceVerdict.thirdParty);
    });

    test('the brand\'s own "for" listing isn\'t third-party', () {
      final apple = Item(
        storeId: 'lazada',
        title: 'Apple MagSafe Charger for AirPods Pro 3',
        price: 2490,
        url: Uri.parse('https://example.invalid/apple'),
        rank: 0,
        sellerTier: SellerTier.mall,
        shopName: 'Apple Flagship Store',
      );
      expect(check.verdict(apple, ref, 'airpods pro 3'), isNot(PriceVerdict.thirdParty));
    });

    test('works without any price reference: "for MacBook" vs "MacBook" charger', () {
      expect(check.verdict(item('65W USB-C Charger for MacBook Air Pro', 450), null, 'macbook charger'),
          PriceVerdict.thirdParty);
      expect(check.verdict(item('Apple 70W USB-C Power Adapter MacBook charger', 3990), null, 'macbook charger'),
          PriceVerdict.none);
      expect(check.verdict(item('Leather case for MacBook', 900), null, 'case for macbook'), PriceVerdict.none,
          reason: 'the searcher asked for "for" items');
    });

    test('person-to-person listings get more room unless they say brand new', () {
      Item fb(String title, double price) => Item(
            storeId: 'facebook',
            title: title,
            price: price,
            url: Uri.parse('https://example.invalid/fb'),
            rank: 0,
            secondhandMarket: true,
            condition: conditionFromTitle(title),
          );
      expect(check.verdict(fb('AirPods Pro 3 preloved', 7500), ref, 'airpods pro 3'), PriceVerdict.none);
      expect(check.verdict(fb('AirPods Pro 3', 6000), ref, 'airpods pro 3'), PriceVerdict.none);
      expect(check.verdict(fb('AirPods Pro 3', 2500), ref, 'airpods pro 3'), PriceVerdict.tooLow);
      expect(check.verdict(fb('AirPods Pro 3 brand new sealed', 6000), ref, 'airpods pro 3'), PriceVerdict.tooLow);
    });

    test('Switch 2 games are not flagged as cheap consoles', () {
      final sw = check.reference('nintendo switch 2', const [])!;
      expect(check.verdict(item('[PRE-ORDER] Nintendo Switch 2 Stellar Blade Complete Edition', 3145), sw, 'nintendo switch 2'),
          PriceVerdict.none);
      expect(check.verdict(item('Nintendo Switch 2 Console', 9999), sw, 'nintendo switch 2'), PriceVerdict.tooLow);
    });
  });

  group('catalog coverage', () {
    test('ids are unique and aliases are lowercase', () {
      final ids = <String>{};
      for (final e in catalog.entries) {
        expect(ids.add(e.id), isTrue, reason: 'duplicate id ${e.id}');
        for (final a in e.aliases) {
          expect(a, a.toLowerCase(), reason: e.id);
        }
      }
    });

    test('no alias belongs to two products', () {
      final owner = <String, String>{};
      for (final e in catalog.entries) {
        for (final n in e.allNames) {
          final key = normalizeText(n);
          final prev = owner.putIfAbsent(key, () => e.id);
          expect(prev, e.id, reason: '"$n" is claimed by $prev and ${e.id}');
        }
      }
    });

    test('model lines resolve to the right variant', () {
      final cases = {
        'iphone 17 256gb': 'iphone-17',
        'apple iphone 17 pro': 'iphone-17-pro',
        'iphone 17 pro max 1tb': 'iphone-17-pro-max',
        'iPhone 17e': 'iphone-17e',
        'iphone 18 pro': 'iphone-18-pro',
        'iphone 18 pro max cosmic': 'iphone-18-pro-max',
        'iphone 16': 'iphone-16',
        'iphone 16 plus': 'iphone-16-plus',
        'samsung galaxy s26': 'galaxy-s26',
        'galaxy s26 ultra 512gb': 'galaxy-s26-ultra',
        'galaxy s26 plus': 'galaxy-s26-plus',
        'galaxy s26 fe': 'galaxy-s26-fe',
        'galaxy z fold8': 'galaxy-z-fold8',
        'galaxy z fold8 ultra': 'galaxy-z-fold8-ultra',
        'galaxy a17': 'galaxy-a17',
        'galaxy a17 5g': 'galaxy-a17-5g',
        'galaxy buds4 pro': 'galaxy-buds4-pro',
        'galaxy buds4': 'galaxy-buds4',
        'ps5 slim': 'ps5-slim',
        'ps5 pro': 'ps5-pro',
        'dualsense': 'dualsense',
        'dualsense edge': 'dualsense-edge',
        'nintendo switch 2 pro controller': 'switch-2-pro-controller',
        'nintendo switch 2 joy-con 2': 'joy-con-2',
        'sony wh-1000xm6': 'sony-wh-1000xm6',
        'sony wf-1000xm6': 'sony-wf-1000xm6',
        'WH1000XM5': 'sony-wh-1000xm5',
        'macbook pro m5': 'macbook-pro-m5',
        'macbook pro m5 max': 'macbook-pro-m5-pro-max',
        'xiaomi 17': 'xiaomi-17',
        'xiaomi 17t': 'xiaomi-17t',
        'redmi note 17 pro': 'redmi-note-17-pro',
        'redmi note 17 pro max': 'redmi-note-17-pro-max',
        'apple watch series 12': 'apple-watch-series-12',
        'apple watch ultra 4': 'apple-watch-ultra-4',
        'airpods 5': 'airpods-5',
        'airpods max': 'airpods-max-2',
        'dji osmo pocket 3': 'dji-osmo-pocket-3',
        'osmo pocket 4': 'dji-osmo-pocket-4',
      };
      cases.forEach((q, id) => expect(catalog.match(q)?.id, id, reason: q));
    });

    test('JBL Flip and Galaxy Z Flip do not collide', () {
      expect(catalog.match('jbl flip 7')?.id, 'jbl-flip-7');
      expect(catalog.match('flip 7 speaker')?.id, 'jbl-flip-7');
      expect(catalog.match('galaxy z flip8')?.id, 'galaxy-z-flip8');
      expect(catalog.match('samsung galaxy z flip7 256gb')?.id, 'galaxy-z-flip7');
      expect(catalog.match('z flip7')?.id, 'galaxy-z-flip7');
      expect(catalog.match('samsung flip 7')?.id, 'galaxy-z-flip7');
      final jbl = check.reference('flip 7', const [])!;
      expect(check.verdict(item('Samsung Galaxy Z Flip7 512GB', 82190, official: true), jbl, 'flip 7'),
          PriceVerdict.none, reason: 'a phone in "flip 7" results is not an overpriced speaker');
      final z7 = check.reference('galaxy z flip7', const [])!;
      expect(check.verdict(item('JBL Flip 7 Portable Speaker', 6999), z7, 'galaxy z flip7'), PriceVerdict.none);
    });

    test('brand-only or ambiguous searches match nothing', () {
      for (final q in ['iphone', 'samsung galaxy', 'ps5', 'sony headphones', 'dji', 'garmin', 'apple watch']) {
        expect(catalog.match(q), isNull, reason: q);
      }
    });

    test('bigger siblings in the results are not "price looks high"', () {
      final i17 = check.reference('iphone 17', const [])!;
      expect(check.verdict(item('Apple iPhone 17 Pro Max 2TB', 157990, official: true), i17, 'iphone 17'),
          PriceVerdict.none);
      final s26 = check.reference('galaxy s26', const [])!;
      expect(check.verdict(item('Samsung Galaxy S26 Ultra 1TB', 138990, official: true), s26, 'galaxy s26'),
          PriceVerdict.none);
      final ds = check.reference('dualsense', const [])!;
      expect(check.verdict(item('PS5 DualSense Edge Wireless Controller', 13178, official: true), ds, 'dualsense'),
          PriceVerdict.none);
      final mbp = check.reference('macbook pro m5', const [])!;
      expect(check.verdict(item('Apple MacBook Pro 16 M5 Max 48GB', 349990, official: true), mbp, 'macbook pro m5'),
          PriceVerdict.none);
    });

    test('cheaper siblings are not "price looks off"', () {
      final x17 = check.reference('xiaomi 17', const [])!;
      expect(check.verdict(item('XIAOMI REDMI 17 4GB+128GB', 12689), x17, 'xiaomi 17'), PriceVerdict.none);
      final honor = check.reference('honor 600', const [])!;
      expect(check.verdict(item('HONOR 600 Pro 5G 512GB', 49999), honor, 'honor 600'), PriceVerdict.none);
    });

    test('knockoff prices on new entries are flagged', () {
      final pm = check.reference('iphone 17 pro max', const [])!;
      expect(check.verdict(item('iPhone 17 Pro Max 1TB Original', 8999), pm, 'iphone 17 pro max'),
          PriceVerdict.tooLow);
      final xm6 = check.reference('sony wh-1000xm6', const [])!;
      expect(check.verdict(item('Sony WH-1000XM6 Wireless Headphones', 1899), xm6, 'sony wh-1000xm6'),
          PriceVerdict.tooLow);
      final aw = check.reference('dyson airwrap', const [])!;
      expect(check.verdict(item('Dyson Airwrap 6 in 1 Hair Styler', 2499), aw, 'dyson airwrap'), PriceVerdict.tooLow);
      expect(check.verdict(item('Dyson Airwrap i.d. multi-styler', 27675, official: true), aw, 'dyson airwrap'),
          PriceVerdict.none);
    });

    test('games and accessories sharing a name are left alone', () {
      final mk = check.reference('mario kart world', const [])!;
      expect(check.verdict(item('Nintendo Switch 2 Console Mario Kart World Bundle', 34995), mk, 'mario kart world'),
          PriceVerdict.none);
      final ps5 = check.reference('ps5 slim', const [])!;
      expect(check.verdict(item('PS5 Slim Console Cover Chroma Teal', 4165), ps5, 'ps5 slim'), PriceVerdict.none);
    });
  });
}
