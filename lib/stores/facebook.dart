import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// A city Facebook Marketplace accepts in its URL. Logged out, the city in
/// the URL is the only location control: coordinates and radius are ignored.
class MarketplaceCity {
  const MarketplaceCity(this.slug, this.label);

  /// Facebook's city name in the URL, or a numeric city-page ID.
  final String slug;
  final String label;
}

/// Verified 2026-10-11. Unrecognized names (e.g. "baguio", "cebu") silently
/// fall back to a network-guessed location, so only add checked ones.
const marketplaceCities = [
  MarketplaceCity('manila', 'Metro Manila'),
  MarketplaceCity('quezoncity', 'Quezon City'),
  MarketplaceCity('makati', 'Makati'),
  MarketplaceCity('pasig', 'Pasig'),
  MarketplaceCity('taguig', 'Taguig'),
  MarketplaceCity('antipolo', 'Antipolo'),
  MarketplaceCity('cebucity', 'Cebu City'),
  MarketplaceCity('davaocity', 'Davao City'),
  MarketplaceCity('iloilocity', 'Iloilo City'),
  MarketplaceCity('cagayandeoro', 'Cagayan de Oro'),
];

/// Facebook Marketplace, searched logged out, never with the user's account.
///
/// The mobile "lite" page leaves out listing links when logged out
/// (`LOGGED_OUT_EXCLUDE_PERMALINK`), so this store uses the desktop page,
/// which embeds each listing as `GroupCommerceProductItem` JSON in
/// `<script type="application/json">` blobs. Seller names are dropped:
/// these are private people, not shops.
class FacebookMarketplaceAdapter extends StoreAdapter {
  FacebookMarketplaceAdapter({this.citySlug = 'manila'});

  /// Changed from the store settings.
  String citySlug;

  @override
  String get id => 'facebook';
  @override
  String get name => 'Marketplace';

  @override
  bool get desktopMode => true;

  @override
  bool get allowSignIn => false;

  @override
  Uri searchUrl(String query) =>
      Uri.https('www.facebook.com', '/marketplace/$citySlug/search', {'query': query});

  @override
  Uri get homeUrl => Uri.https('www.facebook.com', '/marketplace/$citySlug/');
  @override
  Uri get loginUrl => homeUrl;

  @override
  String get loadStopScript => '''
$jsSendHelper
(function () {
  if (window.__siftFbDone) return;
  var tries = 0;
  function collect() {
    var out = {}, n = 0;
    function walk(o, d) {
      if (!o || typeof o !== 'object' || d > 60) return;
      if (o.__typename === 'GroupCommerceProductItem' && o.marketplace_listing_title && o.id) {
        if (!out[o.id]) {
          var geo = (o.location && o.location.reverse_geocode) || {};
          out[o.id] = {
            id: o.id,
            title: o.marketplace_listing_title,
            price: o.listing_price && o.listing_price.amount,
            strike: o.strikethrough_price && o.strikethrough_price.amount,
            place: (geo.city_page && geo.city_page.display_name) || geo.city || null,
            photo: o.primary_listing_photo && o.primary_listing_photo.image && o.primary_listing_photo.image.uri,
            sold: !!o.is_sold, pending: !!o.is_pending, hidden: !!o.is_hidden,
            delivery: o.delivery_types || []
          };
          n++;
        }
        return;
      }
      var vals = Array.isArray(o) ? o : Object.values(o);
      for (var i = 0; i < vals.length; i++) walk(vals[i], d + 1);
    }
    var blobs = document.querySelectorAll('script[type="application/json"]');
    for (var i = 0; i < blobs.length; i++) {
      try { walk(JSON.parse(blobs[i].textContent), 0); } catch (e) {}
    }
    return { n: n, listings: Object.values(out) };
  }
  (function poll() {
    var r = collect();
    if (r.n > 0 || ++tries >= 16) {
      window.__siftFbDone = true;
      window.__siftSend(JSON.stringify({ listings: r.listings }));
      return;
    }
    setTimeout(poll, 400);
  })();
})();
''';

  @override
  PageKind classify(Uri url) {
    final p = url.path;
    if (p.startsWith('/login') || p.contains('/checkpoint')) return PageKind.login;
    return PageKind.normal;
  }

  @override
  List<Item> parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const StoreBlocked(PageKind.verification, 'non-JSON response');
    }
    final list = decoded is Map<String, dynamic> ? decoded['listings'] : null;
    if (list is! List) return const [];

    final items = <Item>[];
    for (final e in list) {
      if (e is! Map<String, dynamic>) continue;
      if (e['sold'] == true || e['pending'] == true || e['hidden'] == true) continue;
      final id = blankToNull(e['id']);
      final title = blankToNull(e['title']);
      final price = double.tryParse('${e['price']}');
      if (id == null || title == null || price == null || price <= 0) continue;
      final strike = double.tryParse('${e['strike']}');
      final delivery = {for (final d in (e['delivery'] as List? ?? const [])) '$d'};
      items.add(Item(
        storeId: this.id,
        rank: items.length,
        title: title,
        price: price,
        originalPrice: strike != null && strike > price ? strike : null,
        url: Uri.https('www.facebook.com', '/marketplace/item/$id/'),
        imageUrl: blankToNull(e['photo']),
        location: blankToNull(e['place']),
        condition: conditionFromTitle(title),
        secondhandMarket: true,
        deliveryNote: delivery.contains('SHIPPING_OFFSITE') ? 'Can ship' : 'Meetup only',
      ));
    }
    return items;
  }
}
