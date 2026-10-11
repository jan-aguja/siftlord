/// How much the store vouches for the seller, highest first.
enum SellerTier { mall, preferredPlus, preferred, regular }

/// Item condition, where the store says or the title makes it clear.
enum Condition { brandNew, used }

/// One product listing, normalized across stores.
class Item {
  const Item({
    required this.storeId,
    required this.title,
    required this.price,
    required this.url,
    required this.rank,
    this.originalPrice,
    this.imageUrl,
    this.rating,
    this.ratingCount,
    this.soldCount,
    this.soldText,
    this.location,
    this.shopName,
    this.brand,
    this.isAd = false,
    this.sellerTier = SellerTier.regular,
    this.isOverseas = false,
    this.fulfilledByStore = false,
    this.storePick,
    this.condition,
    this.secondhandMarket = false,
    this.deliveryNote,
    this.priceBeforeVouchers,
    this.voucherLabel,
    this.soldOut = false,
    this.voucherCode,
  });

  final String storeId;
  final String title;

  /// Price in pesos as the store shows it on the result card: after the
  /// vouchers the store applies there (see [priceBeforeVouchers]).
  final double price;

  /// The price before the store's own recommended vouchers, when the store
  /// already took them off [price] on its search card. Coins and checkout
  /// promos are never included: search results don't show them.
  final double? priceBeforeVouchers;

  /// What was taken off, e.g. "shop voucher".
  final String? voucherLabel;

  /// The code to enter at checkout for that voucher, when the store gives one.
  final String? voucherCode;
  final double? originalPrice;
  final Uri url;

  /// Position in the store's own result order (0 = first).
  final int rank;

  final String? imageUrl;
  final double? rating;
  final int? ratingCount;
  final int? soldCount;
  final String? soldText;

  /// Where the item ships from, as the store reports it ("Pasay, Metro Manila").
  final String? location;
  final String? shopName;
  final String? brand;
  final bool isAd;
  final SellerTier sellerTier;

  /// Cross-border seller. Can be true even when [location] is a local
  /// warehouse.
  final bool isOverseas;

  /// Stocked and shipped by the store itself (Shopee "Service by Shopee").
  final bool fulfilledByStore;

  /// The store's own curation label ("LazPick", "Shopee Choice").
  final String? storePick;

  final Condition? condition;

  /// From a person-to-person market (Facebook Marketplace) where used items
  /// are normal, so prices run lower than retail.
  final bool secondhandMarket;

  /// How you'd get it, when that isn't plain shipping ("Meetup only").
  final String? deliveryNote;

  /// Listed but out of stock.
  final bool soldOut;

  /// Same listing across refreshes (prices and titles change; the link doesn't).
  String get key => url.toString();

  Map<String, Object?> toJson() => {
        'store': storeId,
        'title': title,
        'price': price,
        'url': url.toString(),
        'rank': rank,
        if (originalPrice != null) 'originalPrice': originalPrice,
        if (imageUrl != null) 'image': imageUrl,
        if (rating != null) 'rating': rating,
        if (ratingCount != null) 'ratingCount': ratingCount,
        if (soldCount != null) 'soldCount': soldCount,
        if (soldText != null) 'soldText': soldText,
        if (location != null) 'location': location,
        if (shopName != null) 'shop': shopName,
        if (brand != null) 'brand': brand,
        if (isAd) 'ad': true,
        if (sellerTier != SellerTier.regular) 'tier': sellerTier.name,
        if (isOverseas) 'overseas': true,
        if (fulfilledByStore) 'fulfilled': true,
        if (storePick != null) 'pick': storePick,
        if (condition != null) 'condition': condition!.name,
        if (secondhandMarket) 'secondhand': true,
        if (deliveryNote != null) 'delivery': deliveryNote,
        if (priceBeforeVouchers != null) 'beforeVouchers': priceBeforeVouchers,
        if (voucherLabel != null) 'voucher': voucherLabel,
        if (soldOut) 'soldOut': true,
        if (voucherCode != null) 'voucherCode': voucherCode,
      };

  factory Item.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return Item(
      storeId: j['store'] as String,
      title: j['title'] as String,
      price: d('price')!,
      url: Uri.parse(j['url'] as String),
      rank: j['rank'] as int? ?? 0,
      originalPrice: d('originalPrice'),
      imageUrl: j['image'] as String?,
      rating: d('rating'),
      ratingCount: j['ratingCount'] as int?,
      soldCount: j['soldCount'] as int?,
      soldText: j['soldText'] as String?,
      location: j['location'] as String?,
      shopName: j['shop'] as String?,
      brand: j['brand'] as String?,
      isAd: j['ad'] == true,
      sellerTier: SellerTier.values.asNameMap()[j['tier']] ?? SellerTier.regular,
      isOverseas: j['overseas'] == true,
      fulfilledByStore: j['fulfilled'] == true,
      storePick: j['pick'] as String?,
      condition: Condition.values.asNameMap()[j['condition']],
      secondhandMarket: j['secondhand'] == true,
      deliveryNote: j['delivery'] as String?,
      priceBeforeVouchers: d('beforeVouchers'),
      voucherLabel: j['voucher'] as String?,
      soldOut: j['soldOut'] == true,
      voucherCode: j['voucherCode'] as String?,
    );
  }

  bool get isOfficial => sellerTier == SellerTier.mall;

  double? get voucherSavings {
    final before = priceBeforeVouchers;
    return before == null || before <= price ? null : before - price;
  }

  int? get discountPercent {
    final orig = originalPrice;
    if (orig == null || orig <= price) return null;
    return ((1 - price / orig) * 100).round();
  }
}

/// Parses "16 sold", "1.2K sold", "10K+ sold" into a rough count.
int? parseSoldText(String? text) {
  if (text == null) return null;
  final m = RegExp(r'([\d.,]+)\s*([KkMm]?)').firstMatch(text);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!.replaceAll(',', ''));
  if (n == null) return null;
  final mult = switch (m.group(2)!.toUpperCase()) {
    'K' => 1000,
    'M' => 1000000,
    _ => 1,
  };
  return (n * mult).round();
}

String? blankToNull(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty || s == 'null' ? null : s;
}

/// Lazada writes "Metro Manila~Pasay"; show it the way Shopee does, city first.
String? prettyLocation(Object? raw) {
  final s = blankToNull(raw);
  if (s == null) return null;
  final parts = s.split('~').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.length < 2) return s;
  return '${parts.sublist(1).join(', ')}, ${parts.first}';
}

const _foreignLocations = {
  'overseas', 'mainland china', 'china', 'hong kong', 'korea', 'south korea',
  'japan', 'taiwan', 'singapore', 'malaysia', 'thailand', 'vietnam', 'indonesia',
  'united states', 'usa',
};

bool isForeignLocation(String? location) =>
    location != null && _foreignLocations.contains(location.trim().toLowerCase());

const _usedWords = ['preloved', 'pre loved', 'used', 'second hand', '2nd hand', 'secondhand', 'lightly used', 'pre owned', 'refurbished'];
const _newWords = ['brand new', 'bnew', 'sealed', 'bnib', 'unopened'];

/// Reads condition from the words sellers put in titles. "Lightly used"
/// wins over "new"; returns null when the title doesn't say.
Condition? conditionFromTitle(String title) {
  final t = ' ${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  if (_usedWords.any((w) => t.contains(' $w '))) return Condition.used;
  if (_newWords.any((w) => t.contains(' $w '))) return Condition.brandNew;
  return null;
}
