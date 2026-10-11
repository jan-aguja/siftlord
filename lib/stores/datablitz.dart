import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// Datablitz, a Philippine games and gadgets retailer. Works logged out.
///
/// Verified 2026-10-11: the site is Shopify, but its `/search` page renders no
/// product cards server-side. A search app (Boost Product Filter & Search)
/// fills them in by loading `services.mybcapps.com/bc-sf-filter/search` as
/// JSONP (so wrapping fetch/XHR wouldn't see it). The same endpoint answers
/// plain JSON with `Access-Control-Allow-Origin: *`, so the load-stop script
/// repeats that request from inside the page with the page's own config
/// (`boostPFSConfig`), 48 per page, and sends back a trimmed copy (the full
/// answer carries every product's description, ~7 KB each).
///
/// Prices are pesos as decimals (`price_min`, variant `price`); they match
/// what the page shows and Shopify's `/products/<handle>.js`. The `*_php`
/// fields are stale market prices: ignore them. Some variants carry a
/// `compare_at_price` below their price, so only a higher one counts.
/// Sold-out items stay in the list (ranked last by `sort_first=available`)
/// marked sold out. "Pre-Order Downpayment" products are dropped:
/// their price is a deposit, not the item's price, and would set off the
/// price check. Results match loosely (a "ps5" search is mostly accessories);
/// the order is the store's relevance order.
///
/// Datablitz is the retailer itself (an authorized one for Sony, Nintendo,
/// Microsoft, Valve...), so every item counts as an official listing. Everything is new, so no
/// condition is set (a "New" badge on every card would be noise).
class DatablitzAdapter extends StoreAdapter {
  static const _host = 'ecommerce.datablitz.com.ph';

  @override
  String get id => 'datablitz';
  @override
  String get name => 'Datablitz';

  @override
  Uri searchUrl(String query) => Uri.https(_host, '/search', {'q': query});

  @override
  Uri get homeUrl => Uri.https(_host, '/');
  @override
  Uri get loginUrl => Uri.https(_host, '/account/login');

  @override
  String get loadStopScript => '''
$jsSendHelper
(function () {
  var q = new URLSearchParams(location.search).get('q') || '';
  if (window.__siftDatablitzDone || !q) return;
  window.__siftDatablitzDone = true;
  var cfg = window.boostPFSConfig || {};
  var api = (cfg.api && cfg.api.searchUrl) || 'https://services.mybcapps.com/bc-sf-filter/search';
  var shop = (cfg.shop && cfg.shop.domain) || 'datablitz-inc.myshopify.com';
  var url = api + '?_=pf&shop=' + encodeURIComponent(shop) + '&q=' + encodeURIComponent(q) +
    '&page=1&limit=48&sort=relevance&product_available=false&variant_available=false' +
    '&build_filter_tree=false&check_cache=false&sort_first=available&enable_plus_character_search=true&event_type=init';
  fetch(url)
    .then(function (r) { return r.text(); })
    .then(function (t) {
      var d;
      try { d = JSON.parse(t); } catch (e) { window.__siftSend(t.slice(0, 2000)); return; }
      if (!d || !Array.isArray(d.products)) { window.__siftSend(JSON.stringify(d)); return; }
      window.__siftSend(JSON.stringify({
        total_product: d.total_product,
        products: d.products.map(function (p) {
          return {
            id: p.id, title: p.title, handle: p.handle, vendor: p.vendor,
            product_type: p.product_type, available: p.available,
            price_min: p.price_min, compare_at_price_min: p.compare_at_price_min,
            images_info: (p.images_info || []).slice(0, 1).map(function (i) { return { src: i.src }; }),
            variants: (p.variants || []).map(function (v) {
              return { id: v.id, title: v.title, price: v.price, compare_at_price: v.compare_at_price, available: v.available };
            })
          };
        })
      }));
    })
    .catch(function (e) { window.__siftSend(JSON.stringify({ siftError: String(e) })); });
})();
''';

  @override
  PageKind classify(Uri url) {
    final p = url.path;
    if (p.startsWith('/challenge') || p.contains('/checkpoint')) {
      return PageKind.verification;
    }
    if (p.startsWith('/account/login')) return PageKind.login;
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
    if (decoded is! Map<String, dynamic>) {
      throw const StoreBlocked(PageKind.normal, 'unexpected payload');
    }
    if (decoded['siftError'] != null) {
      throw StoreBlocked(PageKind.normal, '${decoded['siftError']}');
    }
    final list = decoded['products'];
    if (list is! List) {
      final why = decoded['message'] ?? decoded['error'] ?? 'no products';
      throw StoreBlocked(PageKind.normal, '$why');
    }

    final items = <Item>[];
    for (final (i, e) in list.indexed) {
      if (e is! Map<String, dynamic>) continue;
      final title = blankToNull(e['title']);
      final handle = blankToNull(e['handle']);
      if (title == null || handle == null) continue;
      if (_isDownpayment(title)) continue;

      final variants = [
        for (final v in (e['variants'] as List? ?? const []))
          if (v is Map<String, dynamic> && _num(v['price']) != null) v,
      ];
      final available = e['available'] != false;
      // The cheapest variant you can buy; when none can be, the cheapest one.
      final pool = available ? variants.where((v) => v['available'] != false).toList() : variants;
      Map<String, dynamic>? cheapest;
      for (final v in pool) {
        if (cheapest == null || _num(v['price'])! < _num(cheapest['price'])!) cheapest = v;
      }
      final price = cheapest != null ? _num(cheapest['price']) : _num(e['price_min']);
      if (price == null || price <= 0) continue;
      final compare = cheapest != null ? _num(cheapest['compare_at_price']) : _num(e['compare_at_price_min']);

      final images = e['images_info'];
      final image = images is List && images.isNotEmpty && images.first is Map
          ? blankToNull((images.first as Map)['src'])
          : null;

      items.add(Item(
        storeId: id,
        rank: i,
        title: title,
        price: price,
        originalPrice: compare != null && compare > price ? compare : null,
        url: Uri.https(_host, '/products/$handle'),
        imageUrl: image == null ? null : (image.startsWith('//') ? 'https:$image' : image),
        brand: blankToNull(e['vendor']),
        sellerTier: SellerTier.mall,
        soldOut: !available,
      ));
    }
    return items;
  }

  static bool _isDownpayment(String title) {
    final t = title.toLowerCase();
    return t.contains('downpayment') || t.contains('down payment');
  }

  static double? _num(Object? v) => v == null ? null : double.tryParse('$v');
}
