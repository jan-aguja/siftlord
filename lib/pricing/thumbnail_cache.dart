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
    final img = officialPhoto(ref, items);
    if (img == null) return;
    _prefs.setString(_key(entry.id), img);
    notifyListeners();
  }

  /// The photo of the best-ranked official listing that is the product at a
  /// believable price, so a game titled "Nintendo Switch 2 Yakuza Kiwami"
  /// can't stand in for the console. Null rather than a guess.
  static String? officialPhoto(PriceReference? ref, List<Item> items) {
    if (ref == null) return null;
    final byRank = [...items]..sort((a, b) => a.rank.compareTo(b.rank));
    for (final i in byRank) {
      final img = i.imageUrl;
      if (img == null || !i.isOfficial || i.isAd) continue;
      if (i.price < ref.low * PriceCheck.lowFactor || i.price > ref.high * PriceCheck.highFactor) continue;
      if (ref.claimedBy(i, strict: true)) return img;
    }
    return null;
  }
}
