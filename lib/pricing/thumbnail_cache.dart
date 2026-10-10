import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import 'price_check.dart';

/// Thumbnails for catalog products, learned on the phone: the first time a
/// search shows an official-store listing of the product, its image is kept.
/// The catalog itself ships no images.
class ThumbnailCache extends ChangeNotifier {
  ThumbnailCache._(this._prefs);

  static Future<ThumbnailCache> load() async =>
      ThumbnailCache._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static String _key(String productId) => 'thumb:$productId';

  String? forProduct(String productId) => _prefs.getString(_key(productId));

  void learnFrom(PriceReference? ref, List<Item> items) {
    final entry = ref?.entry;
    if (ref == null || entry == null || forProduct(entry.id) != null) return;
    for (final i in items) {
      final img = i.imageUrl;
      if (img != null && i.isOfficial && !i.isAd && ref.claimedBy(i, strict: true)) {
        _prefs.setString(_key(entry.id), img);
        notifyListeners();
        return;
      }
    }
  }
}
