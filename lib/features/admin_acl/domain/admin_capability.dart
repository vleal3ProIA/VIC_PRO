// ============================================================================
// Admin ACL · Whitelist de capacidades granulares (PR-Super-A1+A2)
// ----------------------------------------------------------------------------
// Mirror Dart de la whitelist definida en la migracion 0044
// (`admin_capabilities.capability CHECK`). Mantener sincronizado: si
// se anyade una capability en la migracion, se anyade aqui Y en el
// mapeo `kRouteToCapability` de `router_guards.dart`.
// ============================================================================

/// Constantes de las 13 capacidades validas. Usar estos identificadores
/// (NO strings literales) para evitar typos.
abstract class AdminCapability {
  AdminCapability._();

  static const String manageUsers       = 'manage_users';
  static const String managePlans       = 'manage_plans';
  static const String manageCoupons     = 'manage_coupons';
  static const String manageBranding    = 'manage_branding';
  static const String manageAppBranding = 'manage_app_branding';
  static const String manageBroadcasts  = 'manage_broadcasts';
  static const String manageChangelog   = 'manage_changelog';
  static const String manageFlags       = 'manage_flags';
  static const String manageIncidents   = 'manage_incidents';
  static const String viewEmailLog      = 'view_email_log';
  static const String viewMetrics       = 'view_metrics';
  static const String manageTrash       = 'manage_trash';
  static const String runAudits         = 'run_audits';
  static const String manageAi          = 'manage_ai';
  static const String viewAiContent     = 'view_ai_content';
  static const String viewErrorReports  = 'view_error_reports';

  /// Set inmutable con TODAS las capacidades. El super admin las
  /// tiene todas implicitamente. Util para tests y validacion.
  static const Set<String> all = {
    manageUsers,
    managePlans,
    manageCoupons,
    manageBranding,
    manageAppBranding,
    manageBroadcasts,
    manageChangelog,
    manageFlags,
    manageIncidents,
    viewEmailLog,
    viewMetrics,
    manageTrash,
    runAudits,
    manageAi,
    viewAiContent,
    viewErrorReports,
  };
}
