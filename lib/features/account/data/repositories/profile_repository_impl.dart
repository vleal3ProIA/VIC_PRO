import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:myapp/core/utils/app_logger.dart';
import 'package:myapp/features/account/data/datasources/profile_supabase_datasource.dart';
import 'package:myapp/features/account/domain/entities/profile.dart';
import 'package:myapp/features/account/domain/failures/profile_failure.dart';
import 'package:myapp/features/account/domain/repositories/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl({required ProfileSupabaseDataSource dataSource})
      : _dataSource = dataSource;

  final ProfileSupabaseDataSource _dataSource;

  @override
  Future<Either<ProfileFailure, Profile>> getMyProfile() async {
    try {
      final map = await _dataSource.fetchMyProfile();
      return Right(Profile.fromMap(map));
    } on AuthException catch (e) {
      AppLogger.w('getMyProfile auth: ${e.message}');
      return Left(ProfileNotFound(cause: e));
    } on PostgrestException catch (e) {
      return Left(_mapPostgrest(e));
    } catch (e, st) {
      AppLogger.e('getMyProfile unknown', error: e, stackTrace: st);
      return Left(ProfileUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<ProfileFailure, Profile>> updateMyProfile({
    String? displayName,
    String? username,
    String? locale,
    String? themeMode,
    String? avatarUrl,
  }) async {
    try {
      final map = await _dataSource.updateMyProfile(
        displayName: displayName,
        username: username,
        locale: locale,
        themeMode: themeMode,
        avatarUrl: avatarUrl,
      );
      return Right(Profile.fromMap(map));
    } on AuthException catch (e) {
      return Left(ProfileNotFound(cause: e));
    } on PostgrestException catch (e) {
      return Left(_mapPostgrest(e));
    } catch (e, st) {
      AppLogger.e('updateMyProfile unknown', error: e, stackTrace: st);
      return Left(ProfileUnknown(cause: e, message: e.toString()));
    }
  }

  @override
  Future<Either<ProfileFailure, Profile>> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    try {
      final url = await _dataSource.uploadAvatar(
        bytes: bytes,
        contentType: contentType,
      );
      // Persistir la URL en el perfil y devolver la fila actualizada.
      final map = await _dataSource.updateMyProfile(avatarUrl: url);
      return Right(Profile.fromMap(map));
    } on AuthException catch (e) {
      return Left(ProfileNotFound(cause: e));
    } on StorageException catch (e) {
      AppLogger.w('uploadAvatar storage: ${e.statusCode} ${e.message}');
      return Left(ProfileUnknown(cause: e, message: e.message));
    } on PostgrestException catch (e) {
      return Left(_mapPostgrest(e));
    } catch (e, st) {
      AppLogger.e('uploadAvatar unknown', error: e, stackTrace: st);
      return Left(ProfileUnknown(cause: e, message: e.toString()));
    }
  }

  ProfileFailure _mapPostgrest(PostgrestException e) {
    AppLogger.w('profile postgrest: ${e.code} ${e.message}');
    // 23505 = unique_violation (username duplicado).
    if (e.code == '23505') {
      return ProfileUsernameTaken(cause: e);
    }
    // PGRST116 = no rows (single() sin resultados).
    if (e.code == 'PGRST116') {
      return ProfileNotFound(cause: e);
    }
    return ProfileUnknown(cause: e, message: e.message);
  }
}
