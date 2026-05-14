/// Rol del usuario dentro de la app.
///
/// - [admin] / [user]: roles persistidos en `profiles.role`.
/// - [guest]: estado derivado — no hay sesión activa. Nunca se guarda en BD.
enum UserRole {
  admin,
  user,
  guest;

  /// Mapea el valor de `profiles.role`. Cualquier valor desconocido o nulo
  /// cae a [user] (el menos privilegiado de los roles autenticados).
  static UserRole fromString(String? value) => switch (value) {
        'admin' => UserRole.admin,
        'guest' => UserRole.guest,
        _ => UserRole.user,
      };

  /// Valor para persistir en BD. `guest` no es válido en BD; se trata como
  /// `user` por seguridad (nunca debería llegar a guardarse).
  String get dbValue => this == UserRole.admin ? 'admin' : 'user';

  bool get isAdmin => this == UserRole.admin;
  bool get isAuthenticated => this != UserRole.guest;
}
