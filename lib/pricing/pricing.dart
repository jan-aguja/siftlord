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
}
