import 'package:flutter/material.dart';

import '../money/money.dart';
import '../stores/facebook.dart';
import '../stores/store_settings.dart';
import 'store_style.dart';
import 'theme.dart';

/// Pick which stores new searches use, Marketplace's city, clean-up, and
/// the look.
class StoreDrawer extends StatefulWidget {
  const StoreDrawer({super.key, required this.settings});

  final StoreSettings settings;

  @override
  State<StoreDrawer> createState() => _StoreDrawerState();
}

class _StoreDrawerState extends State<StoreDrawer> {
  // Stores you've turned on lately come first. The order is taken when the
  // menu opens, so a row doesn't jump away from your finger as you toggle it.
  late final _order = widget.settings.orderedStores;

  StoreSettings get settings => widget.settings;

  static const _subtitles = {
    'lazada': 'Works without signing in',
    'shopee': 'May ask you to sign in',
    'zalora': 'Fashion. Works without signing in',
    'datablitz': 'Games and gadgets. Works without signing in',
    'amazon-us': 'amazon.com · ships abroad, plus shipping and import fees',
    'amazon-jp': 'amazon.co.jp · ships abroad, plus shipping and import fees',
    'amazon-uk': 'amazon.co.uk · ships abroad, plus shipping and import fees',
    'facebook': 'People selling near you, often used. Searched without signing in.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/icon/siftlord_icon.png', width: 44, height: 44),
                    ),
                    const SizedBox(width: 12),
                    Text('SIFT LORD', style: brandText(context, size: 18)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                child: Text('STORES', style: sectionLabel(context)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('New searches use the stores that are on.', style: theme.textTheme.bodySmall),
              ),
              for (final store in _order) ...[
                SwitchListTile(
                  secondary: CircleAvatar(
                    backgroundColor: storeColor(store.id),
                    child: Text(store.name[0], style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(store.name),
                  subtitle: Text(_subtitles[store.id] ?? ''),
                  value: settings.isEnabled(store.id),
                  onChanged: (on) => settings.setEnabled(store.id, on),
                ),
                if (store is FacebookMarketplaceAdapter && settings.isEnabled(store.id))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      initialValue: settings.marketplaceCity.slug,
                      decoration: const InputDecoration(labelText: 'Near', isDense: true),
                      items: [
                        for (final c in marketplaceCities)
                          DropdownMenuItem(value: c.slug, child: Text(c.label)),
                      ],
                      onChanged: (slug) => settings.marketplaceCity =
                          marketplaceCities.firstWhere((c) => c.slug == slug),
                    ),
                  ),
              ],
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                child: Text('SEARCHES', style: sectionLabel(context)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Hearted searches are always kept.', style: theme.textTheme.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<int?>(
                  initialValue: settings.autoCleanupDays,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Remove other searches',
                    helperText: 'Counted from their last refresh',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Never')),
                    for (final d in StoreSettings.cleanupChoices)
                      DropdownMenuItem(value: d, child: Text('After $d days')),
                  ],
                  onChanged: (d) => settings.autoCleanupDays = d,
                ),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                child: Text('PRICES', style: sectionLabel(context)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Listings from stores abroad are converted at the day\'s rate.',
                    style: theme.textTheme.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: settings.homeCurrency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Show prices in', isDense: true),
                  items: [
                    for (final c in {settings.homeCurrency, ...MoneyScope.of(context).rates.currencies})
                      DropdownMenuItem(value: c, child: Text('$c  ${currencySymbol(c).trim()}')),
                  ],
                  onChanged: (c) => settings.homeCurrency = c!,
                ),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text('LOOK', style: sectionLabel(context)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<AppSide>(
                  showSelectedIcon: false,
                  segments: [
                    for (final s in AppSide.values) ButtonSegment(value: s, label: Text(s.label)),
                  ],
                  selected: {settings.side},
                  onSelectionChanged: (v) => settings.side = v.first,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
