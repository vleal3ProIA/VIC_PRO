import 'package:meta/meta.dart';

/// Categoría de una entrada del changelog. Determina el color del chip
/// e icono en la lista.
enum ChangelogCategory { feature, improvement, fix, security }

ChangelogCategory _parseCategory(String? s) {
  switch (s) {
    case 'improvement':
      return ChangelogCategory.improvement;
    case 'fix':
      return ChangelogCategory.fix;
    case 'security':
      return ChangelogCategory.security;
    default:
      return ChangelogCategory.feature;
  }
}

/// Entrada del changelog público (sección "What's new"). Admin las
/// crea desde `/admin/changelog`; users normales solo las ven cuando
/// están publicadas (`publishedAt != null`).
@immutable
class ChangelogEntry {
  const ChangelogEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.version,
    this.publishedAt,
  });

  factory ChangelogEntry.fromMap(Map<String, dynamic> m) {
    return ChangelogEntry(
      id: m['id'] as String,
      version: m['version'] as String?,
      title: m['title'] as String,
      body: m['body'] as String,
      category: _parseCategory(m['category'] as String?),
      publishedAt: m['published_at'] != null
          ? DateTime.parse(m['published_at'] as String)
          : null,
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  final String id;
  final String? version;
  final String title;
  final String body;
  final ChangelogCategory category;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isPublished => publishedAt != null;
  bool get isDraft => publishedAt == null;

  /// Devuelve el string de categoría usado en BD (para serializar).
  String get categoryDbValue {
    switch (category) {
      case ChangelogCategory.feature:
        return 'feature';
      case ChangelogCategory.improvement:
        return 'improvement';
      case ChangelogCategory.fix:
        return 'fix';
      case ChangelogCategory.security:
        return 'security';
    }
  }
}
