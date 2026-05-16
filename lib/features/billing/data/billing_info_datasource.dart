import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/billing_info.dart';

/// Lee y escribe los campos de billing del propio `public.profiles` row.
/// RLS asegura que cada user solo toca su fila.
class BillingInfoDataSource {
  const BillingInfoDataSource(this._client);

  final SupabaseClient _client;

  /// Lee los campos de billing del profile actual. Devuelve
  /// [BillingInfo.empty] si no hay sesión.
  Future<BillingInfo> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return BillingInfo.empty;
    final data = await _client
        .from('profiles')
        .select(
          'first_name, last_name, date_of_birth, address_line1, '
          'address_line2, city, postal_code, country, tax_id, tax_id_type',
        )
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return BillingInfo.empty;
    return BillingInfo.fromProfileMap(data);
  }

  /// Actualiza solo los campos provistos en `patch`. Si pasas null en una
  /// clave, ese campo se borra (Postgres NULL).
  Future<void> updateMine(Map<String, dynamic> patch) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot update billing info: not authenticated');
    }
    if (patch.isEmpty) return;
    await _client.from('profiles').update(patch).eq('id', userId);
  }
}
