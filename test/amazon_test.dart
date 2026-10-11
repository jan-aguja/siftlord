import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/stores/amazon.dart';
import 'package:siftlord/stores/store_adapter.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Matcher blockedAs(PageKind kind) =>
    throwsA(isA<StoreBlocked>().having((e) => e.kind, 'kind', kind));

void main() {
  final us = AmazonAdapter(AmazonStorefront.us);
  final jp = AmazonAdapter(AmazonStorefront.jp);
  final uk = AmazonAdapter(AmazonStorefront.uk);

  test('storefronts', () {
    expect([us.id, jp.id, uk.id], ['amazon-us', 'amazon-jp', 'amazon-uk']);
    expect([us.name, jp.name, uk.name], ['Amazon US', 'Amazon JP', 'Amazon UK']);
    expect([us.country, jp.country, uk.country], ['US', 'JP', 'GB']);
    expect([us.currency, jp.currency, uk.currency], ['USD', 'JPY', 'GBP']);
    expect(us.desktopMode, isTrue);
    expect(us.loadStopScript, contains('s-search-result'));
  });

  test('URLs', () {
    expect(us.searchUrl('airpods pro').toString(), 'https://www.amazon.com/s?k=airpods+pro');
    expect(jp.searchUrl('イヤホン').toString(),
        'https://www.amazon.co.jp/s?k=%E3%82%A4%E3%83%A4%E3%83%9B%E3%83%B3');
    expect(uk.searchUrl('usb c').toString(), 'https://www.amazon.co.uk/s?k=usb+c');
    expect(uk.homeUrl.toString(), 'https://www.amazon.co.uk/');
    expect(jp.loginUrl.toString(), 'https://www.amazon.co.jp/gp/sign-in.html');
  });

  group('Amazon US (USD)', () {
    final items = us.parse(fixture('amazon_us_search.json'));

    test('skips the unpriced result, keeps store order', () {
      expect(items.map((i) => i.rank), [1, 2, 3, 4]);
      expect(items.every((i) => i.storeId == 'amazon-us' && i.currency == 'USD'), isTrue);
      expect(items.any((i) => i.isAd), isFalse);
    });

    test('a result card', () {
      final a = items[0];
      expect(a.title, startsWith('Wireless Ear Buds (2nd Generation)'));
      expect(a.price, 39.99);
      expect(a.originalPrice, isNull);
      expect(a.url.toString(), 'https://www.amazon.com/dp/B0HHXKMCYY');
      expect(a.imageUrl, 'https://m.media-amazon.com/images/I/51boaCR4VLL._AC_UY218_.jpg');
      expect(a.rating, 5.0);
      expect(a.ratingCount, 2);
      expect(a.soldText, '50+ bought in past month');
      expect(a.soldCount, 50);
      expect(a.deliveryNote, startsWith('FREE delivery Fri, Oct 30 to Philippines'));
      expect(a.condition, isNull);
    });

    test("Amazon's Choice and brand", () {
      final b = items[1];
      expect(b.brand, 'Apple');
      expect(b.storePick, "Amazon's Choice");
      expect(b.price, 125.61);
      expect(b.ratingCount, 15262);
      expect(b.deliveryNote, isNull);
    });

    test('list price strikethrough', () {
      expect(items[2].price, 189.99);
      expect(items[2].originalPrice, 249.99);
      expect(items[2].discountPercent, 24);
      expect(items[2].soldCount, 10000);
      expect(items[3].originalPrice, 59.99);
      expect(items[3].brand, 'Soundcore');
    });

    test('round-trips with its currency', () {
      final back = Item.fromJson(items[0].toJson());
      expect(back.currency, 'USD');
      expect(back.price, 39.99);
    });
  });

  group('Amazon JP (yen, Japanese page)', () {
    final items = jp.parse(fixture('amazon_jp_search.json'));

    test('yen without decimals', () {
      expect(items.map((i) => i.rank), [1, 2, 3, 4]);
      expect(items.every((i) => i.currency == 'JPY'), isTrue);
      expect(items.map((i) => i.price), [3799, 3599, 749, 1963]);
      expect(items[0].originalPrice, 4599);
      expect(items[2].originalPrice, isNull);
    });

    test('Japanese ratings, counts and bought text', () {
      final a = items[0];
      expect(a.rating, 4.0);
      expect(a.ratingCount, 115);
      expect(a.soldText, '過去1か月で700点以上購入されました');
      expect(a.soldCount, 700);
      expect(items[2].ratingCount, 41969);
      expect(items[2].soldCount, 1000);
      expect(items[3].soldCount, 10000, reason: '1万点以上');
      expect(a.url.toString(), 'https://www.amazon.co.jp/dp/B0GTLQ5548');
      expect(a.deliveryNote, '配送料 ￥2,410 10月19日 月曜日にお届け フィリピンに発送');
    });
  });

  group('Amazon UK (converted to pesos)', () {
    final items = uk.parse(fixture('amazon_uk_search.json'));

    test('sponsored results are ads; unpriced ones are skipped', () {
      expect(items.map((i) => i.rank), [0, 2, 3, 4]);
      expect(items[0].isAd, isTrue);
      expect(items.skip(1).any((i) => i.isAd), isFalse);
    });

    test('currency comes from the price text, not the storefront', () {
      expect(items.every((i) => i.currency == 'PHP'), isTrue);
      expect(items[0].price, 780.01);
      expect(items[0].originalPrice, 995.99);
      expect(items[0].deliveryNote, 'PHP 1,858.23 delivery Thu 15 Oct Delivers to Philippines');
      expect(items[1].storePick, "Amazon's Choice");
      expect(items[3].price, 2400.67);
      expect(items[3].originalPrice, 2491.21);
    });
  });

  group('result details', () {
    List<Item> one(AmazonAdapter a, Map<String, Object?> fields) {
      final r = {
        'asin': 'B0TEST0001',
        'title': 'Thing',
        'price': '\$10.00',
        ...fields,
      };
      return a.parse(jsonEncode({'results': [r]}));
    }

    test('ad titles lose the "Sponsored Ad -" prefix', () {
      final i = one(us, {'title': 'Sponsored Ad - Amazon 3ft USB to USB-C Cable', 'sponsored': true}).single;
      expect(i.title, 'Amazon 3ft USB to USB-C Cable');
      expect(i.isAd, isTrue);
    });

    test('renewed items are used', () {
      expect(one(uk, {'title': 'AirPods Pro (2nd Gen) (Renewed)', 'price': '£149.00'}).single.condition,
          Condition.used);
      expect(one(us, {'title': 'AirPods 4', 'brand': 'Amazon Renewed'}).single.condition, Condition.used);
      expect(one(jp, {'title': 'iPhone 13 整備済み品', 'price': '￥45,800'}).single.condition, Condition.used);
    });

    test('GBP prices and a list price in another currency is ignored', () {
      final i = one(uk, {'price': '£12.99', 'listPrice': '£19.99'}).single;
      expect(i.currency, 'GBP');
      expect(i.price, 12.99);
      expect(i.originalPrice, 19.99);
      expect(one(uk, {'price': '£12.99', 'listPrice': 'PHP 1,999.00'}).single.originalPrice, isNull);
      expect(one(uk, {'price': '£12.99', 'listPrice': '£9.99'}).single.originalPrice, isNull);
    });

    test('Prime means fulfilled by Amazon; stock notes are not delivery notes', () {
      final i = one(us, {'prime': true, 'delivery': 'Only 3 left in stock.', 'badge': 'best-seller'}).single;
      expect(i.fulfilledByStore, isTrue);
      expect(i.deliveryNote, isNull);
      expect(i.storePick, 'Best Seller');
    });

    test('bad ASINs, missing titles and zero prices are dropped', () {
      expect(one(us, {'asin': ''}), isEmpty);
      expect(one(us, {'asin': 'not-an-asin'}), isEmpty);
      expect(one(us, {'title': '  '}), isEmpty);
      expect(one(us, {'price': '\$0.00'}), isEmpty);
      expect(one(us, {'price': null}), isEmpty);
    });
  });

  group('parseAmazonPrice', () {
    ({double amount, String currency})? p(String? s, [String fb = 'USD']) =>
        parseAmazonPrice(s, fallbackCurrency: fb);

    test('per storefront', () {
      expect(p('\$1,299.99'), (amount: 1299.99, currency: 'USD'));
      expect(p('￥4,980', 'JPY'), (amount: 4980.0, currency: 'JPY'));
      expect(p('¥1,234,567', 'JPY'), (amount: 1234567.0, currency: 'JPY'));
      expect(p('£12.99', 'GBP'), (amount: 12.99, currency: 'GBP'));
      expect(p('£1,049.00', 'GBP'), (amount: 1049.0, currency: 'GBP'));
    });

    test('converted prices carry an ISO code', () {
      expect(p('PHP 2,508.97'), (amount: 2508.97, currency: 'PHP'));
      expect(p('PHP 7,880.77', 'GBP'), (amount: 7880.77, currency: 'PHP'));
      expect(p('USD 39.99', 'JPY'), (amount: 39.99, currency: 'USD'));
    });

    test('labels are not currencies', () {
      expect(p('参考: ￥4,599', 'JPY'), (amount: 4599.0, currency: 'JPY'));
      expect(p('RRP: £24.99', 'GBP'), (amount: 24.99, currency: 'GBP'));
      expect(p('List: \$59.99'), (amount: 59.99, currency: 'USD'));
    });

    test('European formats', () {
      expect(p('1.299,99 €'), (amount: 1299.99, currency: 'EUR'));
      expect(p('12,50 €'), (amount: 12.5, currency: 'EUR'));
    });

    test('falls back to the storefront currency', () {
      expect(p('4,980', 'JPY'), (amount: 4980.0, currency: 'JPY'));
    });

    test('nothing to read', () {
      expect(p(null), isNull);
      expect(p(''), isNull);
      expect(p('See options'), isNull);
    });
  });

  test('parseAmazonNumber', () {
    expect(parseAmazonNumber('1,299.99'), 1299.99);
    expect(parseAmazonNumber('4,980'), 4980);
    expect(parseAmazonNumber('749'), 749);
    expect(parseAmazonNumber('12.99'), 12.99);
    expect(parseAmazonNumber('1.299,99'), 1299.99);
    expect(parseAmazonNumber('1.234.567'), 1234567);
    expect(parseAmazonNumber('12,5'), 12.5);
    expect(parseAmazonNumber(''), isNull);
  });

  test('parseAmazonRating', () {
    expect(parseAmazonRating('4.1 out of 5 stars'), 4.1);
    expect(parseAmazonRating('5つ星のうち4.6'), 4.6);
    expect(parseAmazonRating('4,5 von 5 Sternen'), 4.5);
    expect(parseAmazonRating(null), isNull);
    expect(parseAmazonRating('No reviews'), isNull);
  });

  test('parseAmazonBought', () {
    expect(parseAmazonBought('2K+ bought in past month'), 2000);
    expect(parseAmazonBought('50+ bought in past month'), 50);
    expect(parseAmazonBought('過去1か月で700点以上購入されました'), 700);
    expect(parseAmazonBought('過去1か月で1000点以上購入されました'), 1000);
    expect(parseAmazonBought('過去1か月で1万点以上購入されました'), 10000);
    expect(parseAmazonBought(null), isNull);
  });

  group('blocks', () {
    test('CAPTCHA and robot pages need the user', () {
      expect(() => us.parse('{"blocked": "captcha"}'), blockedAs(PageKind.verification));
      expect(() => uk.parse('{"blocked": "robot"}'), blockedAs(PageKind.verification));
      expect(() => jp.parse('<html>Enter the characters you see below</html>'),
          blockedAs(PageKind.verification));
    });

    test('sign-in and script errors', () {
      expect(() => us.parse('{"blocked": "signin"}'), blockedAs(PageKind.login));
      expect(() => us.parse('{"siftError": "TypeError"}'), blockedAs(PageKind.normal));
      expect(() => us.parse('{"host": "www.amazon.com"}'), blockedAs(PageKind.normal));
    });

    test('no results is an empty list', () {
      expect(us.parse('{"host": "www.amazon.com", "results": []}'), isEmpty);
    });
  });

  test('classifies pages', () {
    expect(us.classify(Uri.parse('https://www.amazon.com/s?k=airpods')), PageKind.normal);
    expect(us.classify(Uri.parse('https://www.amazon.com/errors/validateCaptcha?amzn=x')),
        PageKind.verification);
    expect(jp.classify(Uri.parse('https://www.amazon.co.jp/errors/validateCaptcha')), PageKind.verification);
    expect(uk.classify(Uri.parse('https://www.amazon.co.uk/ap/signin?openid.mode=checkid_setup')),
        PageKind.login);
    expect(us.classify(Uri.parse('https://www.amazon.com/ap/cvf/request')), PageKind.verification);
    // Another storefront's host is not this one's business.
    expect(us.classify(Uri.parse('https://www.amazon.co.jp/errors/validateCaptcha')), PageKind.normal);
  });

  test('brand goes in front of titles that lack it', () {
    expect(AmazonAdapter.withBrand("Men's Club II Era Shoes", 'PUMA'), "PUMA Men's Club II Era Shoes");
    expect(AmazonAdapter.withBrand('PUMA CLUB 2 ERA Suede', 'PUMA(プーマ)'), 'PUMA CLUB 2 ERA Suede');
    expect(AmazonAdapter.withBrand('Flip 7', null), 'Flip 7');
  });
}
