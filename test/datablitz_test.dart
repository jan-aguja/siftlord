import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/stores/datablitz.dart';
import 'package:siftlord/stores/store_adapter.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final datablitz = DatablitzAdapter();

  group('Datablitz', () {
    test('parses Boost search products', () {
      final items = datablitz.parse(fixture('datablitz_search.json'));
      expect(items.map((i) => i.title), [
        'Nintendo Switch 2 Console',
        'PS5 Ghost of Yotei (Asian)',
        'PS5 Ghost of Yotei Collectors Edition (Asian)',
        'Steam Deck OLED (512GB, 1TB)',
      ], reason: 'the pre-order downpayment is dropped');

      final sw = items[0];
      expect(sw.storeId, 'datablitz');
      expect(sw.rank, 0);
      expect(sw.price, 31995, reason: 'price, not the stale price_php');
      expect(sw.originalPrice, isNull);
      expect(sw.url.toString(),
          'https://ecommerce.datablitz.com.ph/products/nintendo-switch-2-console-sea-bee-s-kb5aa-phl');
      expect(sw.imageUrl, startsWith('https://cdn.shopify.com/s/files/'));
      expect(sw.brand, 'Nintendo');
      expect(sw.isOfficial, isTrue);
      expect(sw.condition, isNull);
      expect(sw.soldOut, isFalse);

      final yotei = items[1];
      expect(yotei.price, 3385);
      expect(yotei.originalPrice, 4003);
      expect(yotei.discountPercent, 15);

      final collectors = items[2];
      expect(collectors.soldOut, isTrue);
      expect(collectors.price, 12920);

      final deck = items[3];
      expect(deck.price, 54995, reason: 'cheapest variant in stock');
      expect(deck.originalPrice, isNull, reason: 'a compare-at below the price is ignored');
      expect(deck.soldOut, isFalse);
    });

    test('error payloads are blocked, not empty results', () {
      expect(() => datablitz.parse('<html>Access denied</html>'),
          throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.verification)));
      expect(() => datablitz.parse('{"siftError":"TypeError: Failed to fetch"}'),
          throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.normal)));
      expect(() => datablitz.parse('{"message":"Invalid shop"}'), throwsA(isA<StoreBlocked>()));
    });

    test('no matches is an empty list', () {
      expect(datablitz.parse('{"total_product":0,"products":[]}'), isEmpty);
    });

    test('search URL and page kinds', () {
      expect(datablitz.searchUrl('ps5 slim').toString(),
          'https://ecommerce.datablitz.com.ph/search?q=ps5+slim');
      expect(datablitz.classify(Uri.parse('https://ecommerce.datablitz.com.ph/search?q=ps5')), PageKind.normal);
      expect(datablitz.classify(Uri.parse('https://ecommerce.datablitz.com.ph/challenge')), PageKind.verification);
      expect(datablitz.classify(Uri.parse('https://ecommerce.datablitz.com.ph/account/login')), PageKind.login);
    });
  });
}
