// ============================================================================
// Logica pura de los guards del router (PR-G)
// ----------------------------------------------------------------------------
// Aislado en este archivo para que los tests unitarios puedan
// importarlo SIN arrastrar dependencias web-only (webauthn_js,
// stripe_js, etc.) que `app_router.dart` importa via las pages.
//
// `app_router.dart` re-exporta `evaluateRouterRedirect` y los sets de
// rutas (`privateRoutes`, `adminRoutes`, etc.) para mantener la API
// publica estable -- callers siguen importando `app_router.dart`.
// ============================================================================

import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/branding/domain/app_branding.dart';

// ─────────────────────────── Listas de rutas ───────────────────────────

/// Rutas que NO se ven afectadas por los guards de auth:
/// - `/auth/callback` siempre debe poder procesar el code.
/// - `/set-new-password` requiere sesión activa (la del recovery) y NO debe
///   redirigir a /home al detectar sesión.
/// - `/password-updated` cierra sesión al entrar, así que debe poder mostrarse.
/// - `/email-verified` igualmente: visible sin importar el estado.
/// - `/terms` y `/privacy` son documentos legales: accesibles siempre, con o
///   sin sesión (se enlazan desde el registro y el footer público).
const excludedFromGuard = <String>{
  RoutePaths.authCallback,
  RoutePaths.setNewPassword,
  RoutePaths.passwordUpdated,
  RoutePaths.emailVerified,
  RoutePaths.verifyEmailSent,
  RoutePaths.emailChanged,
  RoutePaths.terms,
  RoutePaths.privacy,
  RoutePaths.cookies,
  // `/status` es publico: util enseñarlo a evaluadores que aun no
  // tienen sesion y a usuarios logueados que entran a investigar un
  // incidente. NO redirigir aunque haya sesion.
  RoutePaths.status,
};

/// Rutas privadas (requieren sesión activa).
const privateRoutes = <String>{
  RoutePaths.home,
  RoutePaths.admin,
  RoutePaths.adminFlags,
  RoutePaths.adminPlans,
  RoutePaths.adminBranding,
  RoutePaths.adminCoupons,
  RoutePaths.adminTrash,
  RoutePaths.adminChangelog,
  RoutePaths.adminAppBranding,
  RoutePaths.adminEmailLog,
  RoutePaths.adminUsers,
  RoutePaths.adminMetrics,
  RoutePaths.adminBroadcasts,
  RoutePaths.adminBroadcastsNew,
  RoutePaths.adminIncidents,
  RoutePaths.changelog,
  RoutePaths.mfaSetup,
  RoutePaths.accountSettings,
  RoutePaths.changePassword,
  RoutePaths.changePasswordDone,
  RoutePaths.changeEmail,
  RoutePaths.changeEmailSent,
  RoutePaths.deleteAccount,
  RoutePaths.passkeys,
  RoutePaths.sessions,
  RoutePaths.files,
  RoutePaths.tokens,
  RoutePaths.webhooks,
  RoutePaths.notifications,
  RoutePaths.onboarding,
  RoutePaths.auditLog,
  RoutePaths.activity,
  RoutePaths.team,
  RoutePaths.plans,
  RoutePaths.billingSuccess,
  RoutePaths.billingInfo,
  RoutePaths.embeddedCheckout,
  RoutePaths.invoices,
  // `acceptInvite` se gestiona dentro de la propia página: si no hay sesión,
  // redirige al login él mismo. No la metemos como privada para que un
  // usuario sin sesión pueda al menos VER el error si el link es inválido.
};

/// Rutas que además requieren rol `admin`. Un usuario autenticado sin ese
/// rol que las pida es redirigido a `/home`.
const adminRoutes = <String>{
  RoutePaths.admin,
  RoutePaths.adminFlags,
  RoutePaths.adminPlans,
  RoutePaths.adminBranding,
  RoutePaths.adminCoupons,
  RoutePaths.adminTrash,
  RoutePaths.adminChangelog,
  RoutePaths.adminAppBranding,
  RoutePaths.adminEmailLog,
  RoutePaths.adminUsers,
  RoutePaths.adminMetrics,
  RoutePaths.adminBroadcasts,
  RoutePaths.adminBroadcastsNew,
  RoutePaths.adminIncidents,
};

/// Rutas públicas en las que NO queremos estar si ya hay sesión.
const publicOnly = <String>{
  RoutePaths.login,
  RoutePaths.register,
  RoutePaths.forgotPassword,
  RoutePaths.passwordResetSent,
  RoutePaths.magicLink,
  RoutePaths.magicLinkSent,
  RoutePaths.otpRequest,
  RoutePaths.otpVerify,
};

/// Rutas donde el onboarding gate se aplica. Lista explícita (no
/// "todas las privadas") porque /accept-invite, /change-email-sent y
/// similares deben funcionar incluso pre-onboarding (link en email).
const onboardingGatedRoutes = <String>{
  RoutePaths.home,
  RoutePaths.admin,
  RoutePaths.accountSettings,
  RoutePaths.plans,
  RoutePaths.billingInfo,
  RoutePaths.invoices,
  RoutePaths.team,
  RoutePaths.notifications,
  RoutePaths.activity,
};

/// `true` si la ruta necesita sesión. Lista exacta de `privateRoutes`
/// más los patrones parametrizados que el `Set` exacto no atrapa
/// (ej. `/account-settings/webhooks/<uuid>`).
bool isPrivateRoute(String loc) {
  if (privateRoutes.contains(loc)) return true;
  if (loc.startsWith('/account-settings/webhooks/')) return true;
  if (loc.startsWith('/admin/users/')) return true;
  if (loc.startsWith('/admin/broadcasts/')) return true;
  return false;
}

/// Mismo concepto que `isPrivateRoute` pero para rutas SOLO admin.
bool isAdminRoute(String loc) {
  if (adminRoutes.contains(loc)) return true;
  if (loc.startsWith('/admin/users/')) return true;
  if (loc.startsWith('/admin/broadcasts/')) return true;
  return false;
}

// ─────────────────────────── La logica pura ───────────────────────────

/// Logica del guard del router. Recibe estados ya resueltos y devuelve
/// la ruta a redirigir o `null` si no procede redirect.
///
/// **Por que pura?** Para poder testearla sin levantar Riverpod ni
/// Supabase (ver `test/core/router/app_router_guards_test.dart`). El
/// wrapper `appRouterRedirect` en `app_router.dart` se encarga de leer
/// los providers.
///
/// **Parametros**:
/// - `branding`: `null` significa "todavia cargando del backend"; en
///   ese caso NO disparamos Gate 0 (evita flash a /setup mientras
///   carga la query a `app_branding`).
/// - `onboardingCompleted`: misma logica -- `null` = cargando, NO
///   redirigimos a /onboarding hasta saberlo cierto.
String? evaluateRouterRedirect({
  required String matchedLocation,
  required bool isAuthenticated,
  required AppBranding? branding,
  required bool mfaPending,
  required bool isAdmin,
  required bool? onboardingCompleted,
}) {
  final loc = matchedLocation;
  if (excludedFromGuard.contains(loc)) return null;

  // ─────────────── Gate 0: setup_completed ───────────────
  // Antes de cualquier otra cosa, si el deploy no ha pasado por
  // /setup, fuerza al usuario a entrar ahí. Excepción: /setup mismo
  // y rutas de auth necesarias para crear el primer admin.
  //
  // OJO: leemos el branding como puede-ser-null. Si branding == null
  // significa que `appBrandingProvider` todavia esta cargando -> NO
  // redirigimos. Asi evitamos un flash a /setup cuando la BD si tiene
  // setup_completed=true pero la query aun no resolvio.
  if (branding != null &&
      !branding.setupCompleted &&
      loc != RoutePaths.setup) {
    const setupAllowed = {
      RoutePaths.authCallback,
      RoutePaths.verifyEmailSent,
      RoutePaths.emailVerified,
    };
    if (!setupAllowed.contains(loc)) {
      return RoutePaths.setup;
    }
  }
  // Si ya está completado y alguien intenta volver a /setup, fuera.
  if (branding != null &&
      branding.setupCompleted &&
      loc == RoutePaths.setup) {
    return RoutePaths.welcome;
  }

  final isAuthed = isAuthenticated;

  // 1) No autenticado y la ruta requiere sesión → login.
  if (!isAuthed && isPrivateRoute(loc)) {
    return RoutePaths.login;
  }

  // 1b) Gate de registro: si está cerrado y alguien intenta /register,
  //     lo mandamos a /login con un toast (lo gestiona la propia
  //     pantalla register al detectar la flag).
  //     Mientras el branding carga, asumimos abierto (mejor mostrar la
  //     pantalla y dejar que la propia /register decida que hacer si
  //     resulta estar cerrado, que bloquear de mas con un valor stale).
  if (!isAuthed &&
      loc == RoutePaths.register &&
      branding != null &&
      !branding.registrationEnabled) {
    return RoutePaths.login;
  }

  // 2) Si está autenticado pero su AAL no es el requerido (MFA pendiente),
  //    cualquier ruta lleva a /mfa-challenge salvo la propia /mfa-challenge.
  if (isAuthed && loc != RoutePaths.mfaChallenge && mfaPending) {
    return RoutePaths.mfaChallenge;
  }

  // 2b) Ruta solo-admin y el usuario no tiene ese rol → /home.
  if (isAuthed && isAdminRoute(loc) && !isAdmin) {
    return RoutePaths.home;
  }

  // 3) Autenticado (y sin MFA pendiente) en ruta solo para invitados.
  if (isAuthed && publicOnly.contains(loc)) {
    return RoutePaths.home;
  }

  // 4) Si ya completó MFA y está en /mfa-challenge → /home.
  if (isAuthed && loc == RoutePaths.mfaChallenge && !mfaPending) {
    return RoutePaths.home;
  }

  // 5) Onboarding wizard: usuario autenticado sin onboarding completado
  //    se redirige a /onboarding -- excepto si ya está allí o en rutas
  //    transversales que NO queremos bloquear (logout, legal, callback).
  //    Si el flag aún está cargando (null), NO redirigimos -- evita
  //    el flash de /onboarding antes de saber el estado real.
  if (isAuthed &&
      loc != RoutePaths.onboarding &&
      onboardingGatedRoutes.contains(loc) &&
      onboardingCompleted == false) {
    return RoutePaths.onboarding;
  }

  return null;
}
