import 'package:flutter/material.dart';

import '../models/item.dart';
import '../queue/search_queue.dart';
import 'item_card.dart';
import 'store_status_chips.dart';

enum SortMode { bestMatch, priceLow, priceHigh, mostSold }

/// Store-agnostic ordering: best match interleaves the stores' own rankings.
List<Item> arrange(List<Item> items, {required SortMode sort, required bool hideAds}) {
  final list = [for (final i in items) if (!hideAds || !i.isAd) i];
  int byRank(Item a, Item b) {
    final r = a.rank.compareTo(b.rank);
    return r != 0 ? r : a.storeId.compareTo(b.storeId);
  }

  switch (sort) {
    case SortMode.bestMatch:
      list.sort(byRank);
    case SortMode.priceLow:
      list.sort((a, b) => a.price.compareTo(b.price));
    case SortMode.priceHigh:
      list.sort((a, b) => b.price.compareTo(a.price));
    case SortMode.mostSold:
      list.sort((a, b) => (b.soldCount ?? -1).compareTo(a.soldCount ?? -1));
  }
  return list;
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.queue, required this.job});

  final SearchQueue queue;
  final SearchJob job;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  SortMode _sort = SortMode.bestMatch;
  bool _hideAds = true;
  bool _cards = true;
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
        title: Text(widget.job.query),
        actions: [
          IconButton(
            tooltip: _cards ? 'List view' : 'Card view',
            icon: Icon(_cards ? Icons.view_list : Icons.view_carousel),
            onPressed: () => setState(() => _cards = !_cards),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.queue,
        builder: (context, _) {
          final items = arrange(widget.job.items, sort: _sort, hideAds: _hideAds);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StoreStatusChips(queue: widget.queue, job: widget.job),
              ),
              _controls(items.length),
              Expanded(child: _body(items)),
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

  Widget _body(List<Item> items) {
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
        itemBuilder: (_, i) => ItemTile(item: items[i], storeName: _storeName(items[i])),
      );
    }
    return PageView.builder(
      controller: _pages,
      itemCount: items.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 24),
        child: ItemCard(item: items[i], storeName: _storeName(items[i])),
      ),
    );
  }

  String _storeName(Item item) => widget.queue.store(item.storeId).name;
}
