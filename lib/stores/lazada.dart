import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// Lazada PH. Works logged out.
///
/// The mobile search page embeds its results in `window.pageData.mods`. With a
/// desktop user agent it doesn't, so the script falls back to the same-origin
/// `?ajax=true` endpoint the page itself uses, which returns the same shape.
class LazadaAdapter extends StoreAdapter {
  @override
  String get id => 'lazada';
  @override
  String get name => 'Lazada';

  @override
  Uri searchUrl(String query) =>
      Uri.https('www.lazada.com.ph', '/catalog/', {'q': query});

  @override
  Uri get homeUrl => Uri.https('www.lazada.com.ph', '/');
  @override
  Uri get loginUrl => Uri.https('member.lazada.com.ph', '/user/login');

  @override
  String get loadStopScript => '''
$jsSendHelper
(function () {
  if (window.__siftLazadaDone) return;
  var tries = 0;
  function viaAjax() {
    var q = new URLSearchParams(location.search).get('q') || '';
    fetch('/catalog/?ajax=true&page=1&q=' + encodeURIComponent(q), { credentials: 'include' })
      .then(function (r) { return r.text(); })
      .then(function (t) { window.__siftLazadaDone = true; window.__siftSend(t); })
      .catch(function (e) { window.__siftSend(JSON.stringify({ siftError: String(e) })); });
  }
  (function poll() {
    var mods = window.pageData && window.pageData.mods;
    if (mods && mods.listItems) {
      window.__siftLazadaDone = true;
      window.__siftSend(JSON.stringify({ mods: { listItems: mods.listItems } }));
      return;
    }
    if (++tries < 12) { setTimeout(poll, 250); } else { viaAjax(); }
  })();
})();
''';

  @override
  PageKind classify(Uri url) {
    final s = url.toString();
    if (s.contains('punish') || s.contains('/_____tmd_____/')) {
      return PageKind.verification;
    }
    if (url.host.startsWith('member.') && url.path.contains('login')) {
      return PageKind.login;
    }
    return PageKind.normal;
  }

  @override
  List<Item> parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // Anti-bot answers with an HTML slider page instead of JSON.
      throw const StoreBlocked(PageKind.verification, 'non-JSON response');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const StoreBlocked(PageKind.verification, 'unexpected payload');
    }
    final ret = decoded['ret'];
    if (ret is List && ret.any((r) => '$r'.contains('RGV587'))) {
      throw const StoreBlocked(PageKind.verification, 'RGV587');
    }
    if (decoded['siftError'] != null) {
      throw StoreBlocked(PageKind.normal, '${decoded['siftError']}');
    }
    final list = (decoded['mods'] as Map<String, dynamic>?)?['listItems'];
    if (list is! List) return const [];

    final items = <Item>[];
    for (final (i, e) in list.indexed) {
      if (e is! Map<String, dynamic>) continue;
      final price = double.tryParse('${e['price']}');
      final title = e['name'] as String?;
      final url = _url(e['itemUrl'] as String?);
      if (price == null || title == null || url == null) continue;
      final soldText = blankToNull(e['itemSoldCntShow']);
      final biz = {
        for (final ic in (e['icons'] as List? ?? const []))
          if (ic is Map) '${ic['bizType']}',
      };
      final location = prettyLocation(e['location']);
      final brand = blankToNull(e['brandName']);
      items.add(Item(
        storeId: id,
        rank: i,
        title: title,
        price: price,
        originalPrice: double.tryParse('${e['originalPrice']}'),
        url: url,
        imageUrl: e['image'] as String?,
        rating: double.tryParse('${e['ratingScore']}'),
        ratingCount: int.tryParse('${e['review']}'),
        soldText: soldText,
        soldCount: parseSoldText(soldText),
        location: location,
        shopName: blankToNull(e['sellerName']),
        brand: brand == 'No Brand' ? null : brand,
        isAd: e['isSponsored'] == true || '${e['adFlag']}' == '1',
        sellerTier: biz.contains('lazMall') ? SellerTier.mall : SellerTier.regular,
        isOverseas: isForeignLocation(location),
        storePick: biz.contains('lazPick')
            ? 'LazPick'
            : biz.contains('choice')
                ? 'Lazada Choice'
                : null,
      ));
    }
    return items;
  }

  Uri? _url(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final full = raw.startsWith('//') ? 'https:$raw' : raw;
    return Uri.tryParse(full);
  }
}
