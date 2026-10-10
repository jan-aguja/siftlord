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
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: jobs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final job = jobs[i];
                        return Dismissible(
                          key: ValueKey(job.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) => queue.remove(job),
                          child: _QueueRow(queue: queue, job: job, onTap: () => _open(job)),
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

/// One queued search: a panel with a thin progress line while it runs.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.queue, required this.job, required this.onTap});

  final SearchQueue queue;
  final SearchJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sift = SiftColors.of(context);
    return Material(
      color: sift.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: job.isRunning ? sift.glow.withValues(alpha: 0.5) : sift.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.query,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        StoreStatusSummary(queue: queue, job: job),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
            if (job.isRunning) const LinearProgressIndicator(minHeight: 2),
          ],
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
