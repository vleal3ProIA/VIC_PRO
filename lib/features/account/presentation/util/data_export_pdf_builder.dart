// ============================================================================
// data_export_pdf_builder.dart
// ----------------------------------------------------------------------------
// Construye un PDF humano-legible a partir del JSON v2 devuelto por la RPC
// `get_my_data_export()`. El PDF acompaña al JSON en el ZIP final
// (`mis-datos.zip`) descargado por el usuario en "Descargar mis datos".
//
// Reglas:
//   * Sin Flutter widgets (uso `package:pdf`, multiplataforma).
//   * Sin UUIDs internos en pantalla — el JSON v2 ya los stripped, aquí
//     solo damos formato.
//   * Localizado en 8 idiomas (es, en, de, fr, it, pt, ru, uk). Los
//     labels llegan por inyección (`PdfExportLabels`) construidos con
//     `AppLocalizations.of(context)` desde el call-site.
//   * Secciones con 0 entradas se omiten — un PDF de 2 páginas que diga
//     "Tokens API (0)" añade ruido, no valor.
//   * Tablas grandes (uploads > 6) usan layout tabular; lista simple en
//     casos pequeños.
//
// Para inspeccionar el resultado: ejecutar el flow desde la app, abrir el
// .zip y revisar `mis-datos.pdf`.
// ============================================================================

import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────

/// Bag de strings localizadas que necesita el PDF.
///
/// Lo construye el call-site (notifier) leyendo `AppLocalizations.of(ctx)`
/// y se pasa al builder. Mantiene el builder libre de `BuildContext`.
class PdfExportLabels {
  PdfExportLabels({
    required this.title,
    required this.subtitle,
    required this.notice,
    required this.sectionAccount,
    required this.sectionProfile,
    required this.sectionTenants,
    required this.sectionUploads,
    required this.sectionLogins,
    required this.sectionEvents,
    required this.sectionEmails,
    required this.sectionTokens,
    required this.sectionWebhooks,
    required this.sectionNotifs,
    required this.labelEmail,
    required this.labelCreated,
    required this.labelLastLogin,
    required this.labelVerified,
    required this.labelDisplayName,
    required this.labelUsername,
    required this.labelLocale,
    required this.labelTheme,
    required this.labelName,
    required this.labelKind,
    required this.labelSize,
    required this.labelDate,
    required this.labelDeleted,
    required this.labelRole,
    required this.labelJoinedAt,
    required this.tenantPersonal,
    required this.loginsSummaryBuilder,
    required this.yes,
    required this.no,
    required this.themeDark,
    required this.themeLight,
    required this.themeSystem,
  });

  final String title;
  /// Plantilla con `{date}`. Se sustituye client-side.
  final String subtitle;
  final String notice;

  final String sectionAccount;
  final String sectionProfile;
  final String sectionTenants;
  final String sectionUploads;
  final String sectionLogins;
  final String sectionEvents;
  final String sectionEmails;
  final String sectionTokens;
  final String sectionWebhooks;
  final String sectionNotifs;

  final String labelEmail;
  final String labelCreated;
  final String labelLastLogin;
  final String labelVerified;
  final String labelDisplayName;
  final String labelUsername;
  final String labelLocale;
  final String labelTheme;
  final String labelName;
  final String labelKind;
  final String labelSize;
  final String labelDate;
  /// Sufijo entre paréntesis para uploads borrados — p.ej. "(borrado)".
  final String labelDeleted;
  final String labelRole;
  final String labelJoinedAt;

  /// Etiqueta usada para el workspace personal del usuario (cuando el
  /// `name` viene null en el export v3 porque era literalmente el email).
  final String tenantPersonal;

  /// Devuelve la línea agregada "{count} inicios de sesión entre {first}
  /// y {last}" para los parámetros dados. El call-site lo apunta al
  /// método generado de `AppLocalizations` directamente.
  final String Function(int count, String first, String last)
      loginsSummaryBuilder;

  final String yes;
  final String no;
  final String themeDark;
  final String themeLight;
  final String themeSystem;
}

/// Genera el PDF como bytes listos para empaquetar en el ZIP.
///
/// `data` es el Map devuelto por la RPC v2 (`format_version: v2`).
/// `locale` es el código ISO ('es', 'en', 'de', 'fr', 'it', 'pt', 'ru',
/// 'uk') usado para formatear fechas y números.
Future<Uint8List> buildDataExportPdf({
  required Map<String, dynamic> data,
  required String locale,
  required PdfExportLabels labels,
}) async {
  // El locale puede llegar como 'es-ES' o nulo desde Supabase. Lo
  // normalizamos al base lang para que intl tenga datos cargados (los
  // 8 idiomas listados arriba están en el bundle por defecto de intl).
  final lang = _normalizeLocale(locale);
  final dateFmt = DateFormat.yMMMd(lang);
  final dateTimeFmt = DateFormat.yMMMd(lang).add_Hm();

  final doc = pw.Document(
    title: labels.title,
    author: 'myapp',
  );

  // Color de cabecera — alineado con la paleta primary del tema.
  const brand = PdfColor.fromInt(0xFF1976D2);
  final headerStyle = pw.TextStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );

  // ── Construye páginas (MultiPage para flow automático) ──
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 36),
      header: (ctx) => ctx.pageNumber == 1
          ? _buildHeader(labels, brand, headerStyle, dateFmt)
          : pw.SizedBox(height: 16),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          '${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (ctx) => _buildBody(
        data: data,
        labels: labels,
        dateFmt: dateFmt,
        dateTimeFmt: dateTimeFmt,
      ),
    ),
  );

  return doc.save();
}

// ─────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────

pw.Widget _buildHeader(
  PdfExportLabels labels,
  PdfColor brand,
  pw.TextStyle titleStyle,
  DateFormat dateFmt,
) {
  final subtitle = labels.subtitle.replaceAll(
    '{date}',
    dateFmt.format(DateTime.now()),
  );

  return pw.Container(
    width: double.infinity,
    color: brand,
    padding: const pw.EdgeInsets.fromLTRB(40, 28, 40, 22),
    margin: const pw.EdgeInsets.only(bottom: 18),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(labels.title, style: titleStyle),
        pw.SizedBox(height: 4),
        pw.Text(
          subtitle,
          style: const pw.TextStyle(
            fontSize: 11,
            color: PdfColors.white,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// Body
// ─────────────────────────────────────────────────────────────────────

List<pw.Widget> _buildBody({
  required Map<String, dynamic> data,
  required PdfExportLabels labels,
  required DateFormat dateFmt,
  required DateFormat dateTimeFmt,
}) {
  final widgets = <pw.Widget>[];

  // Notice del export_meta — un pequeño párrafo gris para enmarcar.
  final meta = _asMap(data['export_meta']);
  final notice = (meta['notice'] as String?) ?? labels.notice;
  widgets.add(
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        notice,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
      ),
    ),
  );
  widgets.add(pw.SizedBox(height: 18));

  // ── Cuenta ──
  final account = _asMap(data['account']);
  if (account.isNotEmpty) {
    widgets.addAll(
      _section(
        title: labels.sectionAccount,
        rows: [
          _kv(labels.labelEmail, account['email'] as String?),
          _kv(labels.labelCreated, _dt(account['created_at'], dateFmt)),
          _kv(
            labels.labelLastLogin,
            _dt(account['last_sign_in_at'], dateTimeFmt),
          ),
          _kv(
            labels.labelVerified,
            account['email_confirmed_at'] != null ? labels.yes : labels.no,
          ),
        ],
      ),
    );
  }

  // ── Perfil ──
  final profile = _asMap(data['profile']);
  if (profile.isNotEmpty) {
    widgets.addAll(
      _section(
        title: labels.sectionProfile,
        rows: [
          _kv(labels.labelDisplayName, profile['display_name'] as String?),
          _kv(labels.labelUsername, profile['username'] as String?),
          _kv(labels.labelLocale, profile['locale'] as String?),
          _kv(
            labels.labelTheme,
            _themeLabel(profile['theme_mode'] as String?, labels),
          ),
          _kv(labels.labelCreated, _dt(profile['created_at'], dateFmt)),
        ],
      ),
    );
  }

  // ── Espacios de trabajo ──
  final tenants = _asList(data['tenants']);
  if (tenants.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionTenants} (${tenants.length})'));
    for (final raw in tenants) {
      final t = _asMap(raw);
      // En v3 del export el `name` viene null para el workspace personal
      // (auto-creado al registrarse, antes era literalmente el email).
      // Mostramos un placeholder "Espacio personal" en su idioma.
      final isPersonal = t['is_personal'] == true;
      final rawName = t['name'] as String?;
      final name = (rawName == null || rawName.trim().isEmpty)
          ? (isPersonal ? labels.tenantPersonal : '—')
          : rawName;
      final role = t['role'] as String? ?? '';
      final joined = _dt(t['joined_at'], dateFmt) ?? '';
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Text(
            '• $name — $role · ${labels.labelJoinedAt} $joined',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      );
    }
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Archivos subidos ──
  final uploads = _asList(data['uploads']);
  if (uploads.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionUploads} (${uploads.length})'));
    widgets.add(_uploadsTable(uploads, labels, dateFmt));
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Audit logs: login summary + other events ──
  final audit = _asMap(data['audit_logs']);
  final summary = _asMap(audit['login_summary']);
  final total = (summary['total'] as num?)?.toInt() ?? 0;
  if (total > 0) {
    final first = _dt(summary['first_at'], dateFmt) ?? '';
    final last = _dt(summary['last_at'], dateFmt) ?? '';
    final line = labels.loginsSummaryBuilder(total, first, last);
    widgets.add(_sectionTitle(labels.sectionLogins));
    widgets.add(
      pw.Text(line, style: const pw.TextStyle(fontSize: 10)),
    );
    widgets.add(pw.SizedBox(height: 14));
  }

  final others = _asList(audit['other_events']);
  if (others.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionEvents} (${others.length})'));
    for (final raw in others) {
      final e = _asMap(raw);
      final when = _dt(e['occurred_at'], dateTimeFmt) ?? '';
      final ev = e['event'] as String? ?? '';
      final evMeta = _asMap(e['metadata']);
      final extra = _formatEventMeta(evMeta);
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            extra.isEmpty ? '• $when — $ev' : '• $when — $ev · $extra',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ),
      );
    }
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Emails recibidos ──
  final emails = _asList(data['emails_received']);
  if (emails.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionEmails} (${emails.length})'));
    for (final raw in emails) {
      final e = _asMap(raw);
      final when = _dt(e['created_at'], dateFmt) ?? '';
      final subject = e['subject'] as String? ?? '—';
      final status = e['status'] as String? ?? '';
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            '• $when — "$subject" ($status)',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      );
    }
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Personal Access Tokens ──
  final pats = _asList(data['personal_access_tokens']);
  if (pats.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionTokens} (${pats.length})'));
    for (final raw in pats) {
      final t = _asMap(raw);
      final name = t['name'] as String? ?? '—';
      final created = _dt(t['created_at'], dateFmt) ?? '';
      final revoked = _dt(t['revoked_at'], dateFmt);
      final suffix = revoked != null ? ' · ${labels.labelDeleted}' : '';
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            '• $name — $created$suffix',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      );
    }
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Webhooks ──
  final webhooks = _asList(data['webhook_endpoints']);
  if (webhooks.isNotEmpty) {
    widgets.add(
      _sectionTitle('${labels.sectionWebhooks} (${webhooks.length})'),
    );
    for (final raw in webhooks) {
      final w = _asMap(raw);
      final url = w['url'] as String? ?? '—';
      final active = (w['active'] as bool?) ?? false;
      final state = active ? labels.yes : labels.no;
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            '• $url (${labels.yes}/${labels.no}: $state)',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ),
      );
    }
    widgets.add(pw.SizedBox(height: 14));
  }

  // ── Notificaciones ──
  final notifs = _asList(data['notifications']);
  if (notifs.isNotEmpty) {
    widgets.add(_sectionTitle('${labels.sectionNotifs} (${notifs.length})'));
    for (final raw in notifs) {
      final n = _asMap(raw);
      final when = _dt(n['created_at'], dateFmt) ?? '';
      final title = n['title'] as String? ?? '—';
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(
            '• $when — $title',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      );
    }
  }

  return widgets;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers de layout
// ─────────────────────────────────────────────────────────────────────

pw.Widget _sectionTitle(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
    child: pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey400),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey800,
        ),
      ),
    ),
  );
}

List<pw.Widget> _section({
  required String title,
  required List<pw.Widget> rows,
}) {
  final live = rows.where((w) => w is! _Empty).toList();
  if (live.isEmpty) return const [];
  return [
    _sectionTitle(title),
    ...live,
    pw.SizedBox(height: 12),
  ];
}

/// Devuelve una fila clave-valor o un widget marcador (filtrado luego) si
/// el valor es null/vacío.
pw.Widget _kv(String key, String? value) {
  if (value == null || value.isEmpty) return _Empty();
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 150,
          child: pw.Text(
            '$key:',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

/// Marker widget — el filtro `_section` lo descarta. Es un `Container`
/// vacío para que, si por alguna razón llegara al renderer, no rompa
/// nada (medida 0×0).
class _Empty extends pw.StatelessWidget {
  _Empty();

  @override
  pw.Widget build(pw.Context context) =>
      pw.SizedBox(width: 0, height: 0);
}

// ─────────────────────────────────────────────────────────────────────
// Uploads table
// ─────────────────────────────────────────────────────────────────────

pw.Widget _uploadsTable(
  List<dynamic> uploads,
  PdfExportLabels labels,
  DateFormat dateFmt,
) {
  final headerStyle = pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.grey800,
  );
  const cellStyle = pw.TextStyle(fontSize: 9.5);

  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FlexColumnWidth(1.4),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.5),
    },
    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _cell(labels.labelName, headerStyle),
          _cell(labels.labelKind, headerStyle),
          _cell(labels.labelSize, headerStyle),
          _cell(labels.labelDate, headerStyle),
        ],
      ),
      for (var i = 0; i < uploads.length; i++)
        pw.TableRow(
          decoration: i.isOdd
              ? const pw.BoxDecoration(color: PdfColors.grey100)
              : null,
          children: () {
            final u = _asMap(uploads[i]);
            final filename = (u['filename'] as String?) ?? '—';
            final deleted = u['deleted_at'] != null;
            final name = deleted
                ? '$filename ${labels.labelDeleted}'
                : filename;
            final kind = _shortKind(u['kind'] as String?);
            final size = _humanBytes((u['size_bytes'] as num?)?.toInt() ?? 0);
            final date = _dt(u['uploaded_at'], dateFmt) ?? '';
            return [
              _cell(name, cellStyle, color: deleted ? PdfColors.grey500 : null),
              _cell(kind, cellStyle),
              _cell(size, cellStyle),
              _cell(date, cellStyle),
            ];
          }(),
        ),
    ],
  );
}

pw.Widget _cell(String text, pw.TextStyle style, {PdfColor? color}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(
      text,
      style: color != null ? style.copyWith(color: color) : style,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// Format helpers
// ─────────────────────────────────────────────────────────────────────

String _normalizeLocale(String locale) {
  // Acepta 'es', 'es-ES', 'es_ES', etc.
  final base = locale.split(RegExp('[-_]')).first.toLowerCase();
  const supported = {'es', 'en', 'de', 'fr', 'it', 'pt', 'ru', 'uk'};
  return supported.contains(base) ? base : 'en';
}

String? _dt(Object? raw, DateFormat fmt) {
  if (raw == null) return null;
  final s = raw.toString();
  final dt = DateTime.tryParse(s);
  if (dt == null) return null;
  return fmt.format(dt.toLocal());
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _shortKind(String? mime) {
  if (mime == null || mime.isEmpty) return '—';
  // 'image/jpeg' -> 'JPG', 'application/pdf' -> 'PDF', 'text/plain' -> 'TXT'
  final sub = mime.split('/').last.toUpperCase();
  return switch (sub) {
    'JPEG' => 'JPG',
    'PLAIN' => 'TXT',
    'SVG+XML' => 'SVG',
    _ => sub.length > 6 ? sub.substring(0, 6) : sub,
  };
}

String _themeLabel(String? mode, PdfExportLabels labels) {
  return switch (mode) {
    'dark' => labels.themeDark,
    'light' => labels.themeLight,
    _ => labels.themeSystem,
  };
}

String _formatEventMeta(Map<String, dynamic> meta) {
  if (meta.isEmpty) return '';
  // Damos prioridad a `filename` y dejamos size_bytes legible.
  final parts = <String>[];
  final filename = meta['filename'];
  if (filename is String && filename.isNotEmpty) parts.add(filename);
  return parts.join(' · ');
}

Map<String, dynamic> _asMap(Object? raw) {
  if (raw is Map) return raw.cast<String, dynamic>();
  return const {};
}

List<dynamic> _asList(Object? raw) {
  if (raw is List) return raw;
  return const [];
}

// ─────────────────────────────────────────────────────────────────────
// Label bundles per locale (8 idiomas)
// ─────────────────────────────────────────────────────────────────────

/// Fallback estático en caso de no tener `AppLocalizations` disponible —
/// p.ej. tests unitarios del builder. El call-site real (notifier) usa
/// `AppLocalizations.of(context)` directamente y NO necesita esta función.
PdfExportLabels fallbackPdfExportLabels(String locale) {
  return switch (_normalizeLocale(locale)) {
    'es' => _es,
    'en' => _en,
    'de' => _de,
    'fr' => _fr,
    'it' => _it,
    'pt' => _pt,
    'ru' => _ru,
    'uk' => _uk,
    _ => _en,
  };
}

final _es = PdfExportLabels(
  title: 'Mis datos personales',
  subtitle: 'Exportado el {date}',
  notice: 'Este export contiene tus datos personales. No lo compartas.',
  sectionAccount: 'Cuenta',
  sectionProfile: 'Perfil',
  sectionTenants: 'Espacios de trabajo',
  sectionUploads: 'Archivos subidos',
  sectionLogins: 'Actividad de inicio de sesión',
  sectionEvents: 'Otros eventos',
  sectionEmails: 'Correos recibidos',
  sectionTokens: 'Tokens API',
  sectionWebhooks: 'Webhooks',
  sectionNotifs: 'Notificaciones',
  labelEmail: 'Email',
  labelCreated: 'Cuenta creada el',
  labelLastLogin: 'Último inicio de sesión',
  labelVerified: 'Email verificado',
  labelDisplayName: 'Nombre mostrado',
  labelUsername: 'Usuario',
  labelLocale: 'Idioma',
  labelTheme: 'Tema',
  labelName: 'Nombre',
  labelKind: 'Tipo',
  labelSize: 'Tamaño',
  labelDate: 'Fecha',
  labelDeleted: '(borrado)',
  labelRole: 'Rol',
  labelJoinedAt: 'Miembro desde',
  tenantPersonal: 'Espacio personal',
  loginsSummaryBuilder: _esLogins,
  yes: 'Sí',
  no: 'No',
  themeDark: 'Oscuro',
  themeLight: 'Claro',
  themeSystem: 'Sistema',
);

final _en = PdfExportLabels(
  title: 'My personal data',
  subtitle: 'Exported on {date}',
  notice: 'This export contains your personal data. Do not share it.',
  sectionAccount: 'Account',
  sectionProfile: 'Profile',
  sectionTenants: 'Workspaces',
  sectionUploads: 'Uploaded files',
  sectionLogins: 'Sign-in activity',
  sectionEvents: 'Other events',
  sectionEmails: 'Emails received',
  sectionTokens: 'API tokens',
  sectionWebhooks: 'Webhooks',
  sectionNotifs: 'Notifications',
  labelEmail: 'Email',
  labelCreated: 'Account created',
  labelLastLogin: 'Last sign-in',
  labelVerified: 'Email verified',
  labelDisplayName: 'Display name',
  labelUsername: 'Username',
  labelLocale: 'Language',
  labelTheme: 'Theme',
  labelName: 'Name',
  labelKind: 'Type',
  labelSize: 'Size',
  labelDate: 'Date',
  labelDeleted: '(deleted)',
  labelRole: 'Role',
  labelJoinedAt: 'Member since',
  tenantPersonal: 'Personal workspace',
  loginsSummaryBuilder: _enLogins,
  yes: 'Yes',
  no: 'No',
  themeDark: 'Dark',
  themeLight: 'Light',
  themeSystem: 'System',
);

final _de = PdfExportLabels(
  title: 'Meine persönlichen Daten',
  subtitle: 'Exportiert am {date}',
  notice: 'Dieser Export enthält deine persönlichen Daten. Nicht teilen.',
  sectionAccount: 'Konto',
  sectionProfile: 'Profil',
  sectionTenants: 'Arbeitsbereiche',
  sectionUploads: 'Hochgeladene Dateien',
  sectionLogins: 'Anmeldeaktivität',
  sectionEvents: 'Weitere Ereignisse',
  sectionEmails: 'Empfangene E-Mails',
  sectionTokens: 'API-Tokens',
  sectionWebhooks: 'Webhooks',
  sectionNotifs: 'Benachrichtigungen',
  labelEmail: 'E-Mail',
  labelCreated: 'Konto erstellt am',
  labelLastLogin: 'Letzte Anmeldung',
  labelVerified: 'E-Mail bestätigt',
  labelDisplayName: 'Anzeigename',
  labelUsername: 'Benutzername',
  labelLocale: 'Sprache',
  labelTheme: 'Design',
  labelName: 'Name',
  labelKind: 'Typ',
  labelSize: 'Größe',
  labelDate: 'Datum',
  labelDeleted: '(gelöscht)',
  labelRole: 'Rolle',
  labelJoinedAt: 'Mitglied seit',
  tenantPersonal: 'Persönlicher Arbeitsbereich',
  loginsSummaryBuilder: _deLogins,
  yes: 'Ja',
  no: 'Nein',
  themeDark: 'Dunkel',
  themeLight: 'Hell',
  themeSystem: 'System',
);

final _fr = PdfExportLabels(
  title: 'Mes données personnelles',
  subtitle: 'Exporté le {date}',
  notice: 'Cet export contient vos données personnelles. Ne le partagez pas.',
  sectionAccount: 'Compte',
  sectionProfile: 'Profil',
  sectionTenants: 'Espaces de travail',
  sectionUploads: 'Fichiers téléchargés',
  sectionLogins: 'Activité de connexion',
  sectionEvents: 'Autres événements',
  sectionEmails: 'E-mails reçus',
  sectionTokens: 'Jetons API',
  sectionWebhooks: 'Webhooks',
  sectionNotifs: 'Notifications',
  labelEmail: 'E-mail',
  labelCreated: 'Compte créé le',
  labelLastLogin: 'Dernière connexion',
  labelVerified: 'E-mail vérifié',
  labelDisplayName: 'Nom affiché',
  labelUsername: "Nom d'utilisateur",
  labelLocale: 'Langue',
  labelTheme: 'Thème',
  labelName: 'Nom',
  labelKind: 'Type',
  labelSize: 'Taille',
  labelDate: 'Date',
  labelDeleted: '(supprimé)',
  labelRole: 'Rôle',
  labelJoinedAt: 'Membre depuis',
  tenantPersonal: 'Espace personnel',
  loginsSummaryBuilder: _frLogins,
  yes: 'Oui',
  no: 'Non',
  themeDark: 'Sombre',
  themeLight: 'Clair',
  themeSystem: 'Système',
);

final _it = PdfExportLabels(
  title: 'I miei dati personali',
  subtitle: 'Esportato il {date}',
  notice: 'Questo export contiene i tuoi dati personali. Non condividerlo.',
  sectionAccount: 'Account',
  sectionProfile: 'Profilo',
  sectionTenants: 'Spazi di lavoro',
  sectionUploads: 'File caricati',
  sectionLogins: 'Attività di accesso',
  sectionEvents: 'Altri eventi',
  sectionEmails: 'Email ricevute',
  sectionTokens: 'Token API',
  sectionWebhooks: 'Webhook',
  sectionNotifs: 'Notifiche',
  labelEmail: 'Email',
  labelCreated: 'Account creato il',
  labelLastLogin: 'Ultimo accesso',
  labelVerified: 'Email verificata',
  labelDisplayName: 'Nome visualizzato',
  labelUsername: 'Nome utente',
  labelLocale: 'Lingua',
  labelTheme: 'Tema',
  labelName: 'Nome',
  labelKind: 'Tipo',
  labelSize: 'Dimensione',
  labelDate: 'Data',
  labelDeleted: '(eliminato)',
  labelRole: 'Ruolo',
  labelJoinedAt: 'Membro dal',
  tenantPersonal: 'Spazio personale',
  loginsSummaryBuilder: _itLogins,
  yes: 'Sì',
  no: 'No',
  themeDark: 'Scuro',
  themeLight: 'Chiaro',
  themeSystem: 'Sistema',
);

final _pt = PdfExportLabels(
  title: 'Os meus dados pessoais',
  subtitle: 'Exportado em {date}',
  notice: 'Esta exportação contém os teus dados pessoais. Não a partilhes.',
  sectionAccount: 'Conta',
  sectionProfile: 'Perfil',
  sectionTenants: 'Espaços de trabalho',
  sectionUploads: 'Ficheiros enviados',
  sectionLogins: 'Atividade de início de sessão',
  sectionEvents: 'Outros eventos',
  sectionEmails: 'Emails recebidos',
  sectionTokens: 'Tokens API',
  sectionWebhooks: 'Webhooks',
  sectionNotifs: 'Notificações',
  labelEmail: 'Email',
  labelCreated: 'Conta criada em',
  labelLastLogin: 'Último início de sessão',
  labelVerified: 'Email verificado',
  labelDisplayName: 'Nome a apresentar',
  labelUsername: 'Utilizador',
  labelLocale: 'Idioma',
  labelTheme: 'Tema',
  labelName: 'Nome',
  labelKind: 'Tipo',
  labelSize: 'Tamanho',
  labelDate: 'Data',
  labelDeleted: '(eliminado)',
  labelRole: 'Função',
  labelJoinedAt: 'Membro desde',
  tenantPersonal: 'Espaço pessoal',
  loginsSummaryBuilder: _ptLogins,
  yes: 'Sim',
  no: 'Não',
  themeDark: 'Escuro',
  themeLight: 'Claro',
  themeSystem: 'Sistema',
);

final _ru = PdfExportLabels(
  title: 'Мои персональные данные',
  subtitle: 'Экспортировано {date}',
  notice: 'В этом файле содержатся ваши персональные данные. Не передавайте его.',
  sectionAccount: 'Аккаунт',
  sectionProfile: 'Профиль',
  sectionTenants: 'Рабочие пространства',
  sectionUploads: 'Загруженные файлы',
  sectionLogins: 'История входов',
  sectionEvents: 'Другие события',
  sectionEmails: 'Полученные письма',
  sectionTokens: 'API-токены',
  sectionWebhooks: 'Веб-хуки',
  sectionNotifs: 'Уведомления',
  labelEmail: 'Email',
  labelCreated: 'Аккаунт создан',
  labelLastLogin: 'Последний вход',
  labelVerified: 'Email подтверждён',
  labelDisplayName: 'Отображаемое имя',
  labelUsername: 'Имя пользователя',
  labelLocale: 'Язык',
  labelTheme: 'Тема',
  labelName: 'Имя',
  labelKind: 'Тип',
  labelSize: 'Размер',
  labelDate: 'Дата',
  labelDeleted: '(удалено)',
  labelRole: 'Роль',
  labelJoinedAt: 'Участник с',
  tenantPersonal: 'Личное пространство',
  loginsSummaryBuilder: _ruLogins,
  yes: 'Да',
  no: 'Нет',
  themeDark: 'Тёмная',
  themeLight: 'Светлая',
  themeSystem: 'Системная',
);

final _uk = PdfExportLabels(
  title: 'Мої персональні дані',
  subtitle: 'Експортовано {date}',
  notice: 'Цей файл містить ваші персональні дані. Не передавайте його.',
  sectionAccount: 'Обліковий запис',
  sectionProfile: 'Профіль',
  sectionTenants: 'Робочі простори',
  sectionUploads: 'Завантажені файли',
  sectionLogins: 'Активність входу',
  sectionEvents: 'Інші події',
  sectionEmails: 'Отримані листи',
  sectionTokens: 'API-токени',
  sectionWebhooks: 'Веб-гуки',
  sectionNotifs: 'Сповіщення',
  labelEmail: 'Email',
  labelCreated: 'Створено',
  labelLastLogin: 'Останній вхід',
  labelVerified: 'Email підтверджено',
  labelDisplayName: "Відображуване ім'я",
  labelUsername: 'Користувач',
  labelLocale: 'Мова',
  labelTheme: 'Тема',
  labelName: 'Назва',
  labelKind: 'Тип',
  labelSize: 'Розмір',
  labelDate: 'Дата',
  labelDeleted: '(видалено)',
  labelRole: 'Роль',
  labelJoinedAt: 'Учасник з',
  tenantPersonal: 'Особистий простір',
  loginsSummaryBuilder: _ukLogins,
  yes: 'Так',
  no: 'Ні',
  themeDark: 'Темна',
  themeLight: 'Світла',
  themeSystem: 'Системна',
);

// Las funciones `_xxLogins` son las usadas por los fallbacks estáticos
// arriba. El call-site real (notifier) pasa
// `AppLocalizations.of(ctx).dataExportPdfLabelLoginsSummary` directamente,
// que tiene la misma firma `(int, String, String) -> String`.
String _esLogins(int c, String f, String l) =>
    '$c inicios de sesión entre $f y $l';
String _enLogins(int c, String f, String l) =>
    '$c sign-ins between $f and $l';
String _deLogins(int c, String f, String l) =>
    '$c Anmeldungen zwischen $f und $l';
String _frLogins(int c, String f, String l) =>
    '$c connexions entre $f et $l';
String _itLogins(int c, String f, String l) =>
    '$c accessi tra il $f e il $l';
String _ptLogins(int c, String f, String l) =>
    '$c inícios de sessão entre $f e $l';
String _ruLogins(int c, String f, String l) => '$c входов между $f и $l';
String _ukLogins(int c, String f, String l) => '$c входів між $f і $l';
