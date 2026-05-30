// ============================================================================
// user_cache_guard.dart · Invalidación de caches user-scoped al cambiar sesión
// ----------------------------------------------------------------------------
// Bug reportado (29-may-2026):
//   - El super-admin cerró sesión y un usuario NUEVO inició sesión.
//   - El usuario nuevo vio el temario del super-admin durante un instante.
//   - Al recargar la página, los datos se reemplazaron por los suyos.
//
// Causa raíz:
//   Los providers de Riverpod (FutureProvider/StreamProvider/etc.) cachean
//   sus valores hasta que algo los invalida. `authStateChangesProvider` se
//   actualiza al cambiar la sesión, pero los providers de DATOS del usuario
//   (subjectsListProvider, profileSettingsNotifierProvider, etc.) NO se
//   re-evalúan automáticamente — siguen mostrando los datos del usuario
//   anterior hasta que el caller fuerce un `ref.invalidate()` o un refresh
//   manual de la página.
//
//   Es una fuga de datos cross-user a nivel de cache cliente, no de RLS.
//   RLS bloquea correctamente las consultas nuevas; el problema es que los
//   datos VIEJOS siguen en memoria del navegador hasta el primer fetch
//   nuevo.
//
// Fix:
//   Listener global que detecta cambios de `currentUser.id` (a otro user,
//   a null por logout, o de null a un user por login) y invalida en
//   cascada todos los providers data-source user-scoped. Como cada uno de
//   esos data-source providers es la raíz de su feature (todos los
//   providers de datos de la feature dependen de él vía `ref.watch`),
//   invalidar el raíz invalida toda la cadena: subjects → flashcards →
//   exams → etc. en un solo paso.
//
//   Los providers de INFRA (cliente Supabase, locale, theme, branding del
//   deploy) NO se invalidan — son globales al deploy, no al usuario.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/application/auth_sessions_providers.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/admin_users/application/admin_users_providers.dart';
import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/billing/application/billing_providers.dart';
import 'package:myapp/features/broadcasts/application/broadcasts_providers.dart';
import 'package:myapp/features/emails/application/email_log_providers.dart';
import 'package:myapp/features/onboarding/application/onboarding_providers.dart';
import 'package:myapp/features/subjects/application/subjects_providers.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:myapp/features/tokens/application/tokens_providers.dart';
import 'package:myapp/features/uploads/application/uploads_providers.dart';
import 'package:myapp/features/webhooks/application/webhooks_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lista de data-source providers cuyo cache hay que tirar al cambiar de
/// usuario. Cada uno es la raíz de su feature: invalidarlo tumba en cascada
/// todos los `*Provider`/`*Family` que lo `ref.watch()` (lista del temario,
/// detalle de factura, sesiones activas, etc.).
///
/// ¿Cómo decidir si un provider va aquí?
///   - SÍ si carga datos asociados al `auth.uid()` (los más típicos).
///   - SÍ si carga datos de tenants donde el user es miembro.
///   - NO si es infra global (branding del deploy, lista pública de planes,
///     incidents, changelog público).
///   - NO si depende ya de `currentUser` vía `ref.watch` directo (Riverpod
///     ya lo invalida solo).
final List<ProviderOrFamily> _userScopedDataSources = [
  // Cuenta + perfil
  profileDataSourceProvider,
  profileRepositoryProvider,
  authSessionsDataSourceProvider,

  // Workspace del usuario
  subjectsDataSourceProvider,
  uploadsDataSourceProvider,
  tokensDataSourceProvider,
  webhooksDataSourceProvider,
  tenantDataSourceProvider,
  auditLogDataSourceProvider,
  emailLogDataSourceProvider,
  broadcastsDataSourceProvider,

  // Billing del usuario
  billingDataSourceProvider,

  // Onboarding (estado por user)
  onboardingDataSourceProvider,

  // Admin (los datos no son del user, pero la VISIBILIDAD depende del rol
  // del user actual — invalidamos para evitar que un user-normal vea cache
  // de un panel admin tras un logout+login).
  adminUsersDataSourceProvider,
];

/// Side-effect-only provider. Se "lee" desde `MyApp.build` con
/// `ref.watch(userCacheGuardProvider)` igual que los otros sync providers
/// (Sentry/Analytics/Tenant). Una vez activo, mantiene una suscripción al
/// `currentUserProvider` durante toda la vida del container y, cuando el
/// `user.id` cambia, invalida los data sources user-scoped.
///
/// Retorna `void` porque el efecto es completo en la suscripción — no hay
/// estado expuesto al caller.
final userCacheGuardProvider = Provider<void>((ref) {
  String? lastUserId = ref.read(currentUserProvider)?.id;

  ref.listen<User?>(currentUserProvider, (prev, next) {
    final String? nextId = next?.id;
    if (nextId == lastUserId) return;

    // El user actual cambió. Tres casos:
    //   - logout: user X -> null. Invalidamos por si la app vuelve a otra
    //     pantalla del shell durante el unmount.
    //   - login fresh: null -> user X. Invalidamos por si quedó cache de
    //     una sesión anterior cerrada en otro tab del navegador.
    //   - switch: user X -> user Y. EL CASO CRÍTICO del bug reportado.
    lastUserId = nextId;
    for (final p in _userScopedDataSources) {
      ref.invalidate(p);
    }
  });
});
