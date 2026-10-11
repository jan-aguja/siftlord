import 'dart:convert';

import '../models/item.dart';
import 'store_adapter.dart';

/// An Amazon storefront: one site, one country, one home currency.
class AmazonStorefront {
  const AmazonStorefront({
    required this.id,
    required this.name,
    required this.host,
    required this.country,
    required this.currency,
  });

  final String id;
  final String name;
  final String host;
  final String country;
  final String currency;

  static const us = AmazonStorefront(
      id: 'amazon-us', name: 'Amazon US', host: 'www.amazon.com', country: 'US', currency: 'USD');
  static const jp = AmazonStorefront(
      id: 'amazon-jp', name: 'Amazon JP', host: 'www.amazon.co.jp', country: 'JP', currency: 'JPY');
  static const uk = AmazonStorefront(
      id: 'amazon-uk', name: 'Amazon UK', host: 'www.amazon.co.uk', country: 'GB', currency: 'GBP');

  static const all = [us, jp, uk];

  /// "amazon.com", "amazon.co.jp": matches the site and its subdomains.
  String get domain => host.replaceFirst('www.', '');
}

/// Amazon US, JP and UK. Work logged out (verified 2026-10-11 from a PH IP).
///
/// Results are server-rendered: each is a
/// `div[data-component-type="s-search-result"][data-asin]` card, with
/// `data-cy` blocks for title, price, reviews and delivery. There is no
/// embedded JSON, so the load-stop script reads the cards and sends their
/// texts as they are; all parsing (prices, ratings, "bought" counts, in
/// English or Japanese) happens here, where it's tested.
///
/// The desktop page is used: on amazon.co.jp it lists 48 results to the
/// mobile page's 14, prices more of them, and always labels ads.
///
/// Currency: Amazon picks the display currency itself (`i18n-prefs` cookie)
/// and logged out from the Philippines it often converts to pesos
/// ("PHP 2,508.97" on amazon.com). So every price's currency is read from its
/// own text, falling back to the storefront's. The user can change it in
/// Amazon's own currency settings in the visible WebView.
///
/// Delivery: logged out, Amazon guesses "Deliver to Philippines" from the IP
/// and cards then say what shipping to the Philippines costs ("¥2,410
/// delivery … Ships to Philippines"), kept as [Item.deliveryNote]. Items that
/// can't ship there show no price ("See options") and are skipped.
///
/// Ads: "Sponsored" and "Featured from Amazon brands" cards both carry
/// `.puis-sponsored-label-text` and the `AdHolder` class.
///
/// Bot checks: a CAPTCHA page ("Enter the characters you see below",
/// `form[action="/errors/validateCaptcha"]`) is reported as verification for
/// the user to clear in the visible WebView; it's never solved for them.
/// amazon.co.uk sometimes first serves an Akamai proof-of-work page that a
/// browser passes on its own and reloads; the script waits for the reload.
class AmazonAdapter extends StoreAdapter {
  AmazonAdapter(this.storefront);

  final AmazonStorefront storefront;

  @override
  String get id => storefront.id;
  @override
  String get name => storefront.name;
  @override
  String get country => storefront.country;
  @override
  String get currency => storefront.currency;

  String get _host => storefront.host;

  @override
  bool get desktopMode => true;

  @override
  Uri searchUrl(String query) => Uri.https(_host, '/s', {'k': query});

  @override
  Uri get homeUrl => Uri.https(_host, '/');

  /// Redirects to the storefront's own `/ap/signin` with the right OpenID
  /// parameters for that country.
  @override
  Uri get loginUrl => Uri.https(_host, '/gp/sign-in.html');

  /// A clean product link: no `ref`, `dib`, `qid` or `sr` tracking.
  Uri productUrl(String asin) => Uri.https(_host, '/dp/$asin');

  @override
  String get loadStopScript => '''
$jsSendHelper
(function () {
  if (window.__siftAmazonDone) return;
  function txt(el) { return el ? (el.textContent || '').replace(/\\s+/g, ' ').trim() : null; }
  function blocked() {
    if (location.pathname.indexOf('/ap/signin') === 0) return 'signin';
    if (document.querySelector('form[action*="validateCaptcha"], input#captchacharacters')) return 'captcha';
    var body = document.body ? document.body.textContent : '';
    if (/api-services-support@amazon|automated access to Amazon data/.test(body)) return 'robot';
    return null;
  }
  function challenge() {
    // Akamai's proof-of-work page: the browser passes it and reloads.
    if (document.getElementById('akam-logo')) return true;
    for (var i = 0; i < document.scripts.length && i < 3; i++) {
      if (/bm-verify|_sec\\/verify/.test(document.scripts[i].textContent || '')) return true;
    }
    return false;
  }
  function ratingCount(rv) {
    var els = rv.querySelectorAll('[aria-label]');
    for (var i = 0; i < els.length; i++) {
      var l = els[i].getAttribute('aria-label');
      if (/^[\\d,.]+\\s*[KkMm]?\\+?\\s/.test(l) && !/star|つ星/.test(l)) return l;
    }
    return null;
  }
  function card(c) {
    var t = c.querySelector('[data-cy="title-recipe"]') || c;
    var h2s = Array.prototype.slice.call(t.querySelectorAll('h2'));
    var titleEl = h2s.filter(function (h) { return h.getAttribute('aria-label'); })[0] ||
      h2s.slice().sort(function (a, b) { return txt(b).length - txt(a).length; })[0];
    var brandEl = h2s.filter(function (h) { return h !== titleEl && !h.getAttribute('aria-label'); })[0];
    var pr = c.querySelector('[data-cy="price-recipe"]');
    var price = null, list = null;
    if (pr) {
      var ps = pr.querySelectorAll('.a-price');
      for (var i = 0; i < ps.length; i++) {
        var o = txt(ps[i].querySelector('.a-offscreen'));
        if (!o) continue;
        if (ps[i].classList.contains('a-text-price') || ps[i].getAttribute('data-a-strike')) {
          // Not unit prices: "(PHP 2,450.51/count)".
          if (!list && !/\\//.test(txt(ps[i].parentElement))) list = o;
        } else if (!price) price = o;
      }
    }
    var rv = c.querySelector('[data-cy="reviews-block"]');
    var stars = rv && (rv.querySelector('[data-cy="reviews-ratings-slot"] .a-icon-alt') || rv.querySelector('.a-icon-alt'));
    var bought = null;
    if (rv) {
      var spans = rv.querySelectorAll('span');
      for (var j = 0; j < spans.length; j++) {
        var s = txt(spans[j]);
        if (/bought|購入/.test(s) && s.length < 80) { bought = s; break; }
      }
    }
    var badge = c.querySelector('[data-component-type="s-status-badge-component"]');
    var badgeType = null;
    if (badge) { try { badgeType = JSON.parse(badge.getAttribute('data-component-props')).badgeType; } catch (e) {} }
    var img = c.querySelector('img.s-image');
    var del = c.querySelector('[data-cy="delivery-recipe"]');
    return {
      asin: c.getAttribute('data-asin'),
      title: titleEl ? (txt(titleEl) || titleEl.getAttribute('aria-label')) : null,
      brand: brandEl ? txt(brandEl) : null,
      price: price,
      listPrice: list,
      image: img ? img.getAttribute('src') : null,
      rating: txt(stars),
      ratingCount: rv ? ratingCount(rv) : null,
      bought: bought,
      sponsored: c.classList.contains('AdHolder') ||
        !!c.querySelector('.puis-sponsored-label-text, .s-sponsored-label-text'),
      prime: !!c.querySelector('i.a-icon-prime, [aria-label="Amazon Prime"]'),
      badge: badgeType,
      delivery: del ? (del.innerText || del.textContent || '').replace(/\\s+/g, ' ').trim() : null
    };
  }
  var tries = 0;
  (function poll() {
    if (window.__siftAmazonDone) return;
    var b = blocked();
    if (b) { window.__siftAmazonDone = true; window.__siftSend(JSON.stringify({ blocked: b })); return; }
    if (challenge()) return;
    var cards = document.querySelectorAll('div[data-component-type="s-search-result"][data-asin]');
    if (!cards.length && ++tries < 12) { setTimeout(poll, 250); return; }
    var out = [];
    for (var k = 0; k < cards.length; k++) {
      if (!cards[k].getAttribute('data-asin')) continue;
      try { out.push(card(cards[k])); } catch (e) {}
    }
    window.__siftAmazonDone = true;
    window.__siftSend(JSON.stringify({
      host: location.host,
      deliverTo: txt(document.getElementById('glow-ingress-line2')),
      results: out
    }));
  })();
})();
''';

  @override
  PageKind classify(Uri url) {
    if (!url.host.endsWith(storefront.domain)) return PageKind.normal;
    final p = url.path;
    if (p.startsWith('/errors/validateCaptcha')) return PageKind.verification;
    // Account checks ("cvf" codes, MFA) are the user's to clear.
    if (p.startsWith('/ap/cvf') || p.startsWith('/ap/mfa')) return PageKind.verification;
    if (p.startsWith('/ap/signin') || p.startsWith('/ap/register')) return PageKind.login;
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
    switch (decoded['blocked']) {
      case null:
        break;
      case 'signin':
        throw const StoreBlocked(PageKind.login, 'sign-in page');
      case final why:
        throw StoreBlocked(PageKind.verification, '$why');
    }
    final results = decoded['results'];
    if (results is! List) throw const StoreBlocked(PageKind.normal, 'no results list');

    final items = <Item>[];
    for (final (i, e) in results.indexed) {
      if (e is! Map<String, dynamic>) continue;
      final item = _parseResult(e, i);
      if (item != null) items.add(item);
    }
    return items;
  }

  static final _asin = RegExp(r'^[A-Z0-9]{10}$');
  static final _adPrefix = RegExp(r'^\s*(Sponsored Ad|スポンサー広告)\s*[-–:]\s*');

  Item? _parseResult(Map<String, dynamic> e, int rank) {
    final asin = blankToNull(e['asin']);
    // Ads' aria-labels start "Sponsored Ad - "; the visible text doesn't.
    final title = blankToNull('${e['title'] ?? ''}'.replaceFirst(_adPrefix, ''));
    if (asin == null || !_asin.hasMatch(asin) || title == null) return null;
    // No price: unavailable, or can't ship to the delivery country.
    final price = parseAmazonPrice(e['price'] as String?, fallbackCurrency: currency);
    if (price == null || price.amount <= 0) return null;
    final list = parseAmazonPrice(e['listPrice'] as String?, fallbackCurrency: price.currency);
    final brand = blankToNull(e['brand']);
    final count = parseSoldText(blankToNull(e['ratingCount']));
    final bought = blankToNull(e['bought']);

    return Item(
      storeId: id,
      rank: rank,
      title: withBrand(title, brand),
      currency: price.currency,
      country: country,
      price: price.amount,
      originalPrice:
          list != null && list.currency == price.currency && list.amount > price.amount ? list.amount : null,
      url: productUrl(asin),
      imageUrl: blankToNull(e['image']),
      rating: parseAmazonRating(e['rating'] as String?),
      ratingCount: count != null && count > 0 ? count : null,
      soldText: bought,
      soldCount: parseAmazonBought(bought),
      brand: brand,
      isAd: e['sponsored'] == true,
      fulfilledByStore: e['prime'] == true,
      storePick: switch (e['badge']) {
        'amazons-choice' => "Amazon's Choice",
        'best-seller' => 'Best Seller',
        _ => null,
      },
      condition: _isRenewed(title, brand) ? Condition.used : conditionFromTitle(title),
      deliveryNote: _deliveryNote(e['delivery'] as String?),
    );
  }

  /// Amazon prints the brand above the title ("PUMA" / "Men's Club II Era
  /// Shoes"), so the title alone often lacks it. Put it in front, as the card
  /// reads, so searches for the brand match; "PUMA(プーマ)" counts as PUMA.
  static String withBrand(String title, String? brand) {
    if (brand == null) return title;
    final short = brand.replaceAll(RegExp(r'[(（].*?[)）]'), '').trim();
    if (short.isEmpty || title.toLowerCase().contains(short.toLowerCase())) return title;
    return '$short $title';
  }

  static bool _isRenewed(String title, String? brand) {
    final t = title.toLowerCase();
    return t.contains('renewed') || title.contains('整備済み') || brand == 'Amazon Renewed';
  }

  /// The card's shipping line ("¥2,410 delivery Mon, Oct 19 Ships to
  /// Philippines"), not stock notes like "Only 3 left in stock.".
  static String? _deliveryNote(String? raw) {
    final s = blankToNull(raw);
    if (s == null) return null;
    if (!RegExp(r'deliver|ship|配送|お届け|発送', caseSensitive: false).hasMatch(s)) return null;
    final cut = s.replaceFirst(RegExp(r'\s*(Only \d+ left in stock|残り\d+点).*$'), '');
    return cut.length > 120 ? '${cut.substring(0, 117)}...' : cut;
  }
}

/// Currency symbols Amazon prints, longest first so "US$" wins over "$".
const _symbols = <String, String>{
  'US\$': 'USD',
  'CA\$': 'CAD',
  'AU\$': 'AUD',
  'S\$': 'SGD',
  'HK\$': 'HKD',
  '\$': 'USD',
  '￥': 'JPY',
  '¥': 'JPY',
  '円': 'JPY',
  '£': 'GBP',
  '€': 'EUR',
  '₱': 'PHP',
  '₩': 'KRW',
  '₹': 'INR',
};

/// ISO codes Amazon puts before converted prices ("PHP 2,508.97"). A list,
/// so labels like "RRP" aren't read as currencies.
final _isoCode = RegExp(
    r'(?<![A-Za-z])(PHP|USD|JPY|GBP|EUR|CAD|AUD|SGD|HKD|KRW|INR|CNY|MXN|AED|SAR|NZD|CHF|SEK|PLN|TRY|BRL)(?![A-Za-z])');

/// Parses a price as Amazon writes it: "\$1,299.99", "￥4,980", "£12.99",
/// "PHP 2,508.97", "参考: ￥4,599", "RRP: £24.99", "1.299,99 €".
///
/// The currency comes from the text (an ISO code like "PHP", or a symbol),
/// else [fallbackCurrency]. Returns null when there's no number.
({double amount, String currency})? parseAmazonPrice(String? text, {required String fallbackCurrency}) {
  final s = text?.replaceAll(' ', ' ').trim();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r'\d[\d.,]*').firstMatch(s);
  if (m == null) return null;
  final amount = parseAmazonNumber(m.group(0)!);
  if (amount == null) return null;

  String? cur = _isoCode.firstMatch(s)?.group(1);
  if (cur == null) {
    for (final e in _symbols.entries) {
      if (s.contains(e.key)) {
        cur = e.value;
        break;
      }
    }
  }
  return (amount: amount, currency: cur ?? fallbackCurrency);
}

/// "1,299.99" → 1299.99, "4,980" → 4980, "1.299,99" → 1299.99, "12,5" → 12.5.
///
/// With both separators, the last one is the decimal point. A lone comma
/// followed by groups of three digits is a thousands separator (yen and
/// whole amounts), otherwise a decimal comma. A lone single period is a
/// decimal point.
double? parseAmazonNumber(String raw) {
  var s = raw.replaceAll(RegExp(r'[^\d.,]'), '');
  if (s.isEmpty) return null;
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    final decimal = lastComma > lastDot ? ',' : '.';
    final thousands = decimal == ',' ? '.' : ',';
    s = s.replaceAll(thousands, '').replaceAll(decimal, '.');
  } else if (lastComma >= 0) {
    s = RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(s) ? s.replaceAll(',', '') : s.replaceAll(',', '.');
  } else if ('.'.allMatches(s).length > 1) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

/// "4.1 out of 5 stars", "5つ星のうち4.6", "4,5 von 5 Sternen" → the rating.
double? parseAmazonRating(String? text) {
  if (text == null) return null;
  final jp = RegExp(r'うち\s*([\d.,]+)').firstMatch(text);
  final m = jp ?? RegExp(r'([\d.,]+)').firstMatch(text);
  final v = m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  return v != null && v > 0 && v <= 5 ? v : null;
}

/// "2K+ bought in past month" → 2000; "過去1か月で700点以上購入されました" → 700;
/// "過去1か月で1万点以上購入されました" → 10000.
int? parseAmazonBought(String? text) {
  if (text == null) return null;
  final jp = RegExp(r'で\s*([\d,.]+)\s*(万|千)?\s*点').firstMatch(text);
  if (jp != null) {
    final n = double.tryParse(jp.group(1)!.replaceAll(',', ''));
    if (n == null) return null;
    final mult = switch (jp.group(2)) { '万' => 10000, '千' => 1000, _ => 1 };
    return (n * mult).round();
  }
  return parseSoldText(text);
}
