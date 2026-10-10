import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// Shopee PH. Search needs the user to be signed in (in our WebView); logged
/// out, it redirects to `/verify/traffic/error` ("Login Required") and the
/// search API answers with an error code.
///
/// The page fetches results from `/api/v4/search/search_items`; a
/// document-start script wraps fetch and XHR and forwards that response.
class ShopeeAdapter extends StoreAdapter {
  @override
  String get id => 'shopee';
  @override
  String get name => 'Shopee';

  static const _searchApi = '/api/v4/search/search_items';

  /// Shopee prices are integers scaled by 100,000 (1429000000 = ₱14,290).
  static const _priceScale = 100000;

  @override
  Uri searchUrl(String query) =>
      Uri.https('shopee.ph', '/search', {'keyword': query});

  @override
  Uri get homeUrl => Uri.https('shopee.ph', '/');
  @override
  Uri get loginUrl => Uri.https('shopee.ph', '/buyer/login');

  @override
  String get documentStartScript => '''
$jsSendHelper
(function () {
  if (window.__siftShopeeHooked) return;
  window.__siftShopeeHooked = true;
  var MATCH = '$_searchApi';
  function hit(u) { return String(u || '').indexOf(MATCH) !== -1; }

  var origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url);
      var p = origFetch.apply(this, arguments);
      if (hit(url)) {
        p.then(function (r) { return r.clone().text(); })
         .then(function (t) { window.__siftSend(t); })
         .catch(function () {});
      }
      return p;
    };
  }

  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__siftUrl = url;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    if (hit(this.__siftUrl)) {
      this.addEventListener('load', function () {
        try {
          var t = (this.responseType === '' || this.responseType === 'text')
            ? this.responseText : JSON.stringify(this.response);
          window.__siftSend(t);
        } catch (e) {}
      });
    }
    return origSend.apply(this, arguments);
  };
})();
''';

  @override
  PageKind classify(Uri url) {
    if (url.host != 'shopee.ph') return PageKind.normal;
    if (url.path.startsWith('/buyer/login') ||
        url.path.startsWith('/verify/traffic/error')) {
      return PageKind.login;
    }
    if (url.path.startsWith('/verify/')) return PageKind.verification;
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
      throw const StoreBlocked(PageKind.verification, 'unexpected payload');
    }
    final list = decoded['items'];
    final error = decoded['error'];
    if (list is! List) {
      // Logged out we saw {"error":90309999,...} with no items.
      if (error != null) {
        throw StoreBlocked(PageKind.login, 'error $error');
      }
      return const [];
    }

    final items = <Item>[];
    for (final (i, e) in list.indexed) {
      if (e is! Map<String, dynamic>) continue;
      final item = _parseCard(e, i) ?? _parseBasic(e, i);
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Current format: `item_card_displayed_asset` + `item_data`.
  Item? _parseCard(Map<String, dynamic> e, int rank) {
    final asset = e['item_card_displayed_asset'];
    final data = e['item_data'];
    if (asset is! Map<String, dynamic> || data is! Map<String, dynamic>) {
      return null;
    }
    final title = asset['name'] as String?;
    final priceInfo = data['item_card_display_price'] as Map<String, dynamic>?;
    final price = _price(priceInfo?['price']);
    final url = _productUrl(data['shopid'] ?? e['shopid'], data['itemid'] ?? e['itemid']);
    if (title == null || price == null || url == null) return null;

    final rating = data['item_rating'] as Map<String, dynamic>?;
    final counts = rating?['rating_count'];
    final sold = data['item_card_display_sold_count'] as Map<String, dynamic>?;
    final soldText = _blankToNull(sold?['historical_sold_count_text']) ??
        _blankToNull((asset['sold_count'] as Map<String, dynamic>?)?['text']);
    final flag = (asset['seller_flag'] as Map<String, dynamic>?)?['name'];

    return Item(
      storeId: id,
      rank: rank,
      title: title,
      price: price,
      originalPrice: _price(priceInfo?['strikethrough_price']) ??
          _price(priceInfo?['original_price']),
      url: url,
      imageUrl: _image(asset['image'] as String?),
      rating: (rating?['rating_star'] as num?)?.toDouble(),
      ratingCount: counts is List && counts.isNotEmpty ? counts.first as int? : null,
      soldCount: sold?['historical_sold_count'] as int? ?? parseSoldText(soldText),
      soldText: soldText,
      location: asset['shop_location'] as String?,
      shopName: (data['shop_data'] as Map<String, dynamic>?)?['shop_name'] as String?,
      isAd: _isAd(e),
      isOfficial: flag == 'OFFICIAL_SHOP',
    );
  }

  /// Older format some Shopee pages still serve: `item_basic`.
  Item? _parseBasic(Map<String, dynamic> e, int rank) {
    final b = e['item_basic'];
    if (b is! Map<String, dynamic>) return null;
    final title = b['name'] as String?;
    final price = _price(b['price']) ?? _price(b['price_min']);
    final url = _productUrl(b['shopid'], b['itemid']);
    if (title == null || price == null || url == null) return null;
    final rating = b['item_rating'] as Map<String, dynamic>?;
    final counts = rating?['rating_count'];
    final sold = b['historical_sold'] as int? ?? b['sold'] as int?;
    return Item(
      storeId: id,
      rank: rank,
      title: title,
      price: price,
      originalPrice: _price(b['price_before_discount']),
      url: url,
      imageUrl: _image(b['image'] as String?),
      rating: (rating?['rating_star'] as num?)?.toDouble(),
      ratingCount: counts is List && counts.isNotEmpty ? counts.first as int? : null,
      soldCount: sold,
      soldText: sold == null ? null : '$sold sold',
      location: b['shop_location'] as String?,
      isAd: _isAd(e) || e['adsid'] != null,
      isOfficial: b['is_official_shop'] == true,
    );
  }

  bool _isAd(Map<String, dynamic> e) {
    final tracking = e['search_item_tracking'];
    if (tracking is String && tracking.isNotEmpty) {
      try {
        final t = jsonDecode(tracking);
        if (t is Map && t['is_ads'] == true) return true;
      } on FormatException {
        // fall through
      }
    }
    return false;
  }

  double? _price(Object? v) {
    if (v is! num || v <= 0) return null;
    return v / _priceScale;
  }

  Uri? _productUrl(Object? shopId, Object? itemId) {
    if (shopId == null || itemId == null) return null;
    return Uri.https('shopee.ph', '/product/$shopId/$itemId');
  }

  String? _image(String? hash) {
    if (hash == null || hash.isEmpty) return null;
    if (hash.startsWith('http')) return hash;
    return 'https://down-ph.img.susercontent.com/file/${hash}_tn';
  }
}

String? _blankToNull(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}
