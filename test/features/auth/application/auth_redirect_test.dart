import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/auth/application/auth_redirect.dart';

void main() {
  group('AuthRedirect.buildRedirect', () {
    test('uses pure origin without trailing path', () {
      final url = AuthRedirect.buildRedirect(
        'http://localhost:5000',
        AuthRedirectType.signup,
      );
      expect(url, 'http://localhost:5000/auth/callback?type=signup');
    });

    test('recovery type yields ?type=recovery', () {
      final url = AuthRedirect.buildRedirect(
        'http://localhost:5000',
        AuthRedirectType.recovery,
      );
      expect(url, 'http://localhost:5000/auth/callback?type=recovery');
    });

    test('https production-like origin works', () {
      final url = AuthRedirect.buildRedirect(
        'https://myapp.example.com',
        AuthRedirectType.signup,
      );
      expect(url, 'https://myapp.example.com/auth/callback?type=signup');
    });
  });

  group('Uri.origin (the actual mechanism we rely on)', () {
    test('strips path from a deep route URL', () {
      // Reproduce el bug original: si el usuario estaba en /forgot-password,
      // antes generábamos http://localhost:5000/forgot-password/auth/callback…
      // El fix usa Uri.origin, que devuelve sólo scheme://host:port.
      final base = Uri.parse('http://localhost:5000/forgot-password');
      expect(base.origin, 'http://localhost:5000');
    });

    test('strips path + query + fragment from a complex URL', () {
      final base = Uri.parse(
        'https://myapp.example.com/a/b/c?x=1&y=2#section',
      );
      expect(base.origin, 'https://myapp.example.com');
    });

    test('preserves non-default ports', () {
      final base = Uri.parse('http://localhost:5000/anywhere');
      expect(base.origin, 'http://localhost:5000');
    });
  });
}
