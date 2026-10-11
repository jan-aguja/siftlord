import '../models/item.dart';
import 'catalog.dart';
import 'price_check.dart';
import 'thumbnail_cache.dart';

/// Everything price-related the UI needs, loaded once at startup.
class Pricing {
  Pricing(this.catalog, this.thumbnails) : check = PriceCheck(catalog);

  static Future<Pricing> load() async =>
      Pricing(await Catalog.load(), await ThumbnailCache.load());

  final Catalog catalog;
  final PriceCheck check;
  final ThumbnailCache thumbnails;

  /// A picture for a search: the listing the user pinned, else the catalog
  /// product's learned photo, else an official listing of what was searched.
  /// Null (a placeholder) rather than a photo of the wrong thing.
  String? pictureFor(String query, List<Item> items, {Item? pinned}) {
    if (pinned?.imageUrl != null) return pinned!.imageUrl;
    final ref = check.reference(query, items);
    final entry = ref?.entry;
    final learned = entry == null ? null : thumbnails.forProduct(entry.id);
    return learned ?? ThumbnailCache.officialPhoto(ref, items);
  }
}
