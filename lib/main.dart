import 'package:flutter/material.dart';

import 'pricing/pricing.dart';
import 'queue/search_queue.dart';
import 'stores/facebook.dart';
import 'stores/lazada.dart';
import 'stores/shopee.dart';
import 'stores/store_settings.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pricing = await Pricing.load();
  final settings = await StoreSettings.load(
      [LazadaAdapter(), ShopeeAdapter(), FacebookMarketplaceAdapter()]);
  final queue = SearchQueue(settings.stores)
    ..onStoreFinished = (job) => pricing.thumbnails
        .learnFrom(pricing.check.reference(job.query, job.items), job.items);
  runApp(SiftLordApp(queue: queue, pricing: pricing, settings: settings));
}

class SiftLordApp extends StatelessWidget {
  const SiftLordApp({super.key, required this.queue, required this.pricing, required this.settings});

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
