import 'package:meta/meta.dart';

/// Wrapper inmutable sobre `Map<String, dynamic>` con accesos tipados a las
/// claves canónicas de entitlements. Lo devuelve la RPC
/// `tenant_entitlements(tenant_id)`.
///
/// Convención: valor `-1` en una cuota significa "ilimitado".
@immutable
class Entitlements {
  const Entitlements(this.raw);

  /// Versión vacía — sin ninguna capacidad. Se usa como fallback cuando
  /// no hay suscripción activa.
  const Entitlements.empty() : raw = const {};

  final Map<String, dynamic> raw;

  /// Lee una cuota entera. Devuelve [fallback] si la clave no existe o el
  /// valor no es numérico. `-1` se preserva tal cual (la UI lo trata como
  /// "ilimitado").
  int quota(String key, {int fallback = 0}) {
    final v = raw[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  /// Lee una capability booleana.
  bool capability(String key, {bool fallback = false}) {
    final v = raw[key];
    return v is bool ? v : fallback;
  }

  /// Lee un enum string (p.ej. "support" → "community"|"email"|"priority"|"dedicated").
  String? choice(String key) {
    final v = raw[key];
    return v is String ? v : null;
  }

  /// True si `current` cubre la cuota del [key]. Maneja `-1` como ilimitado.
  /// Ejemplo: `entitlements.allows('max_members', current: 4)` → false si
  /// max_members=3 (ya has alcanzado el tope).
  bool allows(String key, {required int current, int fallback = 0}) {
    final max = quota(key, fallback: fallback);
    if (max < 0) return true; // ilimitado
    return current < max;
  }

  /// True cuando el tenant ha llegado o sobrepasado la cuota.
  bool atOrOverLimit(String key, {required int current, int fallback = 0}) =>
      !allows(key, current: current, fallback: fallback);
}
