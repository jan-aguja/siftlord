import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/money/money.dart';
import 'package:siftlord/money/rates.dart';
import 'package:siftlord/pricing/catalog.dart';
import 'package:siftlord/pricing/price_check.dart';

final rates = Rates(null, perEuro: {'PHP': 70.0, 'USD': 1.1, 'JPY': 175.0, 'GBP': 0.85});

final check = PriceCheck(Catalog.parse('''
{"products": [{"id": "flip-7", "name": "JBL Flip 7", "brand": "JBL", "aliases": ["flip 7"],
  "price": {"min": 6000, "max": 7000}, "checked": "2026-10-11"}]}
'''));

Item listing(String title, double price, String currency) => Item(
      storeId: currency == 'PHP' ? 'lazada' : 'amazon',
      title: title,
      price: price,
      url: Uri.parse('https://x.example/$currency/$price'),
      rank: 0,
      currency: currency,
    );

void main() {
  test('formats per currency', () {
    expect(formatMoney(31995, 'PHP'), '₱31,995');
    expect(formatMoney(1299.99, 'USD'), '\$1,299.99');
    expect(formatMoney(4980, 'JPY'), '¥4,980');
    expect(formatMoney(4980.4, 'JPY'), '¥4,980', reason: 'yen has no minor unit');
    expect(formatMoney(12.5, 'GBP'), '£12.50');
    expect(formatMoney(1919.6, 'PHP', whole: true), '₱1,920');
    expect(formatMoney(10, 'XYZ'), 'XYZ 10');
  });

  test('converts through the euro, null without a rate', () {
    expect(rates.convert(4980, 'JPY', 'PHP'), closeTo(1992, 0.01));
    expect(rates.convert(10, 'EUR', 'USD'), closeTo(11, 0.001));
    expect(rates.convert(5, 'PHP', 'PHP'), 5);
    expect(rates.convert(5, 'XYZ', 'PHP'), isNull);
    expect(rates.currencies, containsAll(['EUR', 'PHP', 'JPY']));
  });

  test('currency survives JSON; old saved items are pesos', () {
    final yen = Item.fromJson(listing('Thing', 4980, 'JPY').toJson());
    expect(yen.currency, 'JPY');
    final old = listing('Thing', 100, 'PHP').toJson()..remove('cur');
    expect(Item.fromJson(old).currency, 'PHP');
  });

  test('foreign listings are never judged against peso prices', () {
    final ref = check.reference('jbl flip 7', const [])!;
    expect(check.verdict(listing('JBL Flip 7', 99.95, 'USD'), ref, 'jbl flip 7'), PriceVerdict.none,
        reason: '\$99.95 is not a ₱99.95 fake');
    final amazonInPesos = Item(
      storeId: 'amazon-us',
      title: 'JBL Flip 7',
      price: 3000,
      url: Uri.parse('https://www.amazon.com/dp/B0TEST'),
      rank: 0,
      country: 'US',
    );
    expect(check.verdict(amazonInPesos, ref, 'jbl flip 7'), PriceVerdict.none,
        reason: 'Amazon showing pesos is still a US listing, not a PH bait price');
  });

  test('From compares at today\'s rate and skips unconvertible listings', () {
    double? toPhp(double a, String c) => rates.convert(a, c, 'PHP');
    final items = [
      listing('JBL Flip 7 Black', 6990, 'PHP'),
      listing('JBL Flip 7 Blue', 89.99, 'USD'), // ≈ ₱5,727
      listing('JBL Flip 7 Red', 10, 'XYZ'),
    ];
    expect(check.lowestFair('jbl flip 7', items, toMarket: toPhp)?.currency, 'USD');
    expect(check.lowestFair('jbl flip 7', items)?.currency, 'PHP', reason: 'no rates: local only');
    expect(check.lowestFair('jbl flip 7', [listing('JBL Flip 7', 20, 'USD')], toMarket: toPhp), isNull,
        reason: 'still under 0.6× usual once converted');
  });
}
