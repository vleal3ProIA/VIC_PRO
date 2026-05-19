import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/presentation/util/web_download.dart';

/// Función que dispara la descarga del archivo. Está detrás de un provider
/// para poder inyectar un fake en los tests.
typedef DataDownloader = void Function({
  required String filename,
  required Object payload,
});

final dataDownloaderProvider = Provider<DataDownloader>((ref) {
  return downloadJsonFile;
});

enum DataExportStatus { idle, building, success, failure }

class DataExportState {
  const DataExportState({
    this.status = DataExportStatus.idle,
    this.errorMessage,
  });

  final DataExportStatus status;
  final String? errorMessage;

  bool get isBuilding => status == DataExportStatus.building;

  DataExportState copyWith({
    DataExportStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DataExportState(
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Genera y descarga una copia de los datos del usuario en JSON.
///
/// **Compliance**: cubre **GDPR Article 15 (Right of Access)** y
/// **Article 20 (Data Portability)**, asi como equivalentes (CCPA,
/// LGPD).
///
/// **Antes (v1)**: el payload se construia client-side a partir de
/// `User`, `Profile` y `mfaFactors`. Cobertura limitada: solo cuenta +
/// perfil + factores MFA. Falto: uploads, audit_logs, tenants,
/// notificaciones, emails recibidos, PATs, webhooks.
///
/// **Ahora (v2)**: llama la RPC SQL `get_my_data_export()` (migracion
/// 0043) que recopila TODO en server-side y devuelve un JSONB. La RPC
/// es `SECURITY DEFINER` con `auth.uid()`, asi que aunque bypassa RLS
/// solo expone los datos del propio caller. Strippea secretos
/// (token_hash, secret_hash) y info tecnica (Storage paths).
///
/// **Limit**: `audit_logs` y `email_log` se truncan a las 1000 entradas
/// mas recientes server-side para evitar exports gigantes que rompan
/// el browser. Para historial completo, contact support.
class DataExportNotifier extends Notifier<DataExportState> {
  @override
  DataExportState build() => const DataExportState();

  Future<void> exportAndDownload() async {
    if (state.isBuilding) return;
    state = state.copyWith(
      status: DataExportStatus.building,
      clearError: true,
    );

    try {
      final client = ref.read(supabaseClientProvider);
      final user = client.auth.currentUser;
      if (user == null) {
        state = state.copyWith(
          status: DataExportStatus.failure,
          errorMessage: 'No active session',
        );
        return;
      }

      // La RPC devuelve un JSONB con TODO. Es un Map<String, dynamic>
      // anidado: cada seccion (account, profile, uploads, ...) es una
      // sub-key. La RPC valida `auth.uid()` internamente y lanza
      // `not_authenticated` si el JWT esta vacio (no deberia pasar
      // tras el currentUser != null pero defense in depth).
      final data = await client.rpc<dynamic>('get_my_data_export');
      if (data is! Map) {
        state = state.copyWith(
          status: DataExportStatus.failure,
          errorMessage: 'unexpected_response_shape',
        );
        return;
      }

      ref.read(dataDownloaderProvider)(
        filename: _buildFilename(),
        payload: data.cast<String, dynamic>(),
      );

      state = state.copyWith(status: DataExportStatus.success);
    } catch (e) {
      state = state.copyWith(
        status: DataExportStatus.failure,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const DataExportState();

  String _buildFilename() {
    // `myapp-data-2026-05-15T18-30-12.json`
    final stamp = DateTime.now()
        .toIso8601String()
        .split('.')
        .first
        .replaceAll(':', '-');
    return 'myapp-data-$stamp.json';
  }
}

final dataExportNotifierProvider =
    NotifierProvider<DataExportNotifier, DataExportState>(
  DataExportNotifier.new,
);
