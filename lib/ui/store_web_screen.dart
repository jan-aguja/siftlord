import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../stores/webview_config.dart';

/// A visible store page, for the user to sign in or pass a check. It shares
/// cookies with the hidden search WebViews, so a sign-in here carries over.
class StoreWebScreen extends StatefulWidget {
  const StoreWebScreen({super.key, required this.title, required this.url});

  final String title;
  final Uri url;

  @override
  State<StoreWebScreen> createState() => _StoreWebScreenState();
}

class _StoreWebScreenState extends State<StoreWebScreen> {
  late final Future<InAppWebViewSettings> _settings = WebViewConfig.settings();
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress, minHeight: 2))
            : null,
      ),
      body: FutureBuilder(
        future: _settings,
        builder: (context, snap) {
          final settings = snap.data;
          if (settings == null) return const SizedBox.shrink();
          return InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri.uri(widget.url)),
            initialSettings: settings,
            shouldOverrideUrlLoading: (_, action) async => WebViewConfig.navigationPolicy(action),
            onProgressChanged: (_, p) => setState(() => _progress = p / 100),
          );
        },
      ),
    );
  }
}
