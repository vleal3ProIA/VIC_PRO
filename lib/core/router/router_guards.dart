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
  RoutePaths.myMaterial,
  RoutePaths.admin,
  RoutePaths.adminMaterialLibrary,
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
  RoutePaths.adminAudit,
  RoutePaths.adminAiProviders,
  RoutePaths.adminPublicDomainSources,
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
  RoutePaths.adminMaterialLibrary,
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
  RoutePaths.adminAudit,
  RoutePaths.adminAdmins,
  RoutePaths.adminAiProviders,
  RoutePaths.adminPublicDomainSources,
};

/// Mapeo route -> capability requerida (post migracion 0044). Si una
/// ruta esta aqui, el user necesita esa capacidad ademas de ser admin
/// (basic gate). El super admin tiene todas las capabilities
/// automaticamente, asi que puede entrar a cualquiera.
///
/// `/admin` (menu) NO esta aqui -- cualquier admin puede entrar al
/// menu, donde vera solo las cards de las capabilities que tiene.
///
/// `/admin/admins` requiere ser super -- gestionado en el guard con
/// el flag `isSuperAdmin` (no via capability, porque no es una de las
/// 13 -- es una accion exclusiva del super).
const Map<String, String> kRouteToCapability = {
  RoutePaths.adminFlags:        'manage_flags',
  RoutePaths.adminPlans:        'manage_plans',
  RoutePaths.adminBranding:     'manage_branding',
  RoutePaths.adminCoupons:      'manage_coupons',
  RoutePaths.adminTrash:        'manage_trash',
  RoutePaths.adminChangelog:    'manage_changelog',
  RoutePaths.adminAppBranding:  'manage_app_branding',
  RoutePaths.adminEmailLog:     'view_email_log',
  RoutePaths.adminUsers:        'manage_users',
  RoutePaths.adminMetrics:      'view_metrics',
  RoutePaths.adminBroadcasts:   'manage_broadcasts',
  RoutePaths.adminBroadcastsNew:'manage_broadcasts',
  RoutePaths.adminIncidents:    'manage_incidents',
  RoutePaths.adminAudit:        'run_audits',
  RoutePaths.adminAiProviders:  'manage_ai',
};

/// Devuelve la capability requerida por una ruta, o `null` si la ruta
/// no requiere capability concreta (solo `isAdmin`).
String? requiredCapability(String loc) {
  if (kRouteToCapability.containsKey(loc)) {
    return kRouteToCapability[loc];
  }
  // Patrones parametrizados.
  if (loc.startsWith('/admin/users/'))      return 'manage_users';
  if (loc.startsWith('/admin/broadcasts/')) return 'manage_broadcasts';
  if (loc.startsWith('/admin/audit/'))      return 'run_audits';
  return null;
}

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
  if (loc.startsWith('/admin/audit/')) return true;
  if (loc.startsWith('/admin/material-library/')) return true;
  return false;
}

/// Mismo concepto que `isPrivateRoute` pero para rutas SOLO admin.
bool isAdminRoute(String loc) {
  if (adminRoutes.contains(loc)) return true;
  if (loc.startsWith('/admin/users/')) return true;
  if (loc.startsWith('/admin/broadcasts/')) return true;
  if (loc.startsWith('/admin/audit/')) return true;
  if (loc.startsWith('/admin/material-library/')) return true;
  return false;
}

/// `true` si la ruta es exclusiva del super admin: `/admin/admins` y
/// `/admin/material-library` (+ su detalle `/admin/material-library/:id`).
/// Un admin normal no puede entrar -> guard redirige a /admin.
bool isSuperAdminRoute(String loc) {
  if (loc == RoutePaths.adminAdmins) return true;
  if (loc == RoutePaths.adminMaterialLibrary) return true;
  if (loc.startsWith('/admin/material-library/')) return true;
  if (loc == RoutePaths.adminPublicDomainSources) return true;
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
  bool isSuperAdmin = false,
  Set<String> capabilities = const <String>{},
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

  // 2c) Ruta solo-super (gestion de admins) y el user no es super
  //     -> /admin (el menu, donde le dejara claro que no tiene
  //     acceso a esa pieza concreta). Defensa-en-profundidad: el
  //     server tambien rechazara las RPCs `super_admin_*` con
  //     PostgrestException si llamadas por non-super.
  if (isAuthed && isSuperAdminRoute(loc) && !isSuperAdmin) {
    return RoutePaths.admin;
  }

  // 2d) Ruta admin con capability requerida + el user es admin pero
  //     SIN esa capacidad concreta -> /admin (el menu sin esa card).
  //     Super tiene todas las capabilities, asi que pasa siempre.
  //     Si `capabilities` es vacio (cargando del backend), NO
  //     redirigimos para evitar flash -- la pagina destino debe
  //     manejar su propio loading state.
  if (isAuthed && isAdmin && !isSuperAdmin && capabilities.isNotEmpty) {
    final required = requiredCapability(loc);
    if (required != null && !capabilities.contains(required)) {
      return RoutePaths.admin;
    }
  }

  // 3) Autenticado (y sin MFA pendiente) en ruta solo para invitados.
  if (isAuthed && publicOnly.contains(loc)) {
    return RoutePaths.home;
  }

  // 4) Si ya completó MFA y está en /mfa-challenge → /home.
  if (isAuthed && loc == RoutePaths.mfaChallenge && !mfaPending) {
    return RoutePaths.home;
  }

  // 5) Onboarding wizard: DESACTIVADO. Antes redirigíamos a /onboarding a
  //    los usuarios nuevos (onboarding_completed_at == null). Ahora, tras
  //    login, van directos a /home. El wizard y su ruta siguen existiendo
  //    pero ya no se fuerzan (código inactivo, reversible). Se conservan
  //    `onboardingCompleted` y `onboardingGatedRoutes` por si se reactiva.

  return null;
}
