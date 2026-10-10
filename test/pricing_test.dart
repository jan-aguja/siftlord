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
      expect(catalog.suggest('flip').map((e) => e.id), ['jbl-flip-7']);
      expect(catalog.suggest('a'), isEmpty);
    });
  });

  group('reference price', () {
    test('catalog product uses the catalog range', () {
      final ref = check.reference('airpods pro 3', const [])!;
      expect(ref.source, PriceSource.catalog);
      expect((ref.low, ref.high), (14290, 14990));
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
      expect(check.verdict(item('Apple AirPods Pro 3', 1499, official: true), ref, 'airpods pro 3'), PriceVerdict.bigSale);
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
}
