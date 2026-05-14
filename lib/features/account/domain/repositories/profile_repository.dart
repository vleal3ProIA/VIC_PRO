import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';

import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/failures/profile_failure.dart';

abstract class ProfileRepository {
  /// Carga el perfil del usuario autenticado actual.
  Future<Either<ProfileFailure, Profile>> getMyProfile();

  /// Actualiza campos del perfil. Solo se envían los no-nulos.
  Future<Either<ProfileFailure, Profile>> updateMyProfile({
    String? displayName,
    String? locale,
    String? themeMode,
    String? avatarUrl,
  });

  /// Sube una imagen de avatar al Storage y guarda su URL en el perfil.
  /// Devuelve el perfil actualizado.
  Future<Either<ProfileFailure, Profile>> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  });
}
