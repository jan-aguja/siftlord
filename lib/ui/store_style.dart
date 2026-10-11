import 'package:flutter/material.dart';

import '../stores/store_runner.dart';

Color storeColor(String storeId) => switch (storeId) {
      'lazada' => const Color(0xFF3D5AFE),
      'shopee' => const Color(0xFFEE4D2D),
      'facebook' => const Color(0xFF1877F2),
      // Zalora's black, lifted a little so it shows on the Dark Side.
      'zalora' => const Color(0xFF3D3D3D),
      'datablitz' => const Color(0xFF0017DB),
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

/// Both stores mark their official tier with a red pill and white text;
/// matching it keeps the badge instantly recognizable.
const mallBadgeColor = Color(0xFFD0011B);

/// What each store calls its official-store tier.
String mallLabel(String storeId) => switch (storeId) {
      'lazada' => 'LazMall',
      'shopee' => 'Mall',
      _ => 'Official',
    };

/// "just now", "5m ago", "3h ago", "2d ago".
String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String formatPriceRange(double low, double high) =>
    low == high ? formatPeso(low) : '${formatPeso(low)}–${formatPeso(high)}';

/// A small product picture, or a placeholder until one has been learned.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.url, this.size = 36});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(Icons.sell_outlined,
        size: size * 0.55, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: size,
        height: size,
        color: u == null ? Theme.of(context).colorScheme.surfaceContainerHighest : Colors.white,
        alignment: Alignment.center,
        child: u == null
            ? placeholder
            : Image.network(u, fit: BoxFit.cover, width: size, height: size,
                errorBuilder: (_, _, _) => placeholder),
      ),
    );
  }
}
