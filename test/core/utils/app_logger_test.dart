import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/core/utils/log_context.dart';

void main() {
  setUp(() {
    // En modo test (sin `EnvConfig.load`), dotenv arranca vacío. Forzamos
    // explícitamente el modo estructurado para que el logger emita JSON
    // sin importar el entorno.
    dotenv.testLoad(fileInput: 'STRUCTURED_LOGS=true\nENABLE_LOGGING=true');
  });

  tearDown(() {
    AppLogger.testSink = null;
  });

  group('AppLogger (JSON mode)', () {
    test('emits one JSON line per log with required fields', () {
      final captured = <String>[];
      AppLogger.testSink = (line, {Level? level}) => captured.add(line);

      AppLogger.i('hello');

      expect(captured, hasLength(1));
      final json = jsonDecode(captured.single) as Map<String, dynamic>;
      expect(json['msg'], 'hello');
      expect(json['level'], 'info');
      expect(json['env'], anyOf('dev', 'staging', 'prod'));
      expect(json['app'], isNotNull);
      expect(json['ts'], matches(r'^\d{4}-\d{2}-\d{2}T'));
      // correlation_id sólo aparece dentro de un LogContext.
      expect(json.containsKey('correlation_id'), isFalse);
    });

    test('maps levels: debug/info/warn/error', () {
      final captured = <String>[];
      AppLogger.testSink = (line, {Level? level}) => captured.add(line);

      AppLogger.d('a');
      AppLogger.i('b');
      AppLogger.w('c');
      AppLogger.e('d');

      final levels = captured
          .map((s) => (jsonDecode(s) as Map<String, dynamic>)['level'])
          .toList();
      expect(levels, ['debug', 'info', 'warn', 'error']);
    });

    test('includes error and stack on .e()', () {
      final captured = <String>[];
      AppLogger.testSink = (line, {Level? level}) => captured.add(line);

      AppLogger.e(
        'boom',
        error: StateError('bad'),
        stackTrace: StackTrace.current,
      );

      final json = jsonDecode(captured.single) as Map<String, dynamic>;
      expect(json['error'], contains('bad'));
      expect(json['stack'], isNotEmpty);
    });

    test('inherits correlation_id and tags from LogContext.run', () async {
      final captured = <String>[];
      AppLogger.testSink = (line, {Level? level}) => captured.add(line);

      await LogContext.run(
        correlationId: 'abc123',
        tags: {'flow': 'signup', 'user': 'u1'},
        () async {
          AppLogger.i('step 1');
          AppLogger.i('step 2', tags: {'extra': 'x'});
        },
      );

      expect(captured, hasLength(2));
      final l1 = jsonDecode(captured[0]) as Map<String, dynamic>;
      final l2 = jsonDecode(captured[1]) as Map<String, dynamic>;
      expect(l1['correlation_id'], 'abc123');
      expect(l1['tags'], {'flow': 'signup', 'user': 'u1'});
      expect(l2['correlation_id'], 'abc123');
      // tags se mergean: ctx + call-site.
      expect(l2['tags'], {'flow': 'signup', 'user': 'u1', 'extra': 'x'});
    });

    test('nested LogContext.run can override correlation_id', () async {
      final captured = <String>[];
      AppLogger.testSink = (line, {Level? level}) => captured.add(line);

      await LogContext.run(
        correlationId: 'outer',
        tags: {'a': '1'},
        () async {
          AppLogger.i('outer-1');
          await LogContext.run(
            correlationId: 'inner',
            tags: {'b': '2'},
            () async {
              AppLogger.i('inner');
            },
          );
          AppLogger.i('outer-2');
        },
      );

      final ids = captured
          .map((s) => (jsonDecode(s) as Map<String, dynamic>)['correlation_id'])
          .toList();
      expect(ids, ['outer', 'inner', 'outer']);
      final innerTags =
          (jsonDecode(captured[1]) as Map<String, dynamic>)['tags']
              as Map<String, dynamic>;
      // El hijo hereda tags del padre y añade los propios.
      expect(innerTags, {'a': '1', 'b': '2'});
    });
  });

  group('LogContext.newCorrelationId', () {
    test('generates non-empty, varying ids', () {
      final a = LogContext.newCorrelationId();
      final b = LogContext.newCorrelationId();
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a, isNot(equals(b)));
      expect(a.length, 12);
    });
  });
}
