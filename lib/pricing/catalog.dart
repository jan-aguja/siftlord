import 'dart:convert';

import 'package:flutter/services.dart';

import 'text_match.dart';

/// A product we know the usual price of. Hand-curated in
/// `assets/catalog.json`; covering everything is a non-goal.
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.aliases,
    required this.minPrice,
    required this.maxPrice,
    required this.checked,
    this.brand,
    this.exclude = const [],
    this.search,
  });

  factory CatalogEntry.fromJson(Map<String, dynamic> j) {
    final price = j['price'] as Map<String, dynamic>;
    return CatalogEntry(
      id: j['id'] as String,
      name: j['name'] as String,
      brand: j['brand'] as String?,
      search: j['search'] as String?,
      aliases: [for (final a in j['aliases'] as List) a as String],
      exclude: [for (final e in (j['exclude'] as List? ?? const [])) e as String],
      minPrice: (price['min'] as num).toDouble(),
      maxPrice: (price['max'] as num).toDouble(),
      checked: DateTime.parse(j['checked'] as String),
    );
  }

  final String id;
  final String name;
  final String? brand;

  /// Ways people search for or title it. [name] counts as one too.
  final List<String> aliases;

  /// Phrases marking a listing as something else that shares the name
  /// (games for a console, a case for earbuds).
  final List<String> exclude;

  /// Usual price range across variants, in pesos, as of [checked].
  final double minPrice;
  final double maxPrice;
  final DateTime checked;

  /// What to send to the stores when this product is picked from
  /// suggestions, if [name] isn't a good search.
  final String? search;

  String get searchText => search ?? name;

  List<String> get allNames => [name, ...aliases];
}

class Catalog {
  const Catalog(this.entries);

  static const assetPath = 'assets/catalog.json';

  static Future<Catalog> load() async =>
      Catalog.parse(await rootBundle.loadString(assetPath));

  factory Catalog.parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return Catalog([
      for (final p in j['products'] as List) CatalogEntry.fromJson(p as Map<String, dynamic>),
    ]);
  }

  final List<CatalogEntry> entries;

  /// The product a search is for: the entry with the longest name or alias
  /// that the query contains as a phrase. "airpods pro 3 white" → AirPods
  /// Pro 3; "airpods pro" alone → nothing (it could be either generation).
  CatalogEntry? match(String query) {
    final q = ' ${normalizeText(query)} ';
    CatalogEntry? best;
    var bestLen = 0;
    for (final e in entries) {
      for (final name in e.allNames) {
        final n = normalizeText(name);
        if (n.length > bestLen && q.contains(' $n ')) {
          best = e;
          bestLen = n.length;
        }
      }
    }
    return best;
  }

  /// Products to suggest while typing: any name or alias with a word starting
  /// with each typed word, in order of how early the match is.
  List<CatalogEntry> suggest(String text, {int limit = 5}) {
    final typed = words(text);
    if (typed.isEmpty || normalizeText(text).length < 2) return const [];
    final scored = <(int, CatalogEntry)>[];
    for (final e in entries) {
      int? best;
      for (final name in e.allNames) {
        final nw = words(name);
        final ok = typed.every((t) => nw.any((w) => w.startsWith(t)));
        if (!ok) continue;
        final pos = nw.indexWhere((w) => w.startsWith(typed.first));
        if (best == null || pos < best) best = pos;
      }
      if (best != null) scored.add((best, e));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final s in scored.take(limit)) s.$2];
  }
}
