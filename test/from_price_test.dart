import 'package:flutter_test/flutter_test.dart';
import 'package:siftlord/models/item.dart';
import 'package:siftlord/pricing/catalog.dart';
import 'package:siftlord/pricing/price_check.dart';
import 'package:siftlord/pricing/thumbnail_cache.dart';

final check = PriceCheck(Catalog.parse('''
{"products": [{"id": "flip-7", "name": "JBL Flip 7", "brand": "JBL", "aliases": ["flip 7"],
  "price": {"min": 6000, "max": 7000}, "checked": "2026-10-11"}]}
'''));

Item listing(String title, double price,
        {bool ad = false, bool soldOut = false, Condition? condition, SellerTier tier = SellerTier.regular,
        String? image, int rank = 0}) =>
    Item(
      imageUrl: image,
      storeId: 'shopee',
      title: title,
      price: price,
      url: Uri.parse('https://x.example/$title/$price'),
      rank: rank,
      isAd: ad,
      soldOut: soldOut,
      condition: condition,
      sellerTier: tier,
    );

void main() {
  test('From price skips bait, third-party, accessories, ads, used and sold out', () {
    final items = [
      listing('JBL Flip 7 Waterproof Speaker', 1200), // price looks off
      listing('Speaker for JBL Flip 7 compatible', 900), // third-party
      listing('JBL Flip 7 Case Hard Shell', 400), // accessory
      listing('JBL Flip 7 Speaker', 5000, ad: true),
      listing('JBL Flip 7 Used', 4500, condition: Condition.used),
      listing('JBL Flip 7 Black', 5200, soldOut: true),
      listing('JBL Flip 7 Blue', 5800),
      listing('JBL Flip 7 Strap Set', 700, tier: SellerTier.mall), // official, but not the speaker
      listing('JBL Flip 7 Red', 6490, tier: SellerTier.mall),
    ];
    expect(check.lowestFair('jbl flip 7', items)?.price, 5800);
  });

  test('official listings far below usual are another item, not a sale', () {
    final ref = check.reference('jbl flip 7', const [])!;
    expect(check.verdict(listing('JBL Flip 7 Red', 3500, tier: SellerTier.mall), ref, 'jbl flip 7'),
        PriceVerdict.bigSale);
    expect(check.verdict(listing('JBL Flip 7 Lanyard', 1500, tier: SellerTier.mall), ref, 'jbl flip 7'),
        PriceVerdict.none);
    expect(check.lowestFair('jbl flip 7', [listing('JBL Flip 7 Red', 3500, tier: SellerTier.mall)]), isNull,
        reason: 'a big sale still deserves a look before it becomes the From price');
  });

  test('without a usual price, still needs the searched words', () {
    final items = [
      listing('Silicone case', 99),
      listing('Anker Soundcore Motion 300', 3990),
      listing('Anker Soundcore Motion 300 Black', 3790),
    ];
    expect(check.lowestFair('soundcore motion 300', items)?.price, 3790);
    expect(check.lowestFair('soundcore motion 300', const []), isNull);
  });

  test('a search picture comes only from an official listing at a believable price', () {
    final ref = check.reference('jbl flip 7', const []);
    final items = [
      listing('JBL Flip 7 Strap', 700, tier: SellerTier.mall, image: 'strap', rank: 0),
      listing('JBL Flip 7 Speaker', 5900, image: 'random seller', rank: 1),
      listing('JBL Flip 7 Speaker Red', 6990, tier: SellerTier.mall, image: 'official', rank: 2),
    ];
    expect(ThumbnailCache.officialPhoto(ref, items), 'official');
    expect(ThumbnailCache.officialPhoto(ref, items.sublist(0, 2)), isNull);
  });
}
