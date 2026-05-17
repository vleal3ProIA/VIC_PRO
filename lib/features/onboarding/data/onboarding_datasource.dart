import 'package:supabase_flutter/supabase_flutter.dart';

/// Lee y muta el estado de onboarding del usuario actual.
/// La columna vive en `public.profiles.onboarding_completed_at`.
class OnboardingDataSource {
  const OnboardingDataSource(this._client);

  final SupabaseClient _client;

  /// Devuelve `true` si el user ya completó (o saltó) el onboarding.
  /// `false` si la columna está NULL.
  Future<bool> isCompleted() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final row = await _client
        .from('profiles')
        .select('onboarding_completed_at')
        .eq('id', user.id)
        .maybeSingle();
    return row?['onboarding_completed_at'] != null;
  }

  /// Marca el onboarding como completado. Idempotente: si ya estaba
  /// marcado, no toca el timestamp. Devuelve el timestamp resultante.
  Future<DateTime?> markCompleted() async {
    final result = await _client.rpc<dynamic>('mark_onboarding_completed');
    if (result is String) return DateTime.tryParse(result);
    return null;
  }
}
