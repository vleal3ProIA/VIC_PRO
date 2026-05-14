import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/router/route_names.dart';

void main() {
  group('RoutePaths', () {
    test('no two routes form a hierarchical prefix conflict', () {
      // go_router dispara `assert(uri.path.startsWith(matchedLocation))`
      // si una ruta plana es prefijo de otra ruta plana (ej. /otp vs /otp/verify).
      // Este test atrapa cualquier regresión de ese tipo.
      const paths = <String>[
        RoutePaths.welcome,
        RoutePaths.login,
        RoutePaths.register,
        RoutePaths.forgotPassword,
        RoutePaths.passwordResetSent,
        RoutePaths.setNewPassword,
        RoutePaths.passwordUpdated,
        RoutePaths.verifyEmailSent,
        RoutePaths.emailVerified,
        RoutePaths.magicLink,
        RoutePaths.magicLinkSent,
        RoutePaths.otpRequest,
        RoutePaths.otpVerify,
        RoutePaths.mfaSetup,
        RoutePaths.mfaChallenge,
        RoutePaths.home,
        RoutePaths.accountSettings,
        // authCallback queda exento: usa "/auth/callback" pero no existe
        // ninguna otra ruta que empiece por "/auth".
      ];

      for (final a in paths) {
        for (final b in paths) {
          if (a == b) continue;
          // Si a es prefijo "verdadero" de b (a != b y b empieza por a + '/'),
          // tenemos jerarquía implícita problemática.
          final isPrefixWithSlash = b.startsWith('$a/');
          expect(
            isPrefixWithSlash,
            isFalse,
            reason:
                'Route "$b" starts with "$a/" — go_router los tratará como '
                'jerárquicos y eso rompe la navegación entre ellos.',
          );
        }
      }
    });

    test('otpVerify uses dashed path (regresión del bug)', () {
      expect(RoutePaths.otpVerify, '/otp-verify');
      expect(
        RoutePaths.otpVerify.startsWith('${RoutePaths.otpRequest}/'),
        isFalse,
      );
    });
  });
}
