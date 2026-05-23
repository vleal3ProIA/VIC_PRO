// ============================================================================
// AI providers · Domain (Fase 0)
// ----------------------------------------------------------------------------
// Modelos del registro de proveedores de IA y sus credenciales. Espejo de las
// tablas `ai_providers` y `ai_credentials` (migración 0050). Las credenciales
// NUNCA traen la `api_key` -- solo `keyLast4` para preview enmascarada.
// ============================================================================

class AiProvider {
  const AiProvider({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.tier,
    required this.enabled,
    required this.priority,
    this.defaultModel,
    this.baseUrl,
  });

  factory AiProvider.fromMap(Map<String, dynamic> m) => AiProvider(
        id: m['id'] as String,
        slug: m['slug'] as String,
        displayName: (m['display_name'] as String?) ?? (m['slug'] as String),
        tier: (m['tier'] as String?) ?? 'free',
        enabled: (m['enabled'] as bool?) ?? false,
        priority: (m['priority'] as num?)?.toInt() ?? 100,
        defaultModel: m['default_model'] as String?,
        baseUrl: m['base_url'] as String?,
      );

  final String id;
  final String slug;
  final String displayName;
  final String tier; // 'free' | 'paid'
  final bool enabled;
  final int priority;
  final String? defaultModel;
  final String? baseUrl;

  bool get isFree => tier == 'free';
}

class AiCredential {
  const AiCredential({
    required this.id,
    required this.providerId,
    required this.enabled,
    this.label,
    this.keyLast4,
    this.disabledReason,
    this.cooldownUntil,
    this.lastUsedAt,
  });

  factory AiCredential.fromMap(Map<String, dynamic> m) => AiCredential(
        id: m['id'] as String,
        providerId: m['provider_id'] as String,
        enabled: (m['enabled'] as bool?) ?? true,
        label: m['label'] as String?,
        keyLast4: m['key_last4'] as String?,
        disabledReason: m['disabled_reason'] as String?,
        cooldownUntil: _parseTs(m['cooldown_until']),
        lastUsedAt: _parseTs(m['last_used_at']),
      );

  final String id;
  final String providerId;
  final bool enabled;
  final String? label;
  final String? keyLast4;
  final String? disabledReason;
  final DateTime? cooldownUntil;
  final DateTime? lastUsedAt;

  bool get onCooldown =>
      cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now());
}

DateTime? _parseTs(Object? v) => v is String ? DateTime.tryParse(v) : null;
