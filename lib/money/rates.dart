import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exchange rates for showing foreign listings in the user's currency: the
/// European Central Bank's daily reference rates (public, no key), via
/// Frankfurter. Fetched on the phone at most once a day and cached, so it
/// works offline with the last table. No rate means no conversion: the
/// listing then shows only its own price.
class Rates extends ChangeNotifier {
  Rates(this._prefs, {Map<String, double>? perEuro, this.date}) : _perEuro = perEuro ?? const {};

  static const _url = 'https://api.frankfurter.dev/v1/latest';
  static const _key = 'fx_rates';

  static Future<Rates> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(prefs.getString(_key) ?? '') as Map<String, dynamic>;
      return Rates(prefs, perEuro: _parse(j), date: DateTime.tryParse('${j['date']}'));
    } catch (_) {
      return Rates(prefs);
    }
  }

  final SharedPreferences? _prefs;
  Map<String, double> _perEuro;

  /// The day the rates are from (ECB publishes on working days).
  DateTime? date;
  DateTime? _fetchedAt;

  /// Currencies there's a rate for, plus the euro.
  List<String> get currencies => ({'EUR', ..._perEuro.keys}.toList()..sort());

  /// [amount] in [from], expressed in [to]; null when either rate is unknown.
  double? convert(double amount, String from, String to) {
    if (from == to) return amount;
    final f = from == 'EUR' ? 1.0 : _perEuro[from];
    final t = to == 'EUR' ? 1.0 : _perEuro[to];
    if (f == null || t == null) return null;
    return amount / f * t;
  }

  /// Fetches today's table unless the cached one was fetched within a day.
  Future<void> refresh() async {
    final now = DateTime.now();
    if (_fetchedAt != null && now.difference(_fetchedAt!) < const Duration(hours: 12)) return;
    if (date != null && _perEuro.isNotEmpty && now.difference(date!) < const Duration(hours: 30)) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(_url));
      final res = await req.close();
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final rates = _parse(j);
      if (rates.isEmpty) return;
      _perEuro = rates;
      date = DateTime.tryParse('${j['date']}');
      _fetchedAt = now;
      await _prefs?.setString(_key, body);
      notifyListeners();
    } catch (e) {
      debugPrint('exchange rates not refreshed: $e');
    } finally {
      client.close();
    }
  }

  static Map<String, double> _parse(Map<String, dynamic> j) => {
        for (final e in (j['rates'] as Map<String, dynamic>? ?? const {}).entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      };
}
