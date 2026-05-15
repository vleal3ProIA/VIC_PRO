import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/observability/analytics_event.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/utils/log_context.dart';

/// Backend de tests que captura los eventos en memoria para inspeccionarlos.
class _RecordingBackend implements AnalyticsBackend {
  final List<AnalyticsEvent> events = [];
  final List<({String userId, Map<String, Object?> traits})> identifies = [];
  int resets = 0;

  @override
  Future<void> track(AnalyticsEvent event) async {
    events.add(event);
  }

  @override
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async {
    identifies.add((userId: userId, traits: traits));
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'APP_NAME=myapp_test\nENABLE_ANALYTICS=true\n');
  });

  AnalyticsService buildService(AnalyticsBackend backend, {String? userId}) {
    return AnalyticsService(backend: backend, getUserId: () => userId);
  }

  group('AnalyticsService', () {
    test('track() enriches with env', () async {
      final backend = _RecordingBackend();
      final svc = buildService(backend);

      await svc.track('test_event', properties: {'foo': 'bar'});

      expect(backend.events, hasLength(1));
      final e = backend.events.single;
      expect(e.name, 'test_event');
      expect(e.properties['foo'], 'bar');
      expect(e.properties['env'], anyOf('dev', 'staging', 'prod'));
    });

    test('track() within LogContext enriches with correlation_id + tags',
        () async {
      final backend = _RecordingBackend();
      final svc = buildService(backend);

      await LogContext.run(
        correlationId: 'corr-1',
        tags: {'flow': 'signup'},
        () async {
          await svc.track('signup_started');
        },
      );

      final e = backend.events.single;
      expect(e.properties['correlation_id'], 'corr-1');
      expect(e.properties['flow'], 'signup');
    });

    test('identify() is idempotent for same userId', () async {
      final backend = _RecordingBackend();
      final svc = buildService(backend);

      await svc.identify('u1', traits: {'email': 'a@b.com'});
      await svc.identify('u1', traits: {'email': 'a@b.com'});

      expect(backend.identifies, hasLength(1));
      expect(backend.identifies.single.userId, 'u1');
    });

    test('identify() re-fires for different userId', () async {
      final backend = _RecordingBackend();
      final svc = buildService(backend);

      await svc.identify('u1');
      await svc.identify('u2');

      expect(backend.identifies, hasLength(2));
    });

    test('reset() resets the dedupe cache', () async {
      final backend = _RecordingBackend();
      final svc = buildService(backend);

      await svc.identify('u1');
      await svc.reset();
      await svc.identify('u1');

      expect(backend.identifies, hasLength(2));
      expect(backend.resets, 1);
    });

    test('track() swallows backend exceptions', () async {
      final svc = buildService(_ThrowingBackend());
      // No queremos que la app explote por analytics. El test pasa si esto
      // no lanza.
      await svc.track('whatever');
    });
  });

  group('NoopAnalyticsBackend', () {
    test('all methods are no-ops', () async {
      const b = NoopAnalyticsBackend();
      await b.track(const AnalyticsEvent('x'));
      await b.identify('u');
      await b.reset();
    });
  });
}

class _ThrowingBackend implements AnalyticsBackend {
  @override
  Future<void> track(AnalyticsEvent event) async =>
      throw StateError('backend down');

  @override
  Future<void> identify(
    String userId, {
    Map<String, Object?> traits = const {},
  }) async =>
      throw StateError('backend down');

  @override
  Future<void> reset() async => throw StateError('backend down');
}
