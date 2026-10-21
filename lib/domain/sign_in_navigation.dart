import 'package:cursor_android/domain/sign_in_policy.dart';

/// What the sign-in WebView should do with a navigation request.
enum SignInNavigationAction {
  /// Load the URL inside the sign-in WebView.
  allowInWebView,

  /// Cancel the load and show the in-app Google-blocked message.
  blockGoogleInApp,

  /// Cancel the load and hand the URL to the system browser.
  openExternally,

  /// Cancel the load without opening anything.
  block,
}

/// Decides a sign-in WebView navigation.
///
/// Ported from Kotlin 0.1.5 `WebSignIn` `shouldOverrideUrlLoading`:
/// non-https is blocked, Google sign-in stays blocked in the app, trusted
/// sign-in URLs load in the WebView and other https URLs open externally.
/// An https URL without a host is blocked, because Kotlin's `openHttps`
/// ignores blank hosts and the load is cancelled without opening anything.
SignInNavigationAction decideSignInNavigation(String url) {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    return SignInNavigationAction.block;
  }
  if (isGoogleSignInHost(uri.host)) {
    return SignInNavigationAction.blockGoogleInApp;
  }
  if (isTrustedSignInUrl(url)) {
    return SignInNavigationAction.allowInWebView;
  }
  if (uri.host.isEmpty) {
    return SignInNavigationAction.block;
  }
  return SignInNavigationAction.openExternally;
}
