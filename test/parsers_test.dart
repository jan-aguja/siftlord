import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/stores/facebook.dart';
import 'package:siftlord/stores/lazada.dart';
import 'package:siftlord/stores/shopee.dart';
import 'package:siftlord/stores/store_adapter.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Lazada', () {
    final lazada = LazadaAdapter();

    test('parses list items and skips ones without a price', () {
      final items = lazada.parse(fixture('lazada_search.json'));
      expect(items, hasLength(3));

      final a = items[0];
      expect(a.title, startsWith('Air Pro ANC'));
      expect(a.price, 761.22);
      expect(a.originalPrice, 1155);
      expect(a.discountPercent, 34);
      expect(a.url.toString(), 'https://www.lazada.com.ph/products/pdp-i15431300487.html');
      expect(a.rating, 5.0);
      expect(a.ratingCount, 3);
      expect(a.soldCount, 16);
      expect(a.location, 'Pasay, Metro Manila');
      expect(a.isAd, isFalse);
      expect(a.sellerTier, SellerTier.regular);
      expect(a.brand, isNull, reason: '"No Brand" is no brand');

      final b = items[1];
      expect(b.isAd, isTrue);
      expect(b.isOfficial, isTrue);
      expect(b.storePick, 'LazPick');
      expect(b.brand, 'Apple');
      expect(b.soldCount, 2300);

      final c = items[2];
      expect(c.isOverseas, isTrue);
      expect(c.storePick, 'Lazada Choice');
    });

    test('HTML slider page means verification needed', () {
      expect(() => lazada.parse('<html>punish</html>'),
          throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.verification)));
    });

    test('classifies the anti-bot page', () {
      expect(lazada.classify(Uri.parse('https://www.lazada.com.ph/catalog/_____tmd_____/punish?x=1')),
          PageKind.verification);
      expect(lazada.classify(Uri.parse('https://www.lazada.com.ph/tag/airpods/?q=airpods')), PageKind.normal);
    });
  });

  group('Shopee', () {
    final shopee = ShopeeAdapter();

    test('parses current and old item formats', () {
      final items = shopee.parse(fixture('shopee_search.json'));
      expect(items, hasLength(5));

      final a = items[0];
      expect(a.title, 'AirPods Pro 3 (2025)');
      expect(a.price, 14290);
      expect(a.originalPrice, 14990);
      expect(a.url.toString(), 'https://shopee.ph/product/1275798143/27342482444');
      expect(a.soldCount, 15913);
      expect(a.soldText, '10K+ sold');
      expect(a.ratingCount, 4447);
      expect(a.shopName, 'Apple Flagship Store');
      expect(a.isOfficial, isTrue);
      expect(a.isAd, isFalse);
      expect(a.imageUrl, contains('ph-11134207-81ztl-mfkgizppuayw61'));

      expect(items[1].isAd, isTrue);
      expect(items[1].price, 99);
      expect(items[1].originalPrice, isNull);

      final old = items[2];
      expect(old.title, 'Old format item');
      expect(old.price, 250);
      expect(old.soldCount, 42);
      expect(old.sellerTier, SellerTier.preferredPlus);
      expect(old.isOverseas, isTrue, reason: 'cross-border even though it ships from Laguna');
      expect(old.location, 'Calamba City, Laguna');
      expect(old.fulfilledByStore, isTrue);
      expect(old.storePick, 'Shopee Choice');
      expect(old.shopName, 'Overseas Shop');
    });

    test('uses the card price, which already has Shopee\'s recommended voucher off', () {
      final items = shopee.parse(fixture('shopee_search.json'));
      final flip = items[3];
      expect(flip.price, 5999);
      expect(flip.priceBeforeVouchers, 6199);
      expect(flip.voucherSavings, 200);
      expect(flip.voucherLabel, 'shop voucher');
      expect(flip.originalPrice, 7999);

      // The card's variant (₱673 − ₱5 voucher), not the cheapest-variant ₱499.
      expect(items[4].price, 668);
      expect(items[4].voucherSavings, 5);

      // No vouchers: nothing to show.
      expect(items[0].voucherSavings, isNull);
      expect(items[2].voucherSavings, isNull);
    });

    test('logged-out error payload means sign-in needed', () {
      const raw = '{"5":false,"error":90309999,"1":"799de7a7","9":true}';
      expect(() => shopee.parse(raw),
          throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.login)));
    });

    test('classifies login and verify pages', () {
      expect(shopee.classify(Uri.parse('https://shopee.ph/verify/traffic/error?type=4')), PageKind.login);
      expect(shopee.classify(Uri.parse('https://shopee.ph/buyer/login?next=x')), PageKind.login);
      expect(shopee.classify(Uri.parse('https://shopee.ph/verify/captcha')), PageKind.verification);
      expect(shopee.classify(Uri.parse('https://shopee.ph/search?keyword=x')), PageKind.normal);
    });
  });

  group('Facebook Marketplace', () {
    final fb = FacebookMarketplaceAdapter(citySlug: 'cebucity');

    test('searches the chosen city', () {
      expect(fb.searchUrl('airpods').toString(),
          'https://www.facebook.com/marketplace/cebucity/search?query=airpods');
    });

    test('parses listings, skipping sold and free ones', () {
      final items = fb.parse(fixture('facebook_search.json'));
      expect(items.map((i) => i.title), ['Airpods pro gen 3', 'Apple AirPods Pro 3 Preloved', 'AirPods Pro 3 Brand New Sealed']);

      final a = items[0];
      expect(a.price, 4799);
      expect(a.url.toString(), 'https://www.facebook.com/marketplace/item/1000000000000001/');
      expect(a.location, 'Bacoor, Cavite');
      expect(a.deliveryNote, 'Meetup only');
      expect(a.secondhandMarket, isTrue);
      expect(a.shopName, isNull, reason: 'sellers are private people');
      expect(a.condition, isNull);

      expect(items[1].originalPrice, 10500);
      expect(items[1].condition, Condition.used);
      expect(items[1].deliveryNote, 'Can ship');
      expect(items[2].condition, Condition.brandNew);
    });

    test('a login page is a failure, not a sign-in prompt', () {
      expect(fb.allowSignIn, isFalse);
      expect(fb.classify(Uri.parse('https://www.facebook.com/login/?next=x')), PageKind.login);
    });
  });

  test('conditionFromTitle', () {
    expect(conditionFromTitle('iPhone 15 preloved'), Condition.used);
    expect(conditionFromTitle('Lightly used, like new'), Condition.used);
    expect(conditionFromTitle('BNEW sealed'), Condition.brandNew);
    expect(conditionFromTitle('AirPods Pro 3'), isNull);
  });

  test('prettyLocation', () {
    expect(prettyLocation('Metro Manila~Pasay'), 'Pasay, Metro Manila');
    expect(prettyLocation('Bulacan'), 'Bulacan');
    expect(prettyLocation(''), isNull);
    expect(prettyLocation(null), isNull);
  });

  test('parseSoldText', () {
    expect(parseSoldText('16 sold'), 16);
    expect(parseSoldText('1.2K sold'), 1200);
    expect(parseSoldText('10K+ sold'), 10000);
    expect(parseSoldText('1,234 sold'), 1234);
    expect(parseSoldText(null), isNull);
  });
}
