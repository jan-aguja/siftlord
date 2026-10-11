import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// Zalora PH. Works logged out, with a mobile or desktop user agent.
///
/// The search page is a Next.js app whose server HTML (`__NEXT_DATA__`) has no
/// products: the page fetches them from `api.zalora.com.ph`, which allows
/// `www.zalora.com.ph` as a CORS origin with credentials. So, like Lazada's
/// `?ajax=true` fallback, the script makes the same two requests the page
/// makes (verified 2026-10-11):
///
/// - `/v1/dynproducts/datajet/list?query=…&shop=m` → `data.Products`, the
///   organic results. Sponsored items come from a separate
///   `/v1/products/sponsored` call, which we skip; `AdId` is still honoured
///   in case ads ever land in this list.
/// - `/v1/promotions?config_sku=…` → each item's vouchers with Zalora's own
///   `EffectivePrice` (min spend already checked: 0 when the item alone
///   doesn't reach it). Zalora's result card shows that price, so we do too,
///   with the listed price as [Item.priceBeforeVouchers]. "Buy 3" cart rules
///   and bank/card promos are left out: buying one item doesn't get them.
///
/// Both answer in protobuf unless asked for `Accept: application/json`.
/// The site runs PerimeterX; a block comes back as JSON with `appId`/
/// `blockScript` instead of `data`.
class ZaloraAdapter extends StoreAdapter {
  @override
  String get id => 'zalora';
  @override
  String get name => 'Zalora';

  static const _host = 'www.zalora.com.ph';

  /// The `shop` value the page itself sends ("main"; `w`/`men` are rejected).
  static const _shop = 'm';

  /// `DepartmentCode` for marketplace sellers. Everything else (`RBO`, `RBC`,
  /// `LBO`, …) is Zalora's own retail stock, sold and shipped by Zalora.
  static const _marketplace = 'MP';

  @override
  Uri searchUrl(String query) => Uri.https(_host, '/search', {'q': query});

  @override
  Uri get homeUrl => Uri.https(_host, '/');
  @override
  Uri get loginUrl => Uri.https(_host, '/login');

  @override
  String get loadStopScript => '''
$jsSendHelper
(function () {
  if (window.__siftZaloraDone) return;
  window.__siftZaloraDone = true;
  var q = new URLSearchParams(location.search).get('q') || '';
  var api = 'https://api.zalora.com.ph/v1/';
  var opts = { credentials: 'include', headers: { Accept: 'application/json' } };
  function get(u) { return fetch(u, opts).then(function (r) { return r.text(); }); }
  get(api + 'dynproducts/datajet/list?shop=$_shop&image_format=webp&image_quality=70' +
      '&image_resize=304.8x440&limit=36&offset=0&query=' + encodeURIComponent(q))
    .then(function (t) {
      var list;
      try { list = JSON.parse(t); } catch (e) { window.__siftSend(t); return; }
      var ps = (list && list.data && list.data.Products) || [];
      if (!ps.length) { window.__siftSend(JSON.stringify({ list: list })); return; }
      var skus = ps.map(function (p) { return 'config_sku=' + encodeURIComponent(p.ConfigSku); });
      return get(api + 'promotions?' + skus.join('&'))
        .then(function (pt) { try { return JSON.parse(pt); } catch (e) { return null; } },
              function () { return null; })
        .then(function (promo) {
          window.__siftSend(JSON.stringify({ list: list, promotions: promo }));
        });
    })
    .catch(function (e) { window.__siftSend(JSON.stringify({ siftError: String(e) })); });
})();
''';

  @override
  PageKind classify(Uri url) {
    if (!url.host.endsWith('zalora.com.ph')) return PageKind.normal;
    final p = url.path;
    if (p.startsWith('/login') || p.startsWith('/customer/account/login')) {
      return PageKind.login;
    }
    if (p.contains('captcha') || p.contains('/blocked')) return PageKind.verification;
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
    if (decoded['siftError'] != null) {
      throw StoreBlocked(PageKind.normal, '${decoded['siftError']}');
    }
    final list = decoded['list'];
    if (list is! Map<String, dynamic>) {
      // The script forwards a bare non-wrapped body only when it was a block.
      _throwIfBlocked(decoded);
      throw const StoreBlocked(PageKind.normal, 'unexpected payload');
    }
    _throwIfBlocked(list);
    final data = list['data'];
    final products = data is Map<String, dynamic> ? data['Products'] : null;
    if (products is! List) return const [];

    final promos = _Promotions.from(decoded['promotions']);
    final items = <Item>[];
    for (final (i, e) in products.indexed) {
      if (e is! Map<String, dynamic>) continue;
      final item = _parseProduct(e, i, promos);
      if (item != null) items.add(item);
    }
    return items;
  }

  /// PerimeterX answers blocked XHRs with `{appId: "PX…", blockScript, …}`;
  /// the API's own errors look like `{err_code, err_info}`.
  void _throwIfBlocked(Map<String, dynamic> m) {
    final appId = '${m['appId'] ?? ''}';
    if (appId.startsWith('PX') || m['blockScript'] != null || m['action'] == 'captcha') {
      throw const StoreBlocked(PageKind.verification, 'PerimeterX block');
    }
    if (m['err_code'] != null) {
      throw StoreBlocked(PageKind.normal, 'error ${m['err_code']}: ${m['err_info']}');
    }
  }

  Item? _parseProduct(Map<String, dynamic> e, int rank, _Promotions promos) {
    final title = blankToNull(e['Name']);
    final url = _productUrl(e['ProductUrl']);
    final regular = _amount(e['PriceInDecimal']) ?? _pesoText(e['Price']);
    final special = _amount(e['SpecialPriceInDecimal']) ?? _pesoText(e['SpecialPrice']);
    if (title == null || url == null || regular == null) return null;

    final listed = special != null && special < regular ? special : regular;
    final voucher = promos.best(blankToNull(e['ConfigSku']));
    final withVoucher = voucher != null && voucher.price < listed ? voucher.price : null;

    final reviews = e['ReviewStatistics'];
    final reviewCount = reviews is Map ? (reviews['ReviewCount'] as num?)?.toInt() : null;
    final hasReviews = reviewCount != null && reviewCount > 0;
    final soldByZalora = blankToNull(e['DepartmentCode']) != _marketplace;
    final official = e['OfficialstoreInformation'];
    final breadcrumbs = [for (final b in (e['Breadcrumbs'] as List? ?? const [])) '$b'.toLowerCase()];

    return Item(
      storeId: id,
      rank: rank,
      title: title,
      price: withVoucher ?? listed,
      priceBeforeVouchers: withVoucher == null ? null : listed,
      voucherLabel: withVoucher == null ? null : voucher!.code == null ? 'vouchers' : 'voucher',
      voucherCode: withVoucher == null ? null : voucher!.code,
      originalPrice: listed < regular ? regular : null,
      url: url,
      imageUrl: blankToNull(e['MainImageUrl']) ??
          ((e['ImageList'] as List?)?.isNotEmpty == true ? '${(e['ImageList'] as List).first}' : null),
      rating: hasReviews ? (reviews['AvgRating'] as num?)?.toDouble() : null,
      ratingCount: hasReviews ? reviewCount : null,
      brand: blankToNull(e['Brand']),
      // For Zalora's own stock `SupplierName` is the brand/distributor it
      // bought from (often "ZALORA", sometimes "PUMA Official Store."), not
      // who sells it, so only marketplace items get a shop name.
      shopName: soldByZalora ? null : blankToNull(e['SupplierName']),
      isAd: blankToNull(e['AdId']) != null,
      // Only Zalora's own official-store badge counts as mall; a seller name
      // with "Official" in it doesn't. (Empty on every item seen so far.)
      sellerTier: official is Map && blankToNull(official['Label']) != null
          ? SellerTier.mall
          : SellerTier.regular,
      fulfilledByStore: soldByZalora,
      condition: breadcrumbs.contains('pre-loved') ? Condition.used : conditionFromTitle(title),
    );
  }

  /// Zalora writes product links relative: `p/puma-suede-classic-green-3453619`.
  Uri? _productUrl(Object? raw) {
    final s = blankToNull(raw);
    if (s == null) return null;
    if (s.startsWith('http')) return Uri.tryParse(s);
    return Uri.https(_host, s.startsWith('/') ? s : '/$s');
  }

  double? _amount(Object? v) => v is num && v > 0 ? v.toDouble() : null;

  /// "Php 5,500.00" → 5500.
  double? _pesoText(Object? v) {
    final s = blankToNull(v)?.replaceAll(RegExp(r'[^\d.]'), '');
    final n = s == null ? null : double.tryParse(s);
    return n != null && n > 0 ? n : null;
  }
}

/// The `/v1/promotions` answer: per-SKU vouchers and Zalora's best stack.
class _Promotions {
  const _Promotions(this._bySku, this._bestStack);

  factory _Promotions.from(Object? raw) {
    final data = raw is Map ? raw['data'] : null;
    if (data is! Map) return const _Promotions({}, {});
    final promos = data['Promotions'];
    final best = data['BestStackableCombination'];
    return _Promotions(
      promos is Map ? promos.cast<String, Object?>() : const {},
      best is Map ? best.cast<String, Object?>() : const {},
    );
  }

  final Map<String, Object?> _bySku;
  final Map<String, Object?> _bestStack;

  /// Lowest price a single buyer of just this item gets with Zalora's
  /// vouchers, and the code to type at checkout when it's one voucher (a
  /// stack of several has no single code).
  ({double price, String? code})? best(String? sku) {
    if (sku == null) return null;
    final list = _bySku[sku];
    if (list is! List) return null;
    ({double price, String? code})? best;
    var stackIsSafe = true;
    for (final p in list) {
      if (p is! Map) continue;
      final type = '${p['TemplateType']}';
      if (p['IsPaymentPromotion'] == true || type.contains('cart_rule')) {
        // "Buy 3, get 10% off" or a bank-card promo: not for one plain order,
        // and it may be part of the best stack.
        stackIsSafe = false;
        continue;
      }
      final price = p['EffectivePrice'];
      if (price is num && price > 0 && (best == null || price < best.price)) {
        best = (price: price.toDouble(), code: blankToNull(p['Code']));
      }
    }
    final stack = _bestStack[sku];
    final stacked = stack is Map ? stack['EffectivePrice'] : null;
    if (stackIsSafe && stacked is num && stacked > 0 && (best == null || stacked < best.price - 0.005)) {
      best = (price: stacked.toDouble(), code: null);
    }
    return best;
  }
}
