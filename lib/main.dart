import 'package:flutter/material.dart';

import 'queue/search_queue.dart';
import 'stores/lazada.dart';
import 'stores/shopee.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(SiftLordApp(queue: SearchQueue([LazadaAdapter(), ShopeeAdapter()])));
}

class SiftLordApp extends StatelessWidget {
  const SiftLordApp({super.key, required this.queue});

  final SearchQueue queue;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B5BDB), brightness: b),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'Sift Lord',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(queue: queue),
    );
  }
}
