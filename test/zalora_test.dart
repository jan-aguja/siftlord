import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/stores/store_adapter.dart';
import 'package:siftlord/stores/zalora.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  final zalora = ZaloraAdapter();

  test('search URL', () {
    expect(zalora.searchUrl('air force 1').toString(),
        'https://www.zalora.com.ph/search?q=air+force+1');
  });

  group('parse', () {
    final items = zalora.parse(fixture('zalora_search.json'));

    test('keeps every product in order', () {
      expect(items, hasLength(5));
      expect(items.map((i) => i.rank), [0, 1, 2, 3, 4]);
      expect(items.every((i) => i.storeId == 'zalora'), isTrue);
      expect(items.any((i) => i.isAd), isFalse);
    });

    test('marketplace seller with a voucher', () {
      final a = items[0];
      expect(a.title, 'Suede Classic');
      expect(a.brand, 'PUMA');
      expect(a.price, 2750, reason: '50% off voucher, as on Zalora\'s card');
      expect(a.priceBeforeVouchers, 5500);
      expect(a.voucherSavings, 2750);
      expect(a.voucherLabel, 'voucher');
      expect(a.voucherCode, '1050BASE62605');
      expect(a.originalPrice, isNull, reason: 'no markdown, only a voucher');
      expect(a.url.toString(), 'https://www.zalora.com.ph/p/puma-suede-classic-green-3453619');
      expect(a.imageUrl, startsWith('https://dynamic.zacdn.com/'));
      expect(a.imageUrl, endsWith('puma-4170-9163543-1.jpg'));
      expect(a.rating, 4.8);
      expect(a.ratingCount, 20);
      expect(a.shopName, 'PUMA Official Store.');
      expect(a.fulfilledByStore, isFalse);
      expect(a.sellerTier, SellerTier.regular, reason: 'a seller name is not a badge');
    });

    test('Zalora stock with a markdown and a voucher on top', () {
      final b = items[1];
      expect(b.title, '530 Lifestyle Shoes');
      expect(b.brand, 'New Balance');
      expect(b.price, 5707.8);
      expect(b.priceBeforeVouchers, 6342);
      expect(b.originalPrice, 6795);
      expect(b.discountPercent, 16);
      expect(b.fulfilledByStore, isTrue);
      expect(b.shopName, isNull, reason: 'SupplierName is the supplier, not the seller');
    });

    test('voucher whose min spend the item misses is ignored', () {
      final c = items[2];
      expect(c.title, 'ARMR Slides');
      expect(c.price, 1795);
      expect(c.priceBeforeVouchers, isNull);
      expect(c.voucherLabel, isNull);
      expect(c.fulfilledByStore, isTrue);
    });

    test('local marketplace seller', () {
      final d = items[3];
      expect(d.brand, 'World Balance');
      expect(d.price, 1749.3);
      expect(d.priceBeforeVouchers, 2499);
      expect(d.shopName, 'CHG GLOBAL Inc.');
      expect(d.rating, 4.5);
      expect(d.ratingCount, 2);
    });

    test('pre-loved item, no reviews', () {
      final e = items[4];
      expect(e.brand, 'Christian Dior');
      expect(e.condition, Condition.used);
      expect(e.price, 46080);
      expect(e.priceBeforeVouchers, 46230);
      expect(e.rating, isNull);
      expect(e.ratingCount, isNull);
      expect(e.shopName, 'RECLO JAPAN');
    });
  });

  test('works without the promotions answer', () {
    final raw = fixture('zalora_search.json')
        .replaceFirst(RegExp(r'"promotions":\s*\{[\s\S]*\}\s*\}\s*$'), '"promotions": null}');
    final items = zalora.parse(raw);
    expect(items, hasLength(5));
    expect(items[0].price, 5500);
    expect(items[1].price, 6342);
    expect(items[1].originalPrice, 6795);
  });

  test('Buy-N cart rules and card promos are not applied', () {
    final items = zalora.parse('''
{"list": {"data": {"Products": [{"ConfigSku": "X1", "Name": "Tokyo Shoes", "Brand": "ADIDAS",
  "PriceInDecimal": 4300, "SpecialPriceInDecimal": 0, "ProductUrl": "p/adidas-tokyo-shoes-white-4312266",
  "DepartmentCode": "RBO", "AdId": ""}]}},
 "promotions": {"data": {"Promotions": {"X1": [
   {"TemplateType": "campaign_cart_rule", "EffectivePrice": 3870, "IsPaymentPromotion": false},
   {"TemplateType": "campaign_voucher", "EffectivePrice": 3500, "IsPaymentPromotion": true}]},
  "BestStackableCombination": {"X1": {"EffectivePrice": 3870}}}}}''');
    expect(items.single.price, 4300);
    expect(items.single.priceBeforeVouchers, isNull);
  });

  test('no results is an empty list', () {
    expect(zalora.parse('{"list": {"data": {"NumProductFound": 0, "Products": null}}}'), isEmpty);
    expect(zalora.parse('{"list": {"data": {"NumProductFound": 0, "Products": []}}}'), isEmpty);
  });

  test('blocks and errors', () {
    expect(() => zalora.parse('<html>Access denied</html>'),
        throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.verification)));
    expect(() => zalora.parse('{"appId": "PXabc123", "blockScript": "/x/captcha.js"}'),
        throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.verification)));
    expect(() => zalora.parse('{"list": {"err_code": 1000, "err_info": "shop value can\'t be recognised"}}'),
        throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.normal)));
    expect(() => zalora.parse('{"siftError": "TypeError: Load failed"}'),
        throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', PageKind.normal)));
  });

  test('classifies pages', () {
    expect(zalora.classify(Uri.parse('https://www.zalora.com.ph/search?q=sneakers')), PageKind.normal);
    expect(zalora.classify(Uri.parse('https://www.zalora.com.ph/login')), PageKind.login);
  });
}
