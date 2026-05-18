// ============================================================================
// PR-G · Tests E2E de los route guards del router
// ----------------------------------------------------------------------------
// Verifica la logica de `evaluateRouterRedirect()` (funcion pura) para
// todos los escenarios criticos del guard:
//
//   - Gate 0: setup wizard
//   - Gate 1: sesion / auth + registro cerrado
//   - Gate 2: MFA pendiente
//   - Gate admin-only
//   - Gate publicOnly (auth en login/register/...)
//   - Gate onboarding
//   - Rutas excluidas (auth/callback, password-updated, legal)
//
// La funcion pura `evaluateRouterRedirect` recibe estados ya resueltos
// (no necesita Ref ni Riverpod), asi que los tests son rapidos y sin
// arrancar Supabase. El wrapper `appRouterRedirect` que SI usa Riverpod
// se prueba indirectamente al verificar la logica de la pura.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/router/router_guards.dart';
import 'package:myapp/features/branding/domain/app_branding.dart';

void main() {
  group('evaluateRouterRedirect — Gate 0 (setup wizard)', () {
    test('setup_completed=false en cualquier ruta -> /setup', () {
      final result = _redirect(
        loc: RoutePaths.welcome,
        branding: _branding(setupCompleted: false),
      );
      expect(result, RoutePaths.setup);
    });

    test('setup_completed=false estando ya en /setup -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.setup,
        branding: _branding(setupCompleted: false),
      );
      expect(result, isNull);
    });

    test('setup_completed=true y user va a /setup -> /welcome (fuera)', () {
      final result = _redirect(
        loc: RoutePaths.setup,
        branding: _branding(setupCompleted: true),
      );
      expect(result, RoutePaths.welcome);
    });

    test('branding=null (loading) -> NO redirige (evita flash a /setup)', () {
      // Caso clave del fix de la manyana: si el provider esta loading
      // (valueOrNull == null), el guard NO debe disparar redirect a
      // /setup. Esa redirect solo procede cuando branding != null y
      // setup_completed es explicitamente false.
      final result = _redirect(loc: RoutePaths.welcome, branding: null);
      expect(result, isNull);
    });

    test('setup_completed=false PERO ruta es authCallback -> null', () {
      // El wizard mismo puede invocar /auth/callback al confirmar el
      // email del primer admin. Esa ruta debe seguir funcionando.
      final result = _redirect(
        loc: RoutePaths.authCallback,
        branding: _branding(setupCompleted: false),
      );
      expect(result, isNull);
    });

    test('setup_completed=false en /verify-email-sent -> null', () {
      final result = _redirect(
        loc: RoutePaths.verifyEmailSent,
        branding: _branding(setupCompleted: false),
      );
      expect(result, isNull);
    });
  });

  group('evaluateRouterRedirect — Gate 1 (sesion / auth)', () {
    test('no autenticado en /home -> /login', () {
      final result = _redirect(
        loc: RoutePaths.home,
        isAuthenticated: false,
      );
      expect(result, RoutePaths.login);
    });

    test('no autenticado en /admin -> /login (es privada)', () {
      final result = _redirect(
        loc: RoutePaths.admin,
        isAuthenticated: false,
      );
      expect(result, RoutePaths.login);
    });

    test('no autenticado en /admin/users -> /login (privada via _isAdmin)',
        () {
      final result = _redirect(
        loc: RoutePaths.adminUsers,
        isAuthenticated: false,
      );
      expect(result, RoutePaths.login);
    });

    test('no autenticado en /account-settings/webhooks/<uuid> -> /login', () {
      // Patron parametrizado que `_isPrivate` reconoce por prefix.
      final result = _redirect(
        loc: '/account-settings/webhooks/abc-123',
        isAuthenticated: false,
      );
      expect(result, RoutePaths.login);
    });

    test('no autenticado en /register con registro CERRADO -> /login', () {
      final result = _redirect(
        loc: RoutePaths.register,
        isAuthenticated: false,
        branding: _branding(registrationEnabled: false),
      );
      expect(result, RoutePaths.login);
    });

    test('no autenticado en /register con registro ABIERTO -> null (pasa)',
        () {
      final result = _redirect(
        loc: RoutePaths.register,
        isAuthenticated: false,
        branding: _branding(registrationEnabled: true),
      );
      expect(result, isNull);
    });

    test('no autenticado en /register con branding loading -> null (pasa)',
        () {
      // Mientras carga, asumimos registro abierto para no bloquear de
      // mas. La pantalla register decide al renderizar.
      final result = _redirect(
        loc: RoutePaths.register,
        isAuthenticated: false,
        branding: null,
      );
      expect(result, isNull);
    });

    test('no autenticado en /login -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.login,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('no autenticado en /welcome -> null (publica)', () {
      final result = _redirect(
        loc: RoutePaths.welcome,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });
  });

  group('evaluateRouterRedirect — Gate 2 (MFA pendiente)', () {
    test('autenticado con MFA pending en /home -> /mfa-challenge', () {
      final result = _redirect(
        loc: RoutePaths.home,
        isAuthenticated: true,
        mfaPending: true,
      );
      expect(result, RoutePaths.mfaChallenge);
    });

    test('autenticado con MFA pending en /admin -> /mfa-challenge', () {
      final result = _redirect(
        loc: RoutePaths.admin,
        isAuthenticated: true,
        mfaPending: true,
        isAdmin: true,
      );
      expect(result, RoutePaths.mfaChallenge);
    });

    test('autenticado SIN MFA pending en /mfa-challenge -> /home', () {
      // Ya resolvio el factor; quitarlo del flow.
      final result = _redirect(
        loc: RoutePaths.mfaChallenge,
        isAuthenticated: true,
        mfaPending: false,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado en /mfa-challenge con MFA pending -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.mfaChallenge,
        isAuthenticated: true,
        mfaPending: true,
      );
      expect(result, isNull);
    });
  });

  group('evaluateRouterRedirect — Gate admin-only', () {
    test('autenticado NO admin en /admin -> /home', () {
      final result = _redirect(
        loc: RoutePaths.admin,
        isAuthenticated: true,
        isAdmin: false,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado NO admin en /admin/users -> /home', () {
      final result = _redirect(
        loc: RoutePaths.adminUsers,
        isAuthenticated: true,
        isAdmin: false,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado NO admin en /admin/users/<uuid> (subruta) -> /home', () {
      final result = _redirect(
        loc: '/admin/users/abc-123',
        isAuthenticated: true,
        isAdmin: false,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado NO admin en /admin/broadcasts/<uuid> -> /home', () {
      final result = _redirect(
        loc: '/admin/broadcasts/xyz',
        isAuthenticated: true,
        isAdmin: false,
      );
      expect(result, RoutePaths.home);
    });

    test('admin en /admin -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.admin,
        isAuthenticated: true,
        isAdmin: true,
      );
      expect(result, isNull);
    });

    test('admin en /admin/users -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.adminUsers,
        isAuthenticated: true,
        isAdmin: true,
      );
      expect(result, isNull);
    });
  });

  group('evaluateRouterRedirect — Gate publicOnly (auth en publicas)', () {
    test('autenticado en /login -> /home', () {
      final result = _redirect(
        loc: RoutePaths.login,
        isAuthenticated: true,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado en /register -> /home', () {
      final result = _redirect(
        loc: RoutePaths.register,
        isAuthenticated: true,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado en /forgot-password -> /home', () {
      final result = _redirect(
        loc: RoutePaths.forgotPassword,
        isAuthenticated: true,
      );
      expect(result, RoutePaths.home);
    });

    test('autenticado en /magic-link -> /home', () {
      final result = _redirect(
        loc: RoutePaths.magicLink,
        isAuthenticated: true,
      );
      expect(result, RoutePaths.home);
    });
  });

  group('evaluateRouterRedirect — Gate onboarding', () {
    test('autenticado SIN onboarding completado en /home -> /onboarding', () {
      final result = _redirect(
        loc: RoutePaths.home,
        isAuthenticated: true,
        onboardingCompleted: false,
      );
      expect(result, RoutePaths.onboarding);
    });

    test(
      'autenticado SIN onboarding en ruta NO gated (passkeys) -> null (pasa)',
      () {
        // Solo se redirige a /onboarding en rutas explicitamente
        // gated (home, admin, account-settings, plans, etc.). Las
        // pantallas auxiliares como passkeys deben funcionar.
        final result = _redirect(
          loc: RoutePaths.passkeys,
          isAuthenticated: true,
          onboardingCompleted: false,
        );
        expect(result, isNull);
      },
    );

    test('autenticado con onboarding loading (null) -> null (sin flash)', () {
      final result = _redirect(
        loc: RoutePaths.home,
        isAuthenticated: true,
        onboardingCompleted: null,
      );
      expect(result, isNull);
    });

    test('autenticado en /onboarding (ya esta alli) -> null', () {
      final result = _redirect(
        loc: RoutePaths.onboarding,
        isAuthenticated: true,
        onboardingCompleted: false,
      );
      expect(result, isNull);
    });

    test('autenticado con onboarding completado en /home -> null (pasa)', () {
      final result = _redirect(
        loc: RoutePaths.home,
        isAuthenticated: true,
        onboardingCompleted: true,
      );
      expect(result, isNull);
    });
  });

  group('evaluateRouterRedirect — Rutas excluidas del guard', () {
    test('/auth/callback sin sesion -> null (debe poder procesar code)', () {
      final result = _redirect(
        loc: RoutePaths.authCallback,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('/password-updated sin sesion -> null (cierra sesion al entrar)',
        () {
      final result = _redirect(
        loc: RoutePaths.passwordUpdated,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('/set-new-password sin sesion -> null', () {
      final result = _redirect(
        loc: RoutePaths.setNewPassword,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('/terms sin sesion -> null (legal publica)', () {
      final result = _redirect(
        loc: RoutePaths.terms,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('/privacy sin sesion -> null', () {
      final result = _redirect(
        loc: RoutePaths.privacy,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });

    test('/cookies sin sesion -> null', () {
      final result = _redirect(
        loc: RoutePaths.cookies,
        isAuthenticated: false,
      );
      expect(result, isNull);
    });
  });
}

// ─────────────────────────── helpers ───────────────────────────

/// Construye un AppBranding sintetico con los flags que importan al
/// router. Defaults: setup_completed=true (no fuerza a /setup),
/// registration_enabled=true (no bloquea /register).
AppBranding _branding({
  bool setupCompleted = true,
  bool registrationEnabled = true,
}) {
  return AppBranding(
    commercialName: 'test',
    colorPalette: 'blue',
    setupCompleted: setupCompleted,
    registrationEnabled: registrationEnabled,
  );
}

/// Wrapper sobre `evaluateRouterRedirect` con defaults razonables para
/// no repetir todos los args en cada test.
///
/// - `branding`: por defecto = setup completed + registration open.
///   Pasa `null` para simular "loading" desde el FutureProvider.
/// - `isAuthenticated`: default false (estado "anonimo").
/// - `mfaPending`, `isAdmin`: default false.
/// - `onboardingCompleted`: default true (no fuerza redirect a onboarding).
String? _redirect({
  required String loc,
  AppBranding? branding = const _DefaultBrandingMarker(),
  bool isAuthenticated = false,
  bool mfaPending = false,
  bool isAdmin = false,
  bool? onboardingCompleted = true,
}) {
  // Permitimos a los tests pasar `branding: null` para simular loading,
  // pero queremos default "branding completo" si NO se especifica. Como
  // no se puede tener default != null en un parametro nullable, usamos
  // un marker.
  final resolvedBranding = identical(branding, const _DefaultBrandingMarker())
      ? _branding()
      : branding;

  return evaluateRouterRedirect(
    matchedLocation: loc,
    isAuthenticated: isAuthenticated,
    branding: resolvedBranding,
    mfaPending: mfaPending,
    isAdmin: isAdmin,
    onboardingCompleted: onboardingCompleted,
  );
}

/// Marker para distinguir "param no pasado" de "param=null explicito".
/// Necesario porque Dart no permite defaults != null en nullables.
class _DefaultBrandingMarker implements AppBranding {
  const _DefaultBrandingMarker();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
