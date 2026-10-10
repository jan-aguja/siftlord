import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/stores/lazada.dart';
import 'package:siftlord/stores/shopee.dart';
import 'package:siftlord/stores/store_adapter.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('Lazada', () {
    final lazada = LazadaAdapter();

    test('parses list items and skips ones without a price', () {
      final items = lazada.parse(fixture('lazada_search.json'));
      expect(items, hasLength(2));

      final a = items[0];
      expect(a.title, startsWith('Air Pro ANC'));
      expect(a.price, 761.22);
      expect(a.originalPrice, 1155);
      expect(a.discountPercent, 34);
      expect(a.url.toString(), 'https://www.lazada.com.ph/products/pdp-i15431300487.html');
      expect(a.rating, 5.0);
      expect(a.ratingCount, 3);
      expect(a.soldCount, 16);
      expect(a.location, isNull);
      expect(a.isAd, isFalse);

      final b = items[1];
      expect(b.isAd, isTrue);
      expect(b.isOfficial, isTrue);
      expect(b.soldCount, 2300);
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
      expect(items, hasLength(3));

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

      expect(items[2].title, 'Old format item');
      expect(items[2].price, 250);
      expect(items[2].soldCount, 42);
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

  test('parseSoldText', () {
    expect(parseSoldText('16 sold'), 16);
    expect(parseSoldText('1.2K sold'), 1200);
    expect(parseSoldText('10K+ sold'), 10000);
    expect(parseSoldText('1,234 sold'), 1234);
    expect(parseSoldText(null), isNull);
  });
}
