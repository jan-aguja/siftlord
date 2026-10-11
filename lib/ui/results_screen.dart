import 'package:flutter/material.dart';

import '../models/item.dart';
import '../money/money.dart';
import '../pricing/price_check.dart';
import '../pricing/pricing.dart';
import '../queue/search_queue.dart';
import '../stores/store_settings.dart';
import 'item_card.dart';
import 'store_status_chips.dart';
import 'store_style.dart';
import 'theme.dart';

enum SortMode { bestMatch, priceLow, priceHigh, mostSold }

/// Store-agnostic ordering: best match interleaves the stores' own rankings.
///
/// [priceOf] puts prices in one currency for sorting (default: as listed);
/// listings it can't convert sort last.
List<Item> arrange(List<Item> items,
    {required SortMode sort,
    required bool hideAds,
    Set<String> hiddenStores = const {},
    double? Function(Item)? priceOf}) {
  final price = priceOf ?? (Item i) => i.price;
  final list = [
    for (final i in items)
      if ((!hideAds || !i.isAd) && !hiddenStores.contains(i.storeId)) i,
  ];
  int byRank(Item a, Item b) {
    final r = a.rank.compareTo(b.rank);
    return r != 0 ? r : a.storeId.compareTo(b.storeId);
  }

  switch (sort) {
    case SortMode.bestMatch:
      list.sort(byRank);
    case SortMode.priceLow:
      list.sort((a, b) => (price(a) ?? double.infinity).compareTo(price(b) ?? double.infinity));
    case SortMode.priceHigh:
      list.sort((a, b) => (price(b) ?? -1).compareTo(price(a) ?? -1));
    case SortMode.mostSold:
      list.sort((a, b) => (b.soldCount ?? -1).compareTo(a.soldCount ?? -1));
  }
  return list;
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.queue,
    required this.pricing,
    required this.settings,
    required this.job,
  });

  final SearchQueue queue;
  final Pricing pricing;
  final StoreSettings settings;
  final SearchJob job;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  SortMode _sort = SortMode.bestMatch;
  bool _hideAds = true;
  late bool _cards = !widget.settings.listView;
  final Set<String> _hiddenStores = {};
  final _pages = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: widget.queue,
          builder: (context, _) => Column(
            children: [
              Text(widget.job.query),
              Text(
                widget.job.isRunning ? 'Searching…' : 'Updated ${timeAgo(widget.job.updatedAt)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh prices',
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.queue.refresh(widget.job, also: widget.settings.enabledStores),
          ),
          IconButton(
            tooltip: _cards ? 'List view' : 'Card view',
            icon: Icon(_cards ? Icons.view_list : Icons.view_carousel),
            onPressed: () => setState(() {
              _cards = !_cards;
              widget.settings.listView = !_cards;
            }),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.queue,
        builder: (context, _) {
          final all = widget.job.items;
          final ref = widget.pricing.check.reference(widget.job.query, all);
          // Pins first (newest first), then everything else in the chosen order.
          final pins = widget.job.pins;
          final pinnedKeys = {for (final p in pins) p.item.key};
          final items = [
            for (final p in pins)
              if (!_hiddenStores.contains(p.item.storeId)) p.item,
            ...arrange([for (final i in all) if (!pinnedKeys.contains(i.key)) i],
                sort: _sort,
                hideAds: _hideAds,
                hiddenStores: _hiddenStores,
                priceOf: (i) => MoneyScope.of(context).toHome(i.price, i.currency)),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StoreStatusChips(
                  queue: widget.queue,
                  job: widget.job,
                  hidden: _hiddenStores,
                  onToggle: (id) => setState(() {
                    if (!_hiddenStores.remove(id)) _hiddenStores.add(id);
                    _jumpToStart();
                  }),
                ),
              ),
              if (ref != null) _ReferenceBar(ref: ref, pricing: widget.pricing),
              _controls(items.length),
              Expanded(child: _body(items, ref)),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          DropdownButton<SortMode>(
            value: _sort,
            underline: const SizedBox.shrink(),
            onChanged: (v) => setState(() {
              _sort = v!;
              _jumpToStart();
            }),
            items: const [
              DropdownMenuItem(value: SortMode.bestMatch, child: Text('Best match')),
              DropdownMenuItem(value: SortMode.priceLow, child: Text('Price: low to high')),
              DropdownMenuItem(value: SortMode.priceHigh, child: Text('Price: high to low')),
              DropdownMenuItem(value: SortMode.mostSold, child: Text('Most sold')),
            ],
          ),
          const Spacer(),
          FilterChip(
            label: const Text('Hide ads'),
            selected: _hideAds,
            onSelected: (v) => setState(() {
              _hideAds = v;
              _jumpToStart();
            }),
          ),
          const SizedBox(width: 8),
          if (_cards && count > 0)
            Text('${(_page + 1).clamp(1, count)} / $count',
                style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }

  void _jumpToStart() {
    _page = 0;
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Widget _body(List<Item> items, PriceReference? ref) {
    final check = widget.pricing.check;
    if (items.isEmpty) {
      return Center(
        child: widget.job.isRunning
            ? const CircularProgressIndicator()
            : const Text('No results.'),
      );
    }
    if (!_cards) {
      return ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => ItemTile(
            item: items[i],
            storeName: _storeName(items[i]),
            verdict: check.verdict(items[i], ref, widget.job.query),
            ref: ref,
            pin: widget.job.pinFor(items[i]),
            onTogglePin: () => _togglePin(items[i])),
      );
    }
    return PageView.builder(
      controller: _pages,
      itemCount: items.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: ItemCard(
            item: items[i],
            storeName: _storeName(items[i]),
            verdict: check.verdict(items[i], ref, widget.job.query),
            ref: ref,
            pin: widget.job.pinFor(items[i]),
            onTogglePin: () => _togglePin(items[i])),
      ),
    );
  }

  void _togglePin(Item item) {
    final pinning = widget.job.pinFor(item) == null;
    final hearted = widget.queue.togglePin(widget.job, item);
    if (pinning) _jumpToStart();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (hearted) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Pinned to the top. This search is now hearted, so the pin is kept.')));
    }
  }

  String _storeName(Item item) => widget.queue.store(item.storeId).name;
}

/// The usual price these results are checked against, and where it came from.
class _ReferenceBar extends StatelessWidget {
  const _ReferenceBar({required this.ref, required this.pricing});

  final PriceReference ref;
  final Pricing pricing;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = ref.entry;
    final String title;
    final String detail;
    final String label;
    if (entry != null) {
      label = 'USUAL PRICE';
      title = '${entry.name} · ${formatPriceRange(ref.low, ref.high)}';
      detail = 'Sift Lord price list, checked ${_months[entry.checked.month - 1]} ${entry.checked.year}';
    } else {
      label = 'OFFICIAL STORES';
      title = 'About ${formatMarket(ref.low)}';
      detail = 'Middle price of ${ref.officialCount} official-store listings here';
    }
    final sift = SiftColors.of(context);
    return ListenableBuilder(
      listenable: pricing.thumbnails,
      builder: (context, _) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sift.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sift.hairline),
          boxShadow: [BoxShadow(color: sift.glow.withValues(alpha: 0.12), blurRadius: 18)],
        ),
        child: Row(
          children: [
            if (entry != null) ...[
              ProductThumb(url: pricing.thumbnails.forProduct(entry.id), size: 36),
              const SizedBox(width: 10),
            ] else ...[
              Icon(Icons.storefront, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: sectionLabel(context)),
                  const SizedBox(height: 2),
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(detail,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
