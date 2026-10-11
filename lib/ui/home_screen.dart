import 'package:flutter/material.dart';

import '../pricing/catalog.dart';
import '../pricing/pricing.dart';
import '../queue/search_queue.dart';
import '../stores/store_settings.dart';
import 'results_screen.dart';
import 'store_accounts_screen.dart';
import 'store_drawer.dart';
import 'store_status_chips.dart';
import 'store_style.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.queue,
    required this.pricing,
    required this.settings,
  });

  final SearchQueue queue;
  final Pricing pricing;
  final StoreSettings settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Rebuild for the search field's glow.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    final stores = widget.settings.enabledStores;
    if (stores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turn on at least one store in the menu.')),
      );
      return;
    }
    widget.queue.add(text, only: stores);
    _controller.clear();
    _focus.unfocus();
  }

  String _hint() {
    final names = [for (final s in widget.settings.enabledStores) s.name];
    if (names.isEmpty) return 'Turn on a store in the menu';
    if (names.length == 1) return 'Search ${names.first}';
    if (names.length > 2) return 'Search ${names.length} stores';
    return 'Search ${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _refresh(SearchJob job) {
    widget.queue.refresh(job, also: widget.settings.enabledStores);
    _snack('Searching "${job.query}" again for fresh prices.');
  }

  Future<void> _confirmClear() async {
    final queue = widget.queue;
    final n = queue.jobs.where((j) => !j.saved).length;
    final kept = queue.jobs.length - n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear $n search${n == 1 ? '' : 'es'}?'),
        content: Text(kept == 0
            ? 'Heart a search to keep it through clean-ups.'
            : 'Your $kept hearted search${kept == 1 ? '' : 'es'} stay${kept == 1 ? 's' : ''}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) queue.clearUnsaved();
  }

  Widget _swipeBackground(Color color, IconData icon, Alignment align) => Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(icon),
      );

  void _open(SearchJob job) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            queue: widget.queue,
            pricing: widget.pricing,
            settings: widget.settings,
            job: job,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final sift = SiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      drawer: StoreDrawer(settings: widget.settings),
      body: DecoratedBox(
        decoration: backdropGlow(context),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Stores and look',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    Expanded(
                      child: Center(child: Text('SIFT LORD', style: brandText(context, size: 22))),
                    ),
                    IconButton(
                      tooltip: 'Store sign-ins',
                      icon: const Icon(Icons.storefront_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => StoreAccountsScreen(queue: queue)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) => RawAutocomplete<CatalogEntry>(
                    textEditingController: _controller,
                    focusNode: _focus,
                    optionsBuilder: (value) => widget.pricing.catalog.suggest(value.text),
                    displayStringForOption: (e) => e.searchText,
                    onSelected: (e) => _submit(e.searchText),
                    fieldViewBuilder: (context, controller, focusNode, _) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          if (focusNode.hasFocus)
                            BoxShadow(color: sift.glow.withValues(alpha: 0.45), blurRadius: 22),
                        ],
                      ),
                      child: ListenableBuilder(
                        listenable: widget.settings,
                        builder: (context, _) => TextField(
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.search,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: _submit,
                          decoration: InputDecoration(
                            hintText: _hint(),
                            prefixIcon: Icon(Icons.search, color: scheme.primary),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add_task),
                              tooltip: 'Queue search',
                              onPressed: () => _submit(controller.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                    optionsViewBuilder: (context, onSelected, options) => _Suggestions(
                      width: constraints.maxWidth,
                      options: options.toList(),
                      pricing: widget.pricing,
                      onSelected: onSelected,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: queue,
                  builder: (context, _) {
                    final jobs = queue.jobs;
                    if (jobs.isEmpty) return const _EmptyQueue();
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: jobs.length + 2,
                      separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 6 : 10),
                      itemBuilder: (context, i) {
                        if (i == 0) return _QueueHeader(queue: queue, onClear: _confirmClear);
                        if (i == jobs.length + 1) return const _QueueFooter();
                        final job = jobs[i - 1];
                        return Dismissible(
                          key: ValueKey(job.id),
                          background: _swipeBackground(
                              sift.statusDone.withValues(alpha: 0.25), Icons.refresh, Alignment.centerLeft),
                          secondaryBackground: _swipeBackground(
                              scheme.errorContainer, Icons.delete_outline, Alignment.centerRight),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) {
                              _refresh(job);
                              return false;
                            }
                            if (!job.saved) return true;
                            _snack('Saved searches stay put. Tap the heart to unsave it first.');
                            return false;
                          },
                          onDismissed: (_) => queue.remove(job),
                          child: _QueueRow(
                            queue: queue,
                            pricing: widget.pricing,
                            job: job,
                            onTap: () => _open(job),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "YOUR SEARCHES · 4" and, when there's something to clear, a Clear button.
class _QueueHeader extends StatelessWidget {
  const _QueueHeader({required this.queue, required this.onClear});

  final SearchQueue queue;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final jobs = queue.jobs;
    final clearable = jobs.any((j) => !j.saved);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text('YOUR SEARCHES · ${jobs.length}', style: sectionLabel(context)),
          const Spacer(),
          if (clearable)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}

/// The emblem, small and dim, under the last search, with the gestures:
/// the empty-queue art only shows on day one, this stays.
class _QueueFooter extends StatelessWidget {
  const _QueueFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        children: [
          Opacity(
            opacity: 0.35,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('assets/icon/siftlord_icon.png', width: 48, height: 48),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Swipe right to refresh prices, left to remove.\nHearted searches stay through clean-ups.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One queued search: a status strip (green all fetched, amber searching,
/// red a store needs you), the query, per-store summary, the lowest fair
/// price, and a heart.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.queue, required this.pricing, required this.job, required this.onTap});

  final SearchQueue queue;
  final Pricing pricing;
  final SearchJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sift = SiftColors.of(context);
    final (Color status, String statusLabel) = switch (job.health) {
      JobHealth.done => (sift.statusDone, 'All stores fetched'),
      JobHealth.busy => (sift.statusBusy, 'Still searching'),
      JobHealth.attention => (sift.statusAttention, 'A store needs you'),
    };
    final lowest = pricing.check.lowestFair(job.query, job.items);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final facts = [
      if (job.pins.isNotEmpty) '${job.pins.length} pinned',
      if (!job.isRunning) 'updated ${timeAgo(job.updatedAt)}',
    ];
    return Material(
      color: sift.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: job.saved ? theme.colorScheme.primary.withValues(alpha: 0.45) : sift.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: statusLabel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 5,
                  decoration: BoxDecoration(
                    color: status,
                    boxShadow: [BoxShadow(color: status.withValues(alpha: 0.6), blurRadius: 8)],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
                      child: Row(
                        children: [
                          ProductThumb(
                            url: pricing.pictureFor(job.query, job.items,
                                pinned: job.pins.isEmpty ? null : job.pins.last.item),
                            size: 56,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(job.query,
                                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                if (lowest != null) ...[
                                  const SizedBox(height: 2),
                                  Text.rich(
                                    TextSpan(children: [
                                      TextSpan(text: 'From ', style: muted),
                                      TextSpan(
                                        text: formatPeso(lowest.price),
                                        style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                                      ),
                                      TextSpan(text: ' on ${queue.store(lowest.storeId).name}', style: muted),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                StoreStatusSummary(queue: queue, job: job),
                                if (facts.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(facts.join(' · '), style: muted),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: job.saved ? 'Unsave' : 'Save this search',
                            onPressed: () => queue.setSaved(job, !job.saved),
                            icon: Icon(
                              job.saved ? Icons.favorite : Icons.favorite_border,
                              color: job.saved ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (job.isRunning) const LinearProgressIndicator(minHeight: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sift = SiftColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: sift.glow.withValues(alpha: 0.5), blurRadius: 40)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.asset('assets/icon/siftlord_icon.png', width: 132, height: 132),
              ),
            ),
            const SizedBox(height: 28),
            Text('WHAT DO YOU SEEK?', textAlign: TextAlign.center, style: brandText(context, size: 18)),
            const SizedBox(height: 12),
            Text(
              'Search once and sift every store at once. Queue as many searches as you like '
              'and open each one while it finishes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Known products matching what's typed, with a learned thumbnail and the
/// usual price.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.width,
    required this.options,
    required this.pricing,
    required this.onSelected,
  });

  final double width;
  final List<CatalogEntry> options;
  final Pricing pricing;
  final void Function(CatalogEntry) onSelected;

  @override
  Widget build(BuildContext context) {
    final sift = SiftColors.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          elevation: 8,
          shadowColor: sift.glow.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: sift.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: 320),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final e in options)
                  ListTile(
                    leading: ProductThumb(url: pricing.thumbnails.forProduct(e.id), size: 36),
                    title: Text(e.name),
                    subtitle: Text('Usually ${formatPriceRange(e.minPrice, e.maxPrice)}'),
                    onTap: () => onSelected(e),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
