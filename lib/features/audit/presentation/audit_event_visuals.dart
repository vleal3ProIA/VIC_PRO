import 'package:flutter/material.dart';
import 'package:myapp/features/audit/domain/audit_events.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// Helpers visuales para los eventos de `audit_logs`. Centraliza la
/// asignación icono/etiqueta para que TANTO la pantalla técnica
/// `/audit-log` COMO el nuevo timeline `/activity` usen los mismos
/// valores.

/// Categorías de eventos — useful para filtros y para colorear iconos
/// por grupo.
enum AuditEventCategory { auth, account, mfa, passkey, other }

AuditEventCategory categoryFor(String event) {
  if (event.startsWith('auth.')) return AuditEventCategory.auth;
  if (event.startsWith('mfa.')) return AuditEventCategory.mfa;
  if (event.startsWith('passkey.')) return AuditEventCategory.passkey;
  if (event.startsWith('account.')) return AuditEventCategory.account;
  return AuditEventCategory.other;
}

IconData iconForAuditEvent(String event) {
  if (event.startsWith('auth.login')) return Icons.login;
  if (event == AuditEvents.logout) return Icons.logout;
  if (event.startsWith('mfa.')) return Icons.shield_outlined;
  if (event.startsWith('passkey.')) return Icons.fingerprint;
  if (event == AuditEvents.passwordChanged) return Icons.password_outlined;
  if (event == AuditEvents.emailChangeRequested) return Icons.alternate_email;
  return Icons.history;
}

/// Texto humano localizado para un evento. Fallback al string crudo si
/// el evento no está mapeado (caso de eventos nuevos sin traducir aún).
String labelForAuditEvent(AppLocalizations l, String event) {
  return switch (event) {
    AuditEvents.loginPassword => l.auditEventLoginPassword,
    AuditEvents.loginOauth => l.auditEventLoginOauth,
    AuditEvents.loginPasskey => l.auditEventLoginPasskey,
    AuditEvents.loginMfaRecovery => l.auditEventLoginMfaRecovery,
    AuditEvents.logout => l.auditEventLogout,
    AuditEvents.passwordChanged => l.auditEventPasswordChanged,
    AuditEvents.emailChangeRequested => l.auditEventEmailChangeRequested,
    AuditEvents.mfaEnabled => l.auditEventMfaEnabled,
    AuditEvents.mfaDisabled => l.auditEventMfaDisabled,
    AuditEvents.passkeyAdded => l.auditEventPasskeyAdded,
    AuditEvents.passkeyRemoved => l.auditEventPasskeyRemoved,
    _ => event,
  };
}

/// Color del icono según categoría — coherente entre /audit-log y
/// /activity. Sigue la paleta del theme: primary, error, tertiary.
Color colorForCategory(ColorScheme scheme, AuditEventCategory cat) {
  switch (cat) {
    case AuditEventCategory.auth:
      return scheme.primary;
    case AuditEventCategory.mfa:
    case AuditEventCategory.passkey:
      return scheme.tertiary;
    case AuditEventCategory.account:
      return scheme.secondary;
    case AuditEventCategory.other:
      return scheme.onSurfaceVariant;
  }
}

/// Etiqueta humana corta de la categoría (para filtros).
String labelForCategory(AppLocalizations l, AuditEventCategory cat) {
  switch (cat) {
    case AuditEventCategory.auth:
      return l.activityCategoryAuth;
    case AuditEventCategory.account:
      return l.activityCategoryAccount;
    case AuditEventCategory.mfa:
      return l.activityCategoryMfa;
    case AuditEventCategory.passkey:
      return l.activityCategoryPasskey;
    case AuditEventCategory.other:
      return l.activityCategoryOther;
  }
}
