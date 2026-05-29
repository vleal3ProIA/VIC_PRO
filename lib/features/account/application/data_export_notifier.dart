import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/features/account/presentation/util/data_export_csv_builder.dart';
import 'package:myapp/features/account/presentation/util/data_export_html_builder.dart';
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

/// Genera y descarga una copia de los datos del usuario en un **ZIP**
/// estilo Google Takeout — multi-formato por tipo de dato.
///
/// **Contenido del ZIP** (filenames localizados al idioma del usuario;
/// `es` ⇒ español, cualquier otro idioma ⇒ inglés):
///
///   * `LEEME.html` / `README.html` — README autocontenido (HTML+CSS
///     inline) que explica qué hay en cada fichero.
///   * `mis-datos.pdf` / `my-data.pdf` — Resumen legible para humanos
///     (PDF generado client-side desde el JSON, sin dependencias de
///     red).
///   * `mis-datos.json` — Payload estructurado tal cual lo devuelve la
///     RPC, para portabilidad RGPD art. 20.
///   * `archivos.csv` / `files.csv` — Lista de uploads, formato CSV
///     UTF-8+BOM compatible con Excel/Sheets directamente.
///   * `actividad.csv` / `activity.csv` — Login summary + otros eventos.
///   * `correos.csv` / `emails.csv` — Email log.
///
/// **Compliance**: GDPR Article 15 (Right of Access — el PDF y HTML) +
/// Article 20 (Data Portability — JSON y CSVs), equivalentes (CCPA,
/// LGPD).
///
/// **v3** (RPC): la RPC `get_my_data_export` (migración 0073) devuelve
/// el payload limpio — sin UUIDs internos del sistema, con
/// `login_summary` agregando ruido y nombres más amigables (kind,
/// uploaded_at). Los builders trabajan sobre ese mismo Map.
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

      // 4. Construir PDF (resumen humano-legible, art. 15).
      final pdfBytes = await buildDataExportPdf(
        data: data,
        locale: locale,
        labels: labels,
      );

      // 5. JSON pretty-printed (portabilidad, art. 20).
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final jsonBytes = Uint8List.fromList(utf8.encode(jsonString));

      // 6. CSVs por tipo de dato (Excel/Sheets friendly). Si una sección
      //    no tiene entradas el builder devuelve un CSV con solo la
      //    fila de cabecera — preferimos un fichero vacío explícito a
      //    un fichero ausente (señal clara para el usuario).
      final uploadsCsv = buildUploadsCsv(data, labels);
      final activityCsv = buildActivityCsv(data, labels);
      final emailsCsv = buildEmailsCsv(data, labels);

      // 7. Filenames localizados — el usuario los verá al descomprimir.
      //    Solo distinguimos `es`/no-es: para el resto se queda en
      //    inglés (universal). Documentado en el dartdoc del notifier.
      final filenames = _localizedFilenames(locale);

      // 8. README HTML (debe construirse después de tener filenames —
      //    los referencia para que el listado coincida con lo que el
      //    usuario verá en el ZIP).
      final dateFmt = DateFormat.yMMMd(_normalizeLocaleForIntl(locale));
      final formattedDate = dateFmt.format(DateTime.now());
      final readmeBytes = buildReadmeHtml(
        data: data,
        labels: labels,
        localizedFilenames: filenames,
        formattedDate: formattedDate,
      );

      // 9. Empaquetar en ZIP (in-memory). El README va primero — es lo
      //    que el usuario suele abrir tras descomprimir y la mayoría de
      //    herramientas de ZIP lo muestran arriba en la lista.
      final archive = Archive()
        ..addFile(_zipFile(filenames[ExportFile.readme]!, readmeBytes))
        ..addFile(_zipFile(filenames[ExportFile.pdf]!, pdfBytes))
        ..addFile(_zipFile(filenames[ExportFile.json]!, jsonBytes))
        ..addFile(_zipFile(filenames[ExportFile.uploadsCsv]!, uploadsCsv))
        ..addFile(_zipFile(filenames[ExportFile.activityCsv]!, activityCsv))
        ..addFile(_zipFile(filenames[ExportFile.emailsCsv]!, emailsCsv));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      // 10. Trigger descarga.
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
      tenantPersonal: l.dataExportPdfTenantPersonal,
      loginsSummaryBuilder: l.dataExportPdfLabelLoginsSummary,
      yes: l.dataExportPdfYes,
      no: l.dataExportPdfNo,
      themeDark: l.dataExportPdfThemeDark,
      themeLight: l.dataExportPdfThemeLight,
      themeSystem: l.dataExportPdfThemeSystem,
      // ── v4: README/HTML + CSVs ──
      readmeIntro: l.dataExportPdfReadmeIntro,
      readmeFilesTitle: l.dataExportPdfReadmeFilesTitle,
      readmeSummaryTitle: l.dataExportPdfReadmeSummaryTitle,
      filePdfDesc: l.dataExportPdfFilePdfDesc,
      fileJsonDesc: l.dataExportPdfFileJsonDesc,
      fileUploadsCsvDesc: l.dataExportPdfFileUploadsCsvDesc,
      fileActivityCsvDesc: l.dataExportPdfFileActivityCsvDesc,
      fileEmailsCsvDesc: l.dataExportPdfFileEmailsCsvDesc,
      readmeGeneratedByBuilder: (date, brand) =>
          l.dataExportPdfReadmeGeneratedBy(date, brand),
      totalUploadsBuilder: l.dataExportTotalUploads,
      totalLoginsBuilder: l.dataExportTotalLogins,
      totalEventsBuilder: l.dataExportTotalEvents,
      totalEmailsBuilder: l.dataExportTotalEmails,
      csvHeaderLogin: l.dataExportCsvHeaderLogin,
    );
  }

  /// Mapa `ExportFile → filename` localizado al idioma del usuario.
  ///
  /// Por ahora distinguimos solo `es` vs resto (cae a inglés universal).
  /// Si en el futuro queremos español/portugués/etc. distintos, se
  /// extiende este switch sin tocar el resto del flow.
  Map<ExportFile, String> _localizedFilenames(String locale) {
    final base = _normalizeLocaleForIntl(locale);
    if (base == 'es') {
      return const {
        ExportFile.readme: 'LEEME.html',
        ExportFile.pdf: 'mis-datos.pdf',
        ExportFile.json: 'mis-datos.json',
        ExportFile.uploadsCsv: 'archivos.csv',
        ExportFile.activityCsv: 'actividad.csv',
        ExportFile.emailsCsv: 'correos.csv',
      };
    }
    return const {
      ExportFile.readme: 'README.html',
      ExportFile.pdf: 'my-data.pdf',
      ExportFile.json: 'my-data.json',
      ExportFile.uploadsCsv: 'files.csv',
      ExportFile.activityCsv: 'activity.csv',
      ExportFile.emailsCsv: 'emails.csv',
    };
  }

  /// Misma normalización que el PDF builder — extraída aquí para no
  /// importar `_normalizeLocale` (privado). Se acepta `es-ES`, `es_ES`,
  /// etc; mismo set de idiomas soportados que el resto del módulo.
  String _normalizeLocaleForIntl(String locale) {
    final base = locale.split(RegExp('[-_]')).first.toLowerCase();
    const supported = {'es', 'en', 'de', 'fr', 'it', 'pt', 'ru', 'uk'};
    return supported.contains(base) ? base : 'en';
  }

  /// Helper trivial para evitar repetir `ArchiveFile(name, bytes.length,
  /// bytes)` 6 veces en el bloque de empaquetado.
  ArchiveFile _zipFile(String name, Uint8List bytes) =>
      ArchiveFile(name, bytes.length, bytes);

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
