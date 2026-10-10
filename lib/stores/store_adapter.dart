import '../models/item.dart';

/// What a store page turned out to be once the hidden WebView landed on it.
enum PageKind { normal, login, verification }

/// Thrown by [StoreAdapter.parse] when the store answered but refused to give
/// results (anti-bot error, login wall).
class StoreBlocked implements Exception {
  const StoreBlocked(this.kind, [this.detail]);
  final PageKind kind;
  final String? detail;

  @override
  String toString() => 'StoreBlocked($kind, $detail)';
}

/// Everything store-specific lives behind this interface. The runner loads
/// [searchUrl] in a hidden WebView, injects [documentStartScript], runs
/// [loadStopScript] after each page load, and hands whatever the scripts send
/// back to [parse].
///
/// Scripts report results with
/// `window.flutter_inappwebview.callHandler('sift', rawJsonString)`.
abstract class StoreAdapter {
  String get id;
  String get name;

  Uri searchUrl(String query);

  /// Page a user opens to sign in or clear a check, in a visible WebView.
  Uri get homeUrl;
  Uri get loginUrl;

  /// Shown above the store's sign-in page, for quirks of signing in inside an app.
  String? get signInHint => null;

  /// False for stores searched only logged out: a login page counts as a
  /// failure, never as a prompt to sign in.
  bool get allowSignIn => true;

  /// Load the store's desktop site instead of its mobile one.
  bool get desktopMode => false;

  String? get documentStartScript => null;
  String? get loadStopScript => null;

  PageKind classify(Uri url);

  /// Turns the raw JSON a script sent back into items. Throws [StoreBlocked]
  /// when the payload is an error rather than results.
  List<Item> parse(String raw);
}

/// Shared JS helper: sends a string to Flutter, waiting for the bridge if a
/// document-start script fires before it's ready.
const jsSendHelper = r'''
window.__siftSend = window.__siftSend || function (payload) {
  function go() { window.flutter_inappwebview.callHandler('sift', payload); }
  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) { go(); }
  else { window.addEventListener('flutterInAppWebViewPlatformReady', go, { once: true }); }
};
''';
