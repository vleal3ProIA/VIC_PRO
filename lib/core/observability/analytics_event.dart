/// Evento de analytics. Es un value object: el nombre canónico vive en
/// [AnalyticsEvents]; las propiedades son específicas del call-site.
///
/// **Convenciones de nombrado** (snake_case, verbo en pasado o sustantivo
/// claro):
///
/// - Acciones de usuario: `signup_started`, `login_succeeded`, `mfa_enabled`.
/// - Vistas: `page_viewed` con `{path: '/pricing'}`.
/// - Errores: `signup_failed` con `{reason: 'email_in_use'}`.
///
/// **Propiedades**: planas, valores serializables (`String`, `num`, `bool`,
/// `null`). Nada de mapas anidados.
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.properties = const {}]);

  final String name;
  final Map<String, Object?> properties;

  @override
  String toString() => 'AnalyticsEvent($name, $properties)';
}

/// Catálogo central de nombres de eventos.
///
/// **Toda métrica de producto pasa por aquí**: si añades una nueva,
/// añádela a este fichero. Esto evita typos (`'sing_up_done'` vs
/// `'signup_done'`), facilita búsquedas a futuro y obliga a discutir el
/// nombre antes de instrumentar.
class AnalyticsEvents {
  AnalyticsEvents._();

  // ─── Auth ────────────────────────────────────────────────────────────────

  static const signupStarted = 'signup_started';
  static const signupSucceeded = 'signup_succeeded';
  static const signupFailed = 'signup_failed';

  static const loginStarted = 'login_started';
  static const loginSucceeded = 'login_succeeded';
  static const loginFailed = 'login_failed';

  static const logout = 'logout';

  static const oauthStarted = 'oauth_started';
  static const oauthSucceeded = 'oauth_succeeded';
  static const oauthFailed = 'oauth_failed';

  static const magicLinkRequested = 'magic_link_requested';
  static const otpRequested = 'otp_requested';
  static const otpVerified = 'otp_verified';

  static const passwordResetRequested = 'password_reset_requested';
  static const passwordResetCompleted = 'password_reset_completed';
  static const passwordChanged = 'password_changed';

  // ─── MFA ────────────────────────────────────────────────────────────────

  static const mfaSetupStarted = 'mfa_setup_started';
  static const mfaEnabled = 'mfa_enabled';
  static const mfaDisabled = 'mfa_disabled';
  static const mfaChallenged = 'mfa_challenged';
  static const mfaChallengeFailed = 'mfa_challenge_failed';
  static const recoveryCodeUsed = 'recovery_code_used';

  // ─── Passkey ────────────────────────────────────────────────────────────

  static const passkeyAdded = 'passkey_added';
  static const passkeyRemoved = 'passkey_removed';
  static const passkeyLoginStarted = 'passkey_login_started';
  static const passkeyLoginSucceeded = 'passkey_login_succeeded';
  static const passkeyLoginFailed = 'passkey_login_failed';

  // ─── Account ────────────────────────────────────────────────────────────

  static const profileUpdated = 'profile_updated';
  static const emailChangeRequested = 'email_change_requested';
  static const accountDeleted = 'account_deleted';
  static const dataExported = 'data_exported';

  // ─── UI navegación ──────────────────────────────────────────────────────

  static const pageViewed = 'page_viewed';

  // ─── Consentimiento ─────────────────────────────────────────────────────

  static const cookieConsentAccepted = 'cookie_consent_accepted';
  static const cookieConsentRejected = 'cookie_consent_rejected';
  static const cookieConsentCustomized = 'cookie_consent_customized';
}
