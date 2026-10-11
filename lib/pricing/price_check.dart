import '../models/item.dart';
import 'catalog.dart';
import 'text_match.dart';

/// Where a search's usual price came from.
enum PriceSource { catalog, officialStores }

/// The usual price for what was searched, and how to tell which listings
/// claim to be that product.
class PriceReference {
  const PriceReference({
    required this.low,
    required this.high,
    required this.source,
    required this.queryWords,
    required this.productTokens,
    this.entry,
    this.officialCount = 0,
  });

  final double low;
  final double high;
  final PriceSource source;
  final CatalogEntry? entry;

  /// How many official listings the median came from.
  final int officialCount;
  final List<String> queryWords;

  /// Token lists a title must fully contain (one per product name/alias).
  final List<List<String>> productTokens;

  /// True when the listing says it's the product, and not an accessory for it.
  /// [strict] also rejects "for…/compatible" titles: right for picking
  /// reference prices, wrong for alerts, since knockoffs title themselves
  /// that way.
  bool claimedBy(Item item, {bool strict = false}) {
    final tw = words(item.title);
    if (!productTokens.any((t) => titleHasTokens(tw, t))) return false;
    return !looksLikeAccessory(tw, queryWords,
        excludePhrases: entry?.exclude ?? const [], strict: strict);
  }
}

enum PriceVerdict {
  none,
  tooLow,
  tooHigh,
  bigSale,

  /// Made *for* the product, not the product: a third-party accessory or
  /// knockoff. Shown whatever the price.
  thirdParty,
}

class PriceCheck {
  const PriceCheck(this.catalog);

  final Catalog catalog;

  /// Below this share of the usual low price, a listing is flagged.
  static const lowFactor = 0.6;

  /// The same on person-to-person markets, where used items selling well
  /// under retail is normal; unless the title says it's brand new.
  static const secondhandLowFactor = 0.35;

  /// An official listing below this share isn't a sale of the product but a
  /// different item that names it (Datablitz titles games "Nintendo Switch 2
  /// Yakuza Kiwami"): no tag, and it's never a "From" price.
  static const implausibleSaleFactor = 0.35;

  /// Above this multiple of the usual high price, a listing is flagged.
  static const highFactor = 1.5;

  /// Official-store references need at least this many matching listings.
  static const minOfficialListings = 2;

  /// 1. a catalog product, 2. else official stores in the results, 3. else none.
  PriceReference? reference(String query, List<Item> items) {
    final qw = words(query);
    final entry = catalog.match(query);
    if (entry != null) {
      return PriceReference(
        low: entry.minPrice,
        high: entry.maxPrice,
        source: PriceSource.catalog,
        entry: entry,
        queryWords: qw,
        productTokens: [for (final n in entry.allNames) queryTokens(n)],
      );
    }

    final tokens = queryTokens(query);
    if (tokens.isEmpty) return null;
    final probe = PriceReference(
      low: 0,
      high: 0,
      source: PriceSource.officialStores,
      queryWords: qw,
      productTokens: [tokens],
    );
    final prices = [
      for (final i in items)
        if (i.isOfficial && !i.isAd && probe.claimedBy(i, strict: true)) i.price,
    ];
    final median = robustMedian(prices);
    if (median == null) return null;
    return PriceReference(
      low: median.$1,
      high: median.$1,
      source: PriceSource.officialStores,
      officialCount: median.$2,
      queryWords: qw,
      productTokens: [tokens],
    );
  }

  /// The "From ₱…" price for a search: the cheapest listing that claims to be
  /// what was searched (not an accessory for it), skipping ads, used and
  /// sold-out items, "Third-party item"s, and anything well under the usual
  /// price ("Price looks off" or "Big sale" alike).
  Item? lowestFair(String query, List<Item> items, [PriceReference? ref]) {
    ref ??= reference(query, items);
    final tokens = queryTokens(query);
    final probe = ref ??
        (tokens.isEmpty
            ? null
            : PriceReference(
                low: 0,
                high: 0,
                source: PriceSource.officialStores,
                queryWords: words(query),
                productTokens: [tokens],
              ));
    if (probe == null) return null;
    Item? best;
    for (final i in items) {
      if (i.isAd || i.soldOut || i.condition == Condition.used || !probe.claimedBy(i)) continue;
      // Well under usual is never a "From" price, even an official "Big sale":
      // those are often a cheaper sibling ("Switch OLED / Switch 2 Console").
      if (ref != null && i.price < ref.low * lowFactor) continue;
      if (verdict(i, ref, query) == PriceVerdict.thirdParty) continue;
      if (best == null || i.price < best.price) best = i;
    }
    return best;
  }

  PriceVerdict verdict(Item item, PriceReference? ref, String query) {
    if (isThirdParty(item, ref, query)) return PriceVerdict.thirdParty;
    if (ref == null || !ref.claimedBy(item)) return PriceVerdict.none;
    final low = item.secondhandMarket && item.condition != Condition.brandNew
        ? secondhandLowFactor
        : lowFactor;
    if (item.price < ref.low * low) {
      if (!item.isOfficial) return PriceVerdict.tooLow;
      return item.price < ref.low * implausibleSaleFactor ? PriceVerdict.none : PriceVerdict.bigSale;
    }
    if (item.price > ref.high * highFactor) return PriceVerdict.tooHigh;
    return PriceVerdict.none;
  }
}

/// "For MacBook" charger vs "MacBook charger": the title says it's made for
/// the searched product. The brand's own official listings are exempt (Apple
/// does sell a "Smart Folio for iPad"); without a catalog brand, any official
/// listing is.
bool isThirdParty(Item item, PriceReference? ref, String query) {
  final qw = words(query);
  final tokenLists = ref?.productTokens ?? [queryTokens(query)];
  final tw = words(item.title);
  if (!tokenLists.any((t) => saysMadeFor(tw, t, qw))) return false;
  if (item.isOfficial) {
    final brand = ref?.entry?.brand?.toLowerCase();
    if (brand == null) return false;
    final sellerSide = '${item.brand ?? ''} ${item.shopName ?? ''}'.toLowerCase();
    if (sellerSide.contains(brand)) return false;
  }
  return true;
}

/// Median after dropping prices under half or over double the first median,
/// so a stray game or single earbud among consoles or earbuds can't skew it.
/// Returns the median and how many prices it used, or null below
/// [PriceCheck.minOfficialListings].
(double, int)? robustMedian(List<double> prices) {
  if (prices.length < PriceCheck.minOfficialListings) return null;
  final m = _median(prices);
  final kept = [for (final p in prices) if (p >= m * 0.5 && p <= m * 2) p];
  if (kept.length < PriceCheck.minOfficialListings) return null;
  return (_median(kept).roundToDouble(), kept.length);
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
