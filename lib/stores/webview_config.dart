import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Settings shared by the hidden search WebViews and the visible sign-in one,
/// so both look like the same mobile browser to the store.
class WebViewConfig {
  WebViewConfig._();

  static String? _userAgent;

  /// The platform's default mobile UA. On Android, drops the "; wv" WebView
  /// marker so stores serve their normal mobile web page instead of an
  /// "open in app" page.
  static Future<String> userAgent() async {
    final cached = _userAgent;
    if (cached != null) return cached;
    var ua = await InAppWebViewController.getDefaultUserAgent();
    if (Platform.isAndroid) ua = ua.replaceFirst('; wv)', ')');
    return _userAgent = ua;
  }

  /// A current desktop Safari, for stores whose mobile page lacks what we need.
  static const desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.6 Safari/605.1.15';

  static Future<InAppWebViewSettings> settings({bool desktop = false}) async => InAppWebViewSettings(
        userAgent: desktop ? desktopUserAgent : await userAgent(),
        preferredContentMode:
            desktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.RECOMMENDED,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: false,
        isInspectable: kDebugMode,
      );

  /// Keeps the store from bouncing us into its native app or app store.
  static NavigationActionPolicy navigationPolicy(NavigationAction action) {
    final scheme = action.request.url?.scheme;
    if (scheme == null || scheme == 'http' || scheme == 'https' ||
        scheme == 'about' || scheme == 'data' || scheme == 'blob') {
      return NavigationActionPolicy.ALLOW;
    }
    return NavigationActionPolicy.CANCEL;
  }
}
