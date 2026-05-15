import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/legal/domain/cookie_consent.dart';

/// Gestiona el consentimiento de cookies: lo carga al arrancar desde
/// SharedPreferences y lo persiste cuando el usuario toma una decisión.
class CookieConsentNotifier extends Notifier<CookieConsent> {
  static const _key = 'cookie_consent_v1';

  @override
  CookieConsent build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const CookieConsent();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CookieConsent.fromJson(json) ?? const CookieConsent();
    } catch (_) {
      return const CookieConsent();
    }
  }

  /// "Aceptar todo" → essential (siempre) + analytics opcional ON.
  Future<void> acceptAll() async {
    await _save(
      const CookieConsent(analytics: true).copyWith(
        decidedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// "Rechazar opcionales" → solo essential, analytics OFF. Es el mínimo
  /// que NO se le puede negar a la app (sesión, idioma, tema…).
  Future<void> rejectOptional() async {
    await _save(
      const CookieConsent().copyWith(
        decidedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// El usuario personaliza desde la página /cookies.
  Future<void> setAnalytics({required bool value}) async {
    await _save(
      state.copyWith(
        analytics: value,
        decidedAt: state.decidedAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _save(CookieConsent consent) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, jsonEncode(consent.toJson()));
    state = consent;
  }
}

final cookieConsentNotifierProvider =
    NotifierProvider<CookieConsentNotifier, CookieConsent>(
  CookieConsentNotifier.new,
);
