import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/item.dart';
import 'store_style.dart';

/// Opens the product in the store's app if installed (universal / app links),
/// otherwise in the browser.
Future<void> openItem(Item item) =>
    launchUrl(item.url, mode: LaunchMode.externalApplication);

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.item, required this.storeName});

  final Item item;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: _Thumb(url: item.imageUrl, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Badges(item: item, storeName: storeName),
                  const SizedBox(height: 8),
                  Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _PriceLine(item: item, big: true),
                  const SizedBox(height: 6),
                  _Meta(item: item),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: storeColor(item.storeId)),
                    onPressed: () => openItem(item),
                    icon: const Icon(Icons.open_in_new),
                    label: Text('Open in $storeName'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, required this.storeName});

  final Item item;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openItem(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                color: Colors.white,
                width: 84,
                height: 84,
                child: _Thumb(url: item.imageUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  _PriceLine(item: item),
                  const SizedBox(height: 4),
                  _Badges(item: item, storeName: storeName),
                  const SizedBox(height: 4),
                  _Meta(item: item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.fit});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    const placeholder = Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey));
    if (u == null) return placeholder;
    return Image.network(u, fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

class _PriceLine extends StatelessWidget {
  const _PriceLine({required this.item, this.big = false});

  final Item item;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discount = item.discountPercent;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Text(formatPeso(item.price),
            style: (big ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (discount != null && item.originalPrice != null) ...[
          Text(formatPeso(item.originalPrice!),
              style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)),
          Text('-$discount%', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.item, required this.storeName});

  final Item item;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    Widget badge(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        );
    return Wrap(spacing: 6, runSpacing: 4, children: [
      badge(storeName, storeColor(item.storeId)),
      if (item.isOfficial) badge('Official', Colors.black87),
      if (item.isAd) badge('Ad', Colors.grey),
    ]);
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.rating != null && item.rating! > 0)
        '★ ${item.rating!.toStringAsFixed(1)}${item.ratingCount != null ? ' (${item.ratingCount})' : ''}',
      if (item.soldText != null) item.soldText!,
      if (item.location != null) item.location!,
      if (item.shopName != null) item.shopName!,
    ];
    return Text(parts.where((p) => p.trim().isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall);
  }
}
