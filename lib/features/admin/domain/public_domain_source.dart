// ============================================================================
// admin · domain · PublicDomainSource
// ----------------------------------------------------------------------------
// Espejo de la tabla `public.public_domain_sources` (migracion 0079). Un
// "source" es un PATTERN que, si aparece en el `source_url` (o file_name o
// extension/mime) de un documento, hace que el subject sea considerado de
// dominio publico — y por tanto el super-admin puede descargar el archivo
// original. La whitelist es editable solo por super-admin.
// ============================================================================

import 'package:flutter/foundation.dart';

/// Tipo de matching del pattern.
///
/// - [domain]: busca el pattern dentro de `documents.source_url` (la URL que
///   el usuario pego al subir). Caso tipico: `boe.es`, `wikipedia.org`.
/// - [filename]: busca el pattern dentro de `documents.file_name`. Caso de
///   uso menos comun (ej. ficheros con un naming convention publico).
/// - [extension]: el pattern es una extension (`pdf`, `txt`) o un mime
///   parcial. Util para tipos universalmente libres (poco usado en la
///   practica; reservado).
enum PublicDomainMatchType { domain, filename, extension }

PublicDomainMatchType matchTypeFrom(String? s) {
  switch (s) {
    case 'filename':
      return PublicDomainMatchType.filename;
    case 'extension':
      return PublicDomainMatchType.extension;
    case 'domain':
    default:
      return PublicDomainMatchType.domain;
  }
}

String matchTypeToWire(PublicDomainMatchType t) {
  switch (t) {
    case PublicDomainMatchType.filename:
      return 'filename';
    case PublicDomainMatchType.extension:
      return 'extension';
    case PublicDomainMatchType.domain:
      return 'domain';
  }
}

@immutable
class PublicDomainSource {
  const PublicDomainSource({
    required this.id,
    required this.pattern,
    required this.label,
    required this.matchType,
    required this.enabled,
    this.notes,
    this.createdAt,
    this.createdBy,
  });

  factory PublicDomainSource.fromMap(Map<String, dynamic> m) =>
      PublicDomainSource(
        id: m['id'] as String,
        pattern: (m['pattern'] as String?) ?? '',
        label: (m['label'] as String?) ?? '',
        matchType: matchTypeFrom(m['match_type'] as String?),
        enabled: (m['enabled'] as bool?) ?? true,
        notes: m['notes'] as String?,
        createdAt: m['created_at'] is String
            ? DateTime.tryParse(m['created_at'] as String)
            : null,
        createdBy: m['created_by'] as String?,
      );

  final String id;
  final String pattern;
  final String label;
  final PublicDomainMatchType matchType;
  final bool enabled;
  final String? notes;
  final DateTime? createdAt;
  final String? createdBy;
}
