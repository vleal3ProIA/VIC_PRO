// ============================================================================
// Leaked password protection (HaveIBeenPwned · k-anonimato)
// ----------------------------------------------------------------------------
// Equivalente GRATIS a la opción "Prevent use of leaked passwords" de
// Supabase (que es Pro-only). Rechaza contraseñas que aparecen en
// brechas de datos conocidas, usando la API pública Pwned Passwords de
// HaveIBeenPwned con el modelo de **k-anonimato**:
//
//   1. Calculamos SHA-1(password) en hex mayúsculas (40 chars).
//   2. Enviamos SOLO los 5 primeros caracteres del hash (el "prefix").
//   3. HIBP devuelve TODOS los sufijos (35 chars) que comparten ese
//      prefix + cuántas veces aparece cada uno en brechas.
//   4. Buscamos NUESTRO sufijo en esa lista localmente.
//
// Así HIBP NUNCA ve la contraseña ni el hash completo: solo un prefijo
// de 5 hex compartido por ~miles de contraseñas distintas. Privacidad
// matemáticamente garantizada (k-anonimato).
//
// **GET simple, sin headers custom**: en Flutter Web un header custom
// (p.ej. `Add-Padding`) dispararía un preflight CORS que HIBP podría
// no permitir. Un GET sin headers extra es una "simple request" sin
// preflight → funciona cross-origin sin problemas.
//
// **FAIL-OPEN**: si HIBP no responde (red caída, timeout, 5xx, CORS),
// devolvemos 0 (no filtrada). NUNCA bloqueamos a un usuario legítimo
// por una caída de un tercero — la protección es best-effort.
//
// **Defensa en profundidad**: esto es client-side (UX). El control
// duro server-side equivalente sería el toggle Pro de Supabase. Como
// no lo tenemos, esta capa eleva el listón sin coste; un atacante que
// llame la API de Supabase directamente se la salta, pero la política
// de longitud + clases de caracteres server-side (Supabase Auth
// settings) sigue aplicando.
// ============================================================================

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class LeakedPasswordChecker {
  const LeakedPasswordChecker(this._client);

  final http.Client _client;

  static const String _endpoint = 'https://api.pwnedpasswords.com/range/';
  static const Duration _timeout = Duration(seconds: 5);

  /// Número de veces que la contraseña aparece en brechas conocidas.
  /// `0` = no aparece, o no se pudo comprobar (fail-open).
  Future<int> pwnedCount(String password) async {
    if (password.isEmpty) return 0;
    try {
      final digest =
          sha1.convert(utf8.encode(password)).toString().toUpperCase();
      final prefix = digest.substring(0, 5);
      final suffix = digest.substring(5);

      final resp = await _client
          .get(Uri.parse('$_endpoint$prefix'))
          .timeout(_timeout);
      if (resp.statusCode != 200) return 0;

      for (final line in const LineSplitter().convert(resp.body)) {
        final idx = line.indexOf(':');
        if (idx <= 0) continue;
        if (line.substring(0, idx).toUpperCase() == suffix) {
          return int.tryParse(line.substring(idx + 1).trim()) ?? 0;
        }
      }
      return 0;
    } catch (_) {
      // Red caída / timeout / parse error → fail-open.
      return 0;
    }
  }

  /// `true` si la contraseña aparece en al menos una brecha conocida.
  Future<bool> isLeaked(String password) async =>
      (await pwnedCount(password)) > 0;
}

/// Provider del checker. Override-able en tests con un `http.Client`
/// mockeado (ver `test/core/security/leaked_password_checker_test.dart`).
final leakedPasswordCheckerProvider = Provider<LeakedPasswordChecker>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return LeakedPasswordChecker(client);
});
