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
  });
}
