import 'package:cursor_android/domain/sign_in_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void expectAction(String url, SignInNavigationAction action) {
    expect(decideSignInNavigation(url), action, reason: url);
  }

  test('allows the Cursor agents page in the WebView', () {
    expectAction(
      'https://cursor.com/agents',
      SignInNavigationAction.allowInWebView,
    );
  });

  test('blocks Google sign-in inside the app', () {
    expectAction(
      'https://accounts.google.com/o/oauth2/v2/auth?client_id=x',
      SignInNavigationAction.blockGoogleInApp,
    );
    expectAction(
      'https://user@ACCOUNTS.GOOGLE.COM/',
      SignInNavigationAction.blockGoogleInApp,
    );
  });

  test('opens untrusted https origins externally', () {
    expectAction(
      'https://evil.example/',
      SignInNavigationAction.openExternally,
    );
    expectAction(
      'https://user@cursor.com/',
      SignInNavigationAction.openExternally,
    );
  });

  test('blocks non-https and host-less URLs', () {
    expectAction('http://cursor.com/', SignInNavigationAction.block);
    expectAction('javascript:alert(1)', SignInNavigationAction.block);
    expectAction('intent://scan#Intent;end', SignInNavigationAction.block);
    expectAction('https:///path', SignInNavigationAction.block);
  });

  test('keeps the Cloudflare challenge in the WebView', () {
    expectAction(
      'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/',
      SignInNavigationAction.allowInWebView,
    );
  });

  test('keeps GitHub login in the WebView', () {
    expectAction(
      'https://github.com/login',
      SignInNavigationAction.allowInWebView,
    );
  });
}
