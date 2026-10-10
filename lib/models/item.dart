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
    this.isAd = false,
    this.isOfficial = false,
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
  final String? location;
  final String? shopName;
  final bool isAd;
  final bool isOfficial;

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
