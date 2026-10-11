import 'package:flutter/material.dart';

import 'pricing/pricing.dart';
import 'queue/search_archive.dart';
import 'queue/search_queue.dart';
import 'stores/datablitz.dart';
import 'stores/facebook.dart';
import 'stores/lazada.dart';
import 'stores/shopee.dart';
import 'stores/store_settings.dart';
import 'stores/zalora.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

/// Hearted searches older than this are searched again on launch.
const staleAfter = Duration(hours: 6);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pricing = await Pricing.load();
  final settings = await StoreSettings.load([
    LazadaAdapter(),
    ShopeeAdapter(),
    ZaloraAdapter(),
    DatablitzAdapter(),
    FacebookMarketplaceAdapter(),
  ]);
  final queue = SearchQueue(settings.stores)
    ..onStoreFinished = (job) => pricing.thumbnails.learnFrom(
      pricing.check.reference(job.query, job.items),
      job.items,
    );
  final archive = await SearchArchive.open();
  await archive.attach(queue);
  // Hearted searches get fresh prices when they're more than a few hours old.
  for (final job in queue.jobs) {
    if (job.saved &&
        !job.isRunning &&
        DateTime.now().difference(job.updatedAt) > staleAfter) {
      queue.refresh(job);
    }
  }
  void cleanup() {
    final days = settings.autoCleanupDays;
    if (days != null) queue.removeOlderThan(Duration(days: days));
  }

  cleanup();
  settings.addListener(cleanup);
  AppLifecycleListener(onResume: cleanup, onPause: archive.flush);
  runApp(SiftLordApp(queue: queue, pricing: pricing, settings: settings));
}

class SiftLordApp extends StatelessWidget {
  const SiftLordApp({
    super.key,
    required this.queue,
    required this.pricing,
    required this.settings,
  });

  final SearchQueue queue;
  final Pricing pricing;
  final StoreSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Sift Lord',
        theme: lightSide(),
        darkTheme: darkSide(),
        themeMode: settings.side.themeMode,
        home: HomeScreen(queue: queue, pricing: pricing, settings: settings),
      ),
    );
  }
}
