import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/app.dart';
import 'package:myapp/core/config/env_config.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      const envName = String.fromEnvironment('ENV', defaultValue: 'development');
      final env = switch (envName) {
        'production' || 'prod' => Environment.production,
        'staging' => Environment.staging,
        _ => Environment.development,
      };

      await EnvConfig.load(env: env);

      await Supabase.initialize(
        url: EnvConfig.supabaseUrl,
        anonKey: EnvConfig.supabaseAnonKey,
        debug: !EnvConfig.isProduction,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          autoRefreshToken: true,
        ),
      );

      final prefs = await SharedPreferences.getInstance();

      FlutterError.onError = (details) {
        AppLogger.e(
          'FlutterError',
          error: details.exception,
          stackTrace: details.stack,
        );
        if (kReleaseMode) FlutterError.presentError(details);
      };

      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: const MyApp(),
        ),
      );
    },
    (error, stack) => AppLogger.e('Uncaught', error: error, stackTrace: stack),
  );
}
