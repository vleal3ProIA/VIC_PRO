import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/presentation/util/data_export_pdf_builder.dart';
import 'package:myapp/features/account/presentation/util/web_download.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

/// Función que dispara la descarga del ZIP final. Está detrás de un
/// provider para poder inyectar un fake en los tests sin tocar el DOM.
///
/// Acepta bytes ya construidos (no un payload genérico): el notifier es
/// quien sabe cómo armar el JSON + PDF + ZIP, esta función solo lo entrega
/// al navegador.
typedef DataDownloader = void Function({
  required String filename,
  required Uint8List bytes,
});

final dataDownloaderProvider = Provider<DataDownloader>((ref) {
  return downloadZipFile;
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

/// Genera y descarga una copia de los datos del usuario en un **ZIP** que
/// contiene `mis-datos.json` (machine-readable) + `mis-datos.pdf`
/// (human-readable, localizado).
///
/// **Compliance**: GDPR Article 15 (Right of Access) + Article 20 (Data
/// Portability), equivalentes (CCPA, LGPD).
///
/// **v2**: la RPC `get_my_data_export` (migración 0072) ya devuelve el
/// payload limpio — sin UUIDs internos del sistema, con `login_summary`
/// agregando ruido y nombres más amigables (kind, uploaded_at). El PDF se
/// construye client-side a partir de ese mismo Map (sin duplicar lógica).
class DataExportNotifier extends Notifier<DataExportState> {
  @override
  DataExportState build() => const DataExportState();

  /// El [context] es necesario para leer las cadenas localizadas que van
  /// al PDF — los notifiers no tienen acceso a `AppLocalizations`. Se
  /// extraen ANTES del primer await para no usar el context tras un gap
  /// async (linter "use_build_context_synchronously").
  Future<void> exportAndDownload(BuildContext context) async {
    if (state.isBuilding) return;

    // 1. Leer labels localizadas y locale del UI ANTES de await.
    final l10n = AppLocalizations.of(context);
    final uiLocale = Localizations.localeOf(context).languageCode;
    final labels = _buildLabels(l10n);

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

      // 2. RPC v2 — JSON ya sin UUIDs, con login_summary, etc.
      final raw = await client.rpc<dynamic>('get_my_data_export');
      if (raw is! Map) {
        state = state.copyWith(
          status: DataExportStatus.failure,
          errorMessage: 'unexpected_response_shape',
        );
        return;
      }
      final data = raw.cast<String, dynamic>();

      // 3. Preferimos el locale del usuario almacenado en su perfil, no el
      //    de la UI — si el user cambió de idioma este export ahora pero
      //    su preferencia base es otra, respetamos su preferencia para el
      //    contenido del PDF (más consistente con sus correos y otros
      //    artefactos generados a partir del perfil).
      final profile = data['profile'];
      final profileLocale = profile is Map
          ? (profile['locale'] as String?)
          : null;
      final locale = profileLocale ?? uiLocale;

      // 4. Construir PDF.
      final pdfBytes = await buildDataExportPdf(
        data: data,
        locale: locale,
        labels: labels,
      );

      // 5. JSON pretty-printed.
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final jsonBytes = Uint8List.fromList(utf8.encode(jsonString));

      // 6. Empaquetar en ZIP (in-memory).
      final archive = Archive()
        ..addFile(ArchiveFile('mis-datos.json', jsonBytes.length, jsonBytes))
        ..addFile(ArchiveFile('mis-datos.pdf', pdfBytes.length, pdfBytes));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      // 7. Trigger descarga.
      ref.read(dataDownloaderProvider)(
        filename: _buildFilename(),
        bytes: zipBytes,
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

  /// Convierte `AppLocalizations` (i18n generada) en un bag plano de
  /// strings para el builder. Mantenemos el builder libre de
  /// `BuildContext` así puede ser un módulo puro Dart testeable sin
  /// MaterialApp wrapper.
  PdfExportLabels _buildLabels(AppLocalizations l) {
    return PdfExportLabels(
      title: l.dataExportPdfTitle,
      subtitle: l.dataExportPdfSubtitle('{date}'),
      notice: l.dataExportPdfNotice,
      sectionAccount: l.dataExportPdfSectionAccount,
      sectionProfile: l.dataExportPdfSectionProfile,
      sectionTenants: l.dataExportPdfSectionTenants,
      sectionUploads: l.dataExportPdfSectionUploads,
      sectionLogins: l.dataExportPdfSectionLogins,
      sectionEvents: l.dataExportPdfSectionEvents,
      sectionEmails: l.dataExportPdfSectionEmails,
      sectionTokens: l.dataExportPdfSectionTokens,
      sectionWebhooks: l.dataExportPdfSectionWebhooks,
      sectionNotifs: l.dataExportPdfSectionNotifs,
      labelEmail: l.dataExportPdfLabelEmail,
      labelCreated: l.dataExportPdfLabelCreated,
      labelLastLogin: l.dataExportPdfLabelLastLogin,
      labelVerified: l.dataExportPdfLabelVerified,
      labelDisplayName: l.dataExportPdfLabelDisplayName,
      labelUsername: l.dataExportPdfLabelUsername,
      labelLocale: l.dataExportPdfLabelLocale,
      labelTheme: l.dataExportPdfLabelTheme,
      labelName: l.dataExportPdfLabelName,
      labelKind: l.dataExportPdfLabelKind,
      labelSize: l.dataExportPdfLabelSize,
      labelDate: l.dataExportPdfLabelDate,
      labelDeleted: l.dataExportPdfLabelDeleted,
      labelRole: l.dataExportPdfLabelRole,
      labelJoinedAt: l.dataExportPdfLabelJoinedAt,
      loginsSummaryBuilder: l.dataExportPdfLabelLoginsSummary,
      yes: l.dataExportPdfYes,
      no: l.dataExportPdfNo,
      themeDark: l.dataExportPdfThemeDark,
      themeLight: l.dataExportPdfThemeLight,
      themeSystem: l.dataExportPdfThemeSystem,
    );
  }

  String _buildFilename() {
    // `myapp-datos-2026-05-28.zip` — fecha solo, sin timestamp full ni
    // UUIDs en el nombre.
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return 'myapp-datos-$y-$m-$d.zip';
  }
}

final dataExportNotifierProvider =
    NotifierProvider<DataExportNotifier, DataExportState>(
  DataExportNotifier.new,
);
