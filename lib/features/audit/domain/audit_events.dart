/// Constantes con los identificadores de eventos del audit log. Coinciden
/// con los valores que se guardan en `public.audit_logs.event`.
///
/// Convención de naming: `<namespace>.<verbo>[.<subtipo>]`, en snake_case
/// para los segmentos finales.
class AuditEvents {
  AuditEvents._();

  // ---- Login --------------------------------------------------------------
  static const String loginPassword = 'auth.login.password';
  static const String loginOauth = 'auth.login.oauth';
  static const String loginPasskey = 'auth.login.passkey';

  /// Recovery code usado correctamente. Implica que el MFA del usuario ha
  /// sido eliminado en el mismo evento → muy útil para la auditoría.
  static const String loginMfaRecovery = 'auth.login.mfa_recovery';

  static const String logout = 'auth.logout';

  // ---- Cuenta -------------------------------------------------------------
  static const String passwordChanged = 'account.password_changed';
  static const String emailChangeRequested = 'account.email_change_requested';

  // ---- MFA ----------------------------------------------------------------
  static const String mfaEnabled = 'mfa.enabled';
  static const String mfaDisabled = 'mfa.disabled';

  // ---- Passkeys -----------------------------------------------------------
  static const String passkeyAdded = 'passkey.added';
  static const String passkeyRemoved = 'passkey.removed';

  // ---- Uploads (PR-D) -----------------------------------------------------
  /// Upload confirmado tras validacion magic bytes + sha256. La metadata
  /// incluye: upload_id, filename, mime_type, size_bytes, sha256.
  static const String uploadCreated = 'upload.created';
  /// Soft-delete por accion del user. La metadata incluye upload_id +
  /// filename para auditoria.
  static const String uploadDeleted = 'upload.deleted';
  /// VirusTotal detecto malware -> el upload queda soft-deleted
  /// automaticamente. La metadata incluye stats + flagged_engines.
  static const String uploadVirusDetected = 'upload.virus_detected';
}
