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
  });

  final String storeId;
  final String title;

  /// Price in pesos as the store shows it on the result card.
  final double price;
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

  bool get isOfficial => sellerTier == SellerTier.mall;

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
