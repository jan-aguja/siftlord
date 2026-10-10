import 'package:flutter/material.dart';

import '../stores/store_runner.dart';

Color storeColor(String storeId) => switch (storeId) {
      'lazada' => const Color(0xFF1A2EA8),
      'shopee' => const Color(0xFFEE4D2D),
      _ => Colors.grey,
    };

String formatPeso(double v) {
  final whole = v.truncate();
  final cents = ((v - whole) * 100).round();
  final digits = whole.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return cents == 0 ? '₱$digits' : '₱$digits.${cents.toString().padLeft(2, '0')}';
}

String statusLabel(StoreStatus s, int count) => switch (s) {
      StoreStatus.queued => 'queued',
      StoreStatus.running => 'searching…',
      StoreStatus.done => '$count',
      StoreStatus.needsLogin => 'sign in',
      StoreStatus.needsVerification => 'check needed',
      StoreStatus.failed => 'failed',
    };

IconData statusIcon(StoreStatus s) => switch (s) {
      StoreStatus.queued => Icons.schedule,
      StoreStatus.running => Icons.sync,
      StoreStatus.done => Icons.check_circle,
      StoreStatus.needsLogin => Icons.login,
      StoreStatus.needsVerification => Icons.shield_outlined,
      StoreStatus.failed => Icons.error_outline,
    };
