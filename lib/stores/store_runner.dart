import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/item.dart';
import 'store_adapter.dart';
import 'webview_config.dart';

enum StoreStatus { queued, running, done, needsLogin, needsVerification, failed }

class StoreRunResult {
  const StoreRunResult(this.status, [this.items = const [], this.detail]);
  final StoreStatus status;
  final List<Item> items;
  final String? detail;
}

/// Runs one store search in a hidden WebView on the device, as the user.
class StoreRunner {
  const StoreRunner({this.timeout = const Duration(seconds: 25)});

  final Duration timeout;

  /// After a "blocked" payload, wait this long for a real one before giving up
  /// (a page may fire an early request that fails and then a good one).
  static const _blockedGrace = Duration(milliseconds: 2500);

  Future<StoreRunResult> run(StoreAdapter store, String query) async {
    final done = Completer<StoreRunResult>();
    Timer? graceTimer;

    void finish(StoreRunResult r) {
      if (done.isCompleted) return;
      graceTimer?.cancel();
      done.complete(r);
    }

    void blocked(PageKind kind, String? detail) {
      final status = kind == PageKind.login
          ? StoreStatus.needsLogin
          : kind == PageKind.verification
              ? StoreStatus.needsVerification
              : StoreStatus.failed;
      graceTimer ??= Timer(_blockedGrace, () => finish(StoreRunResult(status, const [], detail)));
    }

    final scripts = <UserScript>[
      if (store.documentStartScript != null)
        UserScript(
          source: store.documentStartScript!,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
    ];

    final webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri.uri(store.searchUrl(query))),
      initialSettings: await WebViewConfig.settings(),
      initialUserScripts: UnmodifiableListView(scripts),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'sift',
          callback: (List<dynamic> args) {
            if (args.isEmpty || args.first is! String) return;
            try {
              final items = store.parse(args.first as String);
              finish(StoreRunResult(StoreStatus.done, items));
            } on StoreBlocked catch (e) {
              blocked(e.kind, e.detail);
            } catch (e) {
              debugPrint('[${store.id}] parse failed: $e');
              blocked(PageKind.normal, 'parse failed: $e');
            }
          },
        );
      },
      shouldOverrideUrlLoading: (_, action) async =>
          WebViewConfig.navigationPolicy(action),
      onLoadStop: (controller, url) async {
        if (url == null) return;
        final kind = store.classify(url);
        if (kind != PageKind.normal) {
          blocked(kind, url.path);
          return;
        }
        final script = store.loadStopScript;
        if (script != null) await controller.evaluateJavascript(source: script);
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame ?? false) {
          finish(StoreRunResult(StoreStatus.failed, const [], error.description));
        }
      },
    );

    final timer = Timer(timeout, () => finish(const StoreRunResult(StoreStatus.failed, [], 'timed out')));
    try {
      await webView.run();
      return await done.future;
    } catch (e) {
      return StoreRunResult(StoreStatus.failed, const [], '$e');
    } finally {
      timer.cancel();
      graceTimer?.cancel();
      await webView.dispose();
    }
  }
}
