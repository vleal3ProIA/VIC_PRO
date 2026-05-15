import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/application/data_export_builder.dart';
import 'package:myapp/features/account/application/profile_providers.dart';
import 'package:myapp/features/account/presentation/util/web_download.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';

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

/// Genera y descarga una copia de los datos del usuario en JSON
/// (portabilidad GDPR — Art. 20).
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
      final user = ref.read(supabaseClientProvider).auth.currentUser;
      if (user == null) {
        state = state.copyWith(
          status: DataExportStatus.failure,
          errorMessage: 'No active session',
        );
        return;
      }

      // Asegura que perfil y factores MFA están cargados (si ya lo estaban,
      // estos `.future` resuelven inmediatamente con el valor cacheado).
      final profile = await ref.read(myProfileProvider.future);
      final factors = await ref.read(mfaFactorsProvider.future);

      final payload = buildDataExportPayload(
        user: user,
        profile: profile,
        mfaFactors: factors,
      );

      ref.read(dataDownloaderProvider)(
        filename: _buildFilename(),
        payload: payload,
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
