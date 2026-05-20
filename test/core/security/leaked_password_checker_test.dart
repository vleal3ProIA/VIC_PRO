import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myapp/core/security/leaked_password_checker.dart';

void main() {
  // SHA-1("password") = 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8
  //   prefix = 5BAA6
  //   suffix = 1E4C9B93F3F0682250B6CF8331B7EE68FD8
  const knownSuffix = '1E4C9B93F3F0682250B6CF8331B7EE68FD8';

  group('LeakedPasswordChecker.pwnedCount', () {
    test('devuelve el count cuando el sufijo aparece en la respuesta', () async {
      final client = MockClient((req) async {
        // Verificamos que SOLO se envía el prefijo de 5 chars (k-anonimato).
        expect(req.url.toString(), contains('/range/5BAA6'));
        expect(req.url.toString(), isNot(contains(knownSuffix)));
        return http.Response(
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:3\r\n'
          '$knownSuffix:12345\r\n'
          'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF:7',
          200,
        );
      });
      final checker = LeakedPasswordChecker(client);
      expect(await checker.pwnedCount('password'), 12345);
      expect(await checker.isLeaked('password'), isTrue);
    });

    test('devuelve 0 cuando el sufijo NO aparece (password limpia)', () async {
      final client = MockClient((req) async {
        return http.Response(
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:3\r\n'
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:7',
          200,
        );
      });
      final checker = LeakedPasswordChecker(client);
      expect(await checker.pwnedCount('password'), 0);
      expect(await checker.isLeaked('password'), isFalse);
    });

    test('fail-open: HTTP 5xx → 0', () async {
      final client = MockClient((req) async => http.Response('err', 503));
      expect(await LeakedPasswordChecker(client).pwnedCount('password'), 0);
    });

    test('fail-open: excepción de red → 0', () async {
      final client = MockClient((req) async {
        throw Exception('network down');
      });
      expect(await LeakedPasswordChecker(client).pwnedCount('password'), 0);
    });

    test('password vacía → 0 sin llamar a la red', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('', 200);
      });
      expect(await LeakedPasswordChecker(client).pwnedCount(''), 0);
      expect(called, isFalse);
    });

    test('tolera sufijo en minúsculas en la respuesta', () async {
      final client = MockClient((req) async {
        return http.Response('${knownSuffix.toLowerCase()}:42', 200);
      });
      expect(await LeakedPasswordChecker(client).pwnedCount('password'), 42);
    });
  });
}
