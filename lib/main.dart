import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:myapp/app.dart';
import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/observability/sentry_service.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/storage/remember_aware_local_storage.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // En Flutter web: URLs limpias (sin `#`).
      // Imprescindible para que los emails de Supabase con
      // `http://host/auth/callback?...` aterricen en la ruta correcta del
      // router en lugar de en `/` (welcome).
      if (kIsWeb) {
        usePathUrlStrategy();
      }

      const envName = String.fromEnvironment('ENV', defaultValue: 'development');
      final env = switch (envName) {
        'production' || 'prod' => Environment.production,
        'staging' => Environment.staging,
        _ => Environment.development,
      };

      await EnvConfig.load(env: env);

      // Necesario ANTES de Supabase.initialize porque pasamos un
      // LocalStorage custom que lee de SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      final rememberStorage = RememberAwareLocalStorage(prefs);

      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
        debug: !EnvConfig.isProduction,
        // Implicit flow para web SPA:
        // - Tokens llegan en fragment URL (#access_token=…) en lugar de
        //   ?code= con code_verifier en localStorage.
        // - El SDK los procesa automáticamente al inicializarse.
        //
        // Storage custom:
        // - En web, sessionStorage por defecto (sesión se cierra al cerrar
        //   pestaña). localStorage si el usuario marcó "Recordar sesión".
        // - En no-web, el SDK usa su storage default persistente.
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.implicit,
          autoRefreshToken: true,
          localStorage: rememberStorage,
        ),
      );

      FlutterError.onError = (details) {
        AppLogger.e(
          'FlutterError',
          error: details.exception,
          stackTrace: details.stack,
        );
        if (kReleaseMode) FlutterError.presentError(details);
      };

      // Sentry envuelve el `runApp` cuando hay DSN configurado por
      // --dart-define=SENTRY_DSN=https://...; si no hay DSN, ejecuta el
      // runApp directamente (no-op). Toda la observabilidad sigue
      // funcionando aunque Sentry esté off (AppLogger sigue logueando JSON).
      await SentryService.init(
        runApp: () {
          runApp(
            ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
              ],
              child: const MyApp(),
            ),
          );
        },
      );
    },
    (error, stack) => AppLogger.e('Uncaught', error: error, stackTrace: stack),
  );
}
