import 'package:flutter/widgets.dart';

import 'rates.dart';

const _symbols = {
  'PHP': '₱', 'USD': '\$', 'JPY': '¥', 'GBP': '£', 'EUR': '€', 'SGD': 'S\$', 'MYR': 'RM',
  'AUD': 'A\$', 'CAD': 'C\$', 'HKD': 'HK\$', 'KRW': '₩', 'CNY': 'CN¥', 'THB': '฿', 'IDR': 'Rp',
  'INR': '₹', 'NZD': 'NZ\$', 'CHF': 'CHF ',
};

/// Currencies whose prices have no minor unit.
const _noDecimals = {'JPY', 'KRW', 'IDR'};

String currencySymbol(String currency) => _symbols[currency] ?? '$currency ';

/// "₱31,995", "\$1,299.99", "¥4,980", "£12.50". Cents only when there are any;
/// [whole] rounds them away (for converted, approximate amounts).
String formatMoney(double v, String currency, {bool whole = false}) {
  final noMinor = whole || _noDecimals.contains(currency);
  final rounded = noMinor ? v.roundToDouble() : (v * 100).roundToDouble() / 100;
  final units = rounded.truncate();
  final cents = ((rounded - units) * 100).round();
  final digits = units.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final sym = currencySymbol(currency);
  return noMinor || cents == 0 ? '$sym$digits' : '$sym$digits.${cents.toString().padLeft(2, '0')}';
}

/// The user's currency and today's rates, for every widget that shows money.
class MoneyScope extends InheritedNotifier<Rates> {
  const MoneyScope({super.key, required this.home, required Rates rates, required super.child})
      : super(notifier: rates);

  /// The currency the user wants prices in.
  final String home;

  Rates get rates => notifier!;

  static MoneyScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyScope>()!;

  /// [amount] in the user's currency, or null without a rate.
  double? toHome(double amount, String from) => rates.convert(amount, from, home);

  @override
  bool updateShouldNotify(MoneyScope oldWidget) => home != oldWidget.home || super.updateShouldNotify(oldWidget);
}
