import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/item.dart';
import '../money/money.dart';
import '../pricing/price_check.dart';
import '../queue/search_queue.dart';
import 'store_style.dart';
import 'theme.dart';

/// Opens the product in the store's app if installed (universal / app links),
/// otherwise in the browser.
Future<void> openItem(Item item) => launchUrl(item.url, mode: LaunchMode.externalApplication);

class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.item,
    required this.storeName,
    this.verdict = PriceVerdict.none,
    this.ref,
    this.pin,
    this.onTogglePin,
  });

  final Item item;
  final String storeName;
  final PriceVerdict verdict;
  final PriceReference? ref;

  /// Set when the user pinned this listing.
  final Pin? pin;
  final VoidCallback? onTogglePin;

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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        // Product photos are shot on white; keep it in both themes.
                        color: Colors.white,
                        child: _Thumb(url: item.imageUrl, fit: BoxFit.contain),
                      ),
                      if (onTogglePin != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _PinButton(pinned: pin != null, onPressed: onTogglePin!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pin != null) ...[_PinNote(pin: pin!), const SizedBox(height: 8)],
                  _Badges(item: item, storeName: storeName),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _PriceLine(item: item, big: true),
                  if (verdict != PriceVerdict.none) ...[
                    const SizedBox(height: 8),
                    PriceAlert(verdict: verdict, ref: ref),
                  ],
                  const SizedBox(height: 6),
                  _Meta(item: item, storeName: storeName),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: storeColor(item.storeId),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                    ),
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
  const ItemTile({
    super.key,
    required this.item,
    required this.storeName,
    this.verdict = PriceVerdict.none,
    this.ref,
    this.pin,
    this.onTogglePin,
  });

  final Item item;
  final String storeName;
  final PriceVerdict verdict;
  final PriceReference? ref;

  /// Set when the user pinned this listing.
  final Pin? pin;
  final VoidCallback? onTogglePin;

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
                  if (pin != null) ...[_PinNote(pin: pin!), const SizedBox(height: 4)],
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  _PriceLine(item: item),
                  if (verdict != PriceVerdict.none) ...[
                    const SizedBox(height: 4),
                    PriceAlert(verdict: verdict, ref: ref, compact: true),
                  ],
                  const SizedBox(height: 4),
                  _Badges(item: item, storeName: storeName),
                  const SizedBox(height: 4),
                  _Meta(item: item, storeName: storeName),
                ],
              ),
            ),
            if (onTogglePin != null)
              IconButton(
                tooltip: pin != null ? 'Unpin' : 'Pin to top',
                visualDensity: VisualDensity.compact,
                onPressed: onTogglePin,
                icon: Icon(
                  pin != null ? Icons.push_pin : Icons.push_pin_outlined,
                  color: pin != null
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Round pin toggle over the card's photo (the photo is always on white).
class _PinButton extends StatelessWidget {
  const _PinButton({required this.pinned, required this.onPressed});

  final bool pinned;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: pinned ? scheme.primary : Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: pinned ? 'Unpin' : 'Pin to top',
        onPressed: onPressed,
        icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white),
      ),
    );
  }
}

/// "Pinned", plus how the price moved since, or that the latest search
/// didn't find it.
class _PinNote extends StatelessWidget {
  const _PinNote({required this.pin});

  final Pin pin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sift = SiftColors.of(context);
    final diff = pin.item.price - pin.pinnedPrice;
    final (String note, Color color) = pin.missing
        ? ('not in the latest results', sift.warnFg)
        : diff.abs() < 1
        ? ('', scheme.primary)
        : diff < 0
        ? ('${formatMoney(-diff, pin.item.currency)} less than when pinned', sift.saleFg)
        : ('${formatMoney(diff, pin.item.currency)} more than when pinned', sift.warnFg);
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color);
    return Row(
      children: [
        Icon(Icons.push_pin, size: 14, color: scheme.primary),
        const SizedBox(width: 4),
        Text('Pinned', style: style.copyWith(color: scheme.primary)),
        if (note.isNotEmpty)
          Flexible(
            child: Text(' · $note', style: style, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

/// "Price looks off" (amber), "Big sale" (green) or "Third-party" (grey). A
/// nudge to check the listing, never a claim that it's fake: it may be a
/// case, a variant, a bundle, or a real sale.
class PriceAlert extends StatelessWidget {
  const PriceAlert({super.key, required this.verdict, required this.ref, this.compact = false});

  final PriceVerdict verdict;

  /// Null only for [PriceVerdict.thirdParty], which doesn't need a price.
  final PriceReference? ref;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sift = SiftColors.of(context);
    final r = ref;
    final usual = r == null
        ? ''
        : r.entry != null
        ? 'Usually ${formatPriceRange(r.low, r.high)}.'
        : 'Official stores here: about ${formatMarket(r.low)}.';
    final entry = r?.entry;
    final (IconData icon, String title, String detail, Color bg, Color fg) = switch (verdict) {
      PriceVerdict.thirdParty => (
        Icons.extension_outlined,
        'Third-party item',
        entry?.brand != null
            ? 'Says it\'s made for ${entry!.name}, so it\'s not by ${entry.brand}.'
            : 'Says it\'s made for what you searched, not that it is it.',
        sift.neutralBg,
        sift.neutralFg,
      ),
      PriceVerdict.bigSale => (
        Icons.local_offer,
        'Big sale from an official store',
        '$usual Worth a look, and check it\'s the right variant.',
        sift.saleBg,
        sift.saleFg,
      ),
      PriceVerdict.tooHigh => (
        Icons.trending_up,
        'Price looks high',
        '$usual Check the variant or bundle.',
        sift.warnBg,
        sift.warnFg,
      ),
      _ => (
        Icons.warning_amber_rounded,
        'Price looks off',
        '$usual Make sure it\'s genuine and the right item.',
        sift.warnBg,
        sift.warnFg,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 3 : 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: compact
                ? Text(
                    title,
                    style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                      ),
                      Text(detail, style: TextStyle(color: fg, fontSize: 12)),
                    ],
                  ),
          ),
        ],
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
    final savings = item.voucherSavings;
    final line = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Text(
          formatMoney(item.price, item.currency),
          style: (big ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (discount != null && item.originalPrice != null) ...[
          Text(
            formatMoney(item.originalPrice!, item.currency),
            style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
          ),
          Text('-$discount%', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ],
    );
    // Foreign storefronts: the user's currency at today's rate, and a reminder
    // that getting it here costs more than the listed price.
    final money = MoneyScope.of(context);
    final abroad = item.country != PriceCheck.marketCountry;
    final converted = item.currency != money.home ? money.toHome(item.price, item.currency) : null;
    final note = !abroad && converted == null
        ? null
        : Text(
            [
              if (converted != null) '≈ ${formatMoney(converted, money.home, whole: true)}',
              if (abroad) 'plus shipping and import fees',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
    if (savings == null && note == null) return line;
    final sift = SiftColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        if (note != null) ...[const SizedBox(height: 2), note],
        if (savings != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: sift.saleBg, borderRadius: BorderRadius.circular(4)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.confirmation_number_outlined, size: 14, color: sift.saleFg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${item.voucherCode != null ? '${formatMoney(savings, item.currency)} off with code ${item.voucherCode}' : '${formatMoney(savings, item.currency)} ${item.voucherLabel ?? 'voucher'} applied'} · '
                    '${formatMoney(item.priceBeforeVouchers!, item.currency)} before',
                    style: TextStyle(color: sift.saleFg, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    Widget badge(String text, Color color, {Color fg = Colors.white}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
    final tier = switch (item.sellerTier) {
      SellerTier.mall => badge(mallLabel(item.storeId), mallBadgeColor),
      SellerTier.preferredPlus => badge('Preferred+', const Color(0xFFD9480F)),
      SellerTier.preferred => badge('Preferred', const Color(0xFFE8590C)),
      SellerTier.regular => null,
    };
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        badge(storeName, storeColor(item.storeId)),
        ?tier,
        if (item.condition == Condition.used) badge('Used', const Color(0xFF868E96)),
        if (item.condition == Condition.brandNew) badge('New', const Color(0xFF2B8A3E)),
        if (item.isOverseas) badge('Overseas seller', const Color(0xFF6741D9)),
        if (item.storePick != null) badge(item.storePick!, const Color(0xFF0B7285)),
        if (item.soldOut) badge('Sold out', const Color(0xFF495057)),
        if (item.isAd) badge('Ad', scheme.outline),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.item, required this.storeName});

  final Item item;
  final String storeName;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (item.rating != null && item.rating! > 0)
        '★ ${item.rating!.toStringAsFixed(1)}${item.ratingCount != null ? ' (${item.ratingCount})' : ''}',
      ?item.soldText,
      if (item.location != null)
        item.secondhandMarket ? 'In ${item.location}' : 'Ships from ${item.location}',
      ?item.deliveryNote,
      if (item.fulfilledByStore) 'Fulfilled by $storeName',
      ?item.shopName,
    ];
    return Text(
      parts.where((p) => p.trim().isNotEmpty).join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
