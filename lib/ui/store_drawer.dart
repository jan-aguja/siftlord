import 'package:flutter/material.dart';

import '../stores/facebook.dart';
import '../stores/store_settings.dart';
import 'store_style.dart';
import 'theme.dart';

/// Pick which stores new searches use, Marketplace's city, and the look.
class StoreDrawer extends StatelessWidget {
  const StoreDrawer({super.key, required this.settings});

  final StoreSettings settings;

  static const _subtitles = {
    'lazada': 'Works without signing in',
    'shopee': 'May ask you to sign in',
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
              for (final store in settings.stores) ...[
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
