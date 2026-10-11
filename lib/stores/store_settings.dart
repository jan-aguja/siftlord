import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

import 'facebook.dart';
import 'store_adapter.dart';

/// Which stores new searches use, the Marketplace city, and how results are
/// shown. Remembered on the phone.
class StoreSettings extends ChangeNotifier {
  StoreSettings._(this._prefs, this.stores) {
    _applyCity();
  }

  static Future<StoreSettings> load(List<StoreAdapter> stores) async =>
      StoreSettings._(await SharedPreferences.getInstance(), stores);

  final SharedPreferences _prefs;
  final List<StoreAdapter> stores;

  /// On until the user turns them off. Marketplace starts off: it's a
  /// different kind of market (people, used items, meetups).
  static const _defaultOn = {'lazada', 'shopee'};

  static String _key(String storeId) => 'store_on:$storeId';
  static const _cityKey = 'marketplace_city';

  bool isEnabled(String storeId) => _prefs.getBool(_key(storeId)) ?? _defaultOn.contains(storeId);

  void setEnabled(String storeId, bool on) {
    _prefs.setBool(_key(storeId), on);
    if (on) _prefs.setInt(_onAtKey(storeId), DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  static String _onAtKey(String storeId) => 'store_on_at:$storeId';

  /// Stores that are on, most recently turned on first (defaults keep their
  /// built-in order below those), then the ones that are off. The side menu
  /// lists them this way, so the stores someone actually uses rise to the top.
  List<StoreAdapter> get orderedStores {
    final base = {for (final (i, s) in stores.indexed) s.id: i};
    int onAt(StoreAdapter s) => _prefs.getInt(_onAtKey(s.id)) ?? 0;
    final on = [for (final s in stores) if (isEnabled(s.id)) s]
      ..sort((a, b) {
        final r = onAt(b).compareTo(onAt(a));
        return r != 0 ? r : base[a.id]!.compareTo(base[b.id]!);
      });
    return [...on, for (final s in stores) if (!isEnabled(s.id)) s];
  }

  List<StoreAdapter> get enabledStores => [for (final s in orderedStores) if (isEnabled(s.id)) s];

  static const _cleanupKey = 'auto_cleanup_days';

  /// Choices for removing unhearted searches nobody refreshed in a while.
  static const cleanupChoices = [7, 14, 30, 90];

  /// Days after which unhearted searches go; null (the default) keeps them.
  int? get autoCleanupDays => _prefs.getInt(_cleanupKey);

  set autoCleanupDays(int? days) {
    days == null ? _prefs.remove(_cleanupKey) : _prefs.setInt(_cleanupKey, days);
    notifyListeners();
  }

  MarketplaceCity get marketplaceCity {
    final slug = _prefs.getString(_cityKey);
    return marketplaceCities.firstWhere((c) => c.slug == slug, orElse: () => marketplaceCities.first);
  }

  set marketplaceCity(MarketplaceCity city) {
    _prefs.setString(_cityKey, city.slug);
    _applyCity();
    notifyListeners();
  }

  static const _currencyKey = 'home_currency';

  /// The currency prices are shown in; foreign listings are converted to it.
  /// Pesos until the user picks otherwise (country onboarding comes later).
  String get homeCurrency => _prefs.getString(_currencyKey) ?? 'PHP';

  set homeCurrency(String c) {
    _prefs.setString(_currencyKey, c);
    notifyListeners();
  }

  static const _sideKey = 'app_side';

  /// Dark Side unless the user picks otherwise.
  AppSide get side => AppSide.values.asNameMap()[_prefs.getString(_sideKey)] ?? AppSide.dark;

  set side(AppSide s) {
    _prefs.setString(_sideKey, s.name);
    notifyListeners();
  }

  static const _listViewKey = 'results_list_view';

  /// Card (one at a time) is the default; the last choice sticks.
  bool get listView => _prefs.getBool(_listViewKey) ?? false;

  set listView(bool on) {
    _prefs.setBool(_listViewKey, on);
    notifyListeners();
  }

  void _applyCity() {
    for (final s in stores) {
      if (s is FacebookMarketplaceAdapter) s.citySlug = marketplaceCity.slug;
    }
  }
}
