import 'package:cursor_android/domain/sign_in_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isGoogleSignInHost', () {
    test('matches accounts.google.com case-insensitively', () {
      expect(isGoogleSignInHost('accounts.google.com'), isTrue);
      expect(isGoogleSignInHost('Accounts.Google.COM'), isTrue);
      expect(isGoogleSignInHost('google.com'), isFalse);
    });
  });

  group('isTrustedSignInHost', () {
    test('never trusts Google', () {
      expect(isTrustedSignInHost('accounts.google.com'), isFalse);
      expect(isTrustedSignInHost('ACCOUNTS.GOOGLE.COM'), isFalse);
    });

    test('trusts the Cloudflare challenge host', () {
      expect(isCloudflareChallengeHost('challenges.cloudflare.com'), isTrue);
      expect(isTrustedSignInHost('challenges.cloudflare.com'), isTrue);
      expect(isTrustedSignInHost('cloudflare.com'), isFalse);
    });

    test('trusts cursor.com and its subdomains', () {
      expect(isTrustedSignInHost('cursor.com'), isTrue);
      expect(isTrustedSignInHost('www.Cursor.com'), isTrue);
      expect(isTrustedSignInHost('authenticator.cursor.sh'), isTrue);
    });

    test('trusts WorkOS and GitHub', () {
      expect(isTrustedSignInHost('workos.com'), isTrue);
      expect(isTrustedSignInHost('api.workos.com'), isTrue);
      expect(isTrustedSignInHost('github.com'), isTrue);
    });

    test('rejects look-alike hosts', () {
      expect(isTrustedSignInHost('evilcursor.com'), isFalse);
      expect(isTrustedSignInHost('cursor.com.example.org'), isFalse);
      expect(isTrustedSignInHost('gist.github.com'), isFalse);
    });
  });

  group('isTrustedSignInUrl', () {
    test('accepts https on a trusted host', () {
      expect(isTrustedSignInUrl('https://cursor.com/agents'), isTrue);
    });

    test('rejects http', () {
      expect(isTrustedSignInUrl('http://cursor.com/agents'), isFalse);
      expect(isTrustedSignInUrl('HTTPS://cursor.com/agents'), isFalse);
    });

    test('rejects user info', () {
      expect(isTrustedSignInUrl('https://user@cursor.com/'), isFalse);
      expect(isTrustedSignInUrl('https://a:b@cursor.com/'), isFalse);
      expect(isTrustedSignInUrl('https://@cursor.com/'), isFalse);
    });

    test('rejects Google and invalid URLs', () {
      expect(isTrustedSignInUrl('https://accounts.google.com/'), isFalse);
      expect(isTrustedSignInUrl('https://[::1'), isFalse);
      expect(isTrustedSignInUrl('not a url'), isFalse);
    });
  });

  group('signInContentIsVisible', () {
    test('treats the Cloudflare interstitial as invisible', () {
      expect(
        signInContentIsVisible('Just a moment...', 'GitHub Email'),
        isFalse,
      );
    });

    test('requires a non-blank body', () {
      expect(signInContentIsVisible('Sign in', '   '), isFalse);
    });

    test('is visible with GitHub and email', () {
      expect(
        signInContentIsVisible('Sign in', 'Continue with GitHub or Email'),
        isTrue,
      );
      expect(signInContentIsVisible(null, 'GitHub 邮箱'), isTrue);
    });

    test('is not visible with GitHub but no email', () {
      expect(
        signInContentIsVisible('Sign in', 'Continue with GitHub'),
        isFalse,
      );
    });
  });
}
