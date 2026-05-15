import 'package:meta/meta.dart';

/// Tenant = workspace lógico. Un usuario puede pertenecer a varios.
///
/// El campo `isPersonal` marca el tenant auto-creado en el signup: no se
/// puede borrar y sirve como fallback si el usuario sale de todos los demás.
@immutable
class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    required this.slug,
    required this.ownerId,
    required this.isPersonal,
    required this.createdAt,
  });

  factory Tenant.fromMap(Map<String, dynamic> map) {
    return Tenant(
      id: map['id'] as String,
      name: map['name'] as String,
      slug: map['slug'] as String,
      ownerId: map['owner_id'] as String,
      isPersonal: map['is_personal'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String name;
  final String slug;
  final String ownerId;
  final bool isPersonal;
  final DateTime createdAt;

  Tenant copyWith({String? name}) => Tenant(
        id: id,
        name: name ?? this.name,
        slug: slug,
        ownerId: ownerId,
        isPersonal: isPersonal,
        createdAt: createdAt,
      );

  @override
  String toString() => 'Tenant($slug, $name${isPersonal ? ', personal' : ''})';

  @override
  bool operator ==(Object other) => other is Tenant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
