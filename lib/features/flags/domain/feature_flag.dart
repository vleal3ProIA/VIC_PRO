import 'package:meta/meta.dart';

/// Origen del veredicto de un flag — útil para debugging / observabilidad.
/// El orden refleja la precedencia (user override > tenant > rollout > global).
enum FeatureFlagSource {
  user,
  tenant,
  rollout,
  global;

  static FeatureFlagSource fromString(String value) {
    return switch (value) {
      'user' => FeatureFlagSource.user,
      'tenant' => FeatureFlagSource.tenant,
      'rollout' => FeatureFlagSource.rollout,
      _ => FeatureFlagSource.global,
    };
  }
}

/// Estado efectivo de un flag para el usuario actual + tenant actual.
/// Resuelto por la RPC `my_feature_flags(p_tenant_id)`. Inmutable.
@immutable
class FeatureFlag {
  const FeatureFlag({
    required this.key,
    required this.enabled,
    required this.source,
    this.value,
  });

  factory FeatureFlag.fromMap(Map<String, dynamic> map) {
    return FeatureFlag(
      key: map['key'] as String,
      enabled: (map['enabled'] as bool?) ?? false,
      source: FeatureFlagSource.fromString(map['source'] as String),
      value: map['value'] as Map<String, dynamic>?,
    );
  }

  final String key;
  final bool enabled;
  final Map<String, dynamic>? value;
  final FeatureFlagSource source;

  /// Atajo para flags de configuración: lee un sub-campo del `value` con
  /// fallback al `defaultValue`.
  T config<T>(String field, T defaultValue) {
    final v = value?[field];
    if (v is T) return v;
    return defaultValue;
  }

  @override
  String toString() => 'FeatureFlag($key, ${enabled ? "on" : "off"}, $source)';

  @override
  bool operator ==(Object other) =>
      other is FeatureFlag && other.key == key && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(key, enabled);
}

/// Versión "admin" — incluye la definición global del flag, no solo el
/// estado resuelto para el caller. Se usa en la pantalla `/admin/flags`.
@immutable
class FeatureFlagDefinition {
  const FeatureFlagDefinition({
    required this.key,
    required this.enabled,
    required this.rolloutPercentage,
    required this.updatedAt,
    this.description,
    this.value,
  });

  factory FeatureFlagDefinition.fromMap(Map<String, dynamic> map) {
    return FeatureFlagDefinition(
      key: map['key'] as String,
      description: map['description'] as String?,
      enabled: (map['enabled'] as bool?) ?? false,
      rolloutPercentage: (map['rollout_percentage'] as int?) ?? 0,
      value: map['value'] as Map<String, dynamic>?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String key;
  final String? description;
  final bool enabled;
  final int rolloutPercentage;
  final Map<String, dynamic>? value;
  final DateTime updatedAt;
}
