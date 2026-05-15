import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/observability/sentry_service.dart';

/// Tests del `SentryService` cuando NO hay DSN configurado: todas las
/// llamadas deben ser no-op silenciosas para que dev/CI funcionen sin
/// cuenta de Sentry.
///
/// (No probamos el modo "DSN activo" con tests de unidad porque eso
/// requeriría arrancar el SDK real con un endpoint mock. Esa rama queda
/// cubierta por staging.)
void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'APP_NAME=myapp_test\n');
  });

  group('SentryService without DSN', () {
    test('isEnabled is false', () {
      expect(SentryService.isEnabled, isFalse);
    });

    test('capture() is a no-op (does not throw)', () async {
      await SentryService.capture(
        StateError('boom'),
        stackTrace: StackTrace.current,
        tags: const {'feature': 'auth'},
        message: 'a boom',
      );
      // Nada que assert: el contrato es que no lance.
    });

    test('captureMessage() is a no-op (does not throw)', () async {
      await SentryService.captureMessage(
        'warn-event',
        tags: const {'k': 'v'},
      );
    });

    test('setUser() / clear is a no-op (does not throw)', () async {
      await SentryService.setUser(id: 'u1', email: 'a@b.com');
      await SentryService.setUser();
    });

    test('init() without DSN just runs the appRunner', () async {
      var ran = false;
      await SentryService.init(
        runApp: () {
          ran = true;
        },
      );
      expect(ran, isTrue);
      expect(SentryService.isEnabled, isFalse);
    });
  });
}
