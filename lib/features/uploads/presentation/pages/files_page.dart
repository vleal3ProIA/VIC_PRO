import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/uploads_providers.dart';
import '../../data/uploads_datasource.dart';
import '../../domain/uploaded_file.dart';
import '../widgets/storage_quota_bar.dart';

/// `/account-settings/files` — lista de archivos subidos por el tenant +
/// barra de cuota + botón para subir uno nuevo. Sirve a la vez como:
///   - "papelera" donde ves todo lo subido
///   - chequeo de cuánto storage te queda
///   - punto para limpiar archivos viejos
class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  bool _uploading = false;
  Timer? _scanPollTimer;

  /// Página actual (0-indexed) de la paginación client-side.
  int _page = 0;

  /// Archivos por página.
  static const int _pageSize = 20;

  @override
  void dispose() {
    _scanPollTimer?.cancel();
    super.dispose();
  }

  /// PR-C UX: cuando hay uploads con `virus_scan_status='pending'`, el
  /// chip muestra "Escaneando..." pero el scan se hace en background
  /// (Edge Function `scan-upload` tarda ~5-30s). Sin polling el user
  /// tiene que pulsar F5 para ver el resultado. Aqui re-fetchamos la
  /// lista cada 5s mientras quede algun pending; en cuanto todos
  /// resuelven (clean/suspicious/error/skipped) cancelamos el timer.
  void _maybePollPendingScans(List<UploadedFile> files) {
    final hasPending =
        files.any((f) => f.virusScanStatus == VirusScanStatus.pending);
    if (hasPending) {
      if (_scanPollTimer == null || !_scanPollTimer!.isActive) {
        _scanPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          // Si el widget se desmonto entre tick y tick, paramos.
          if (!mounted) {
            _scanPollTimer?.cancel();
            _scanPollTimer = null;
            return;
          }
          ref.invalidate(tenantUploadsProvider);
        });
      }
    } else if (_scanPollTimer != null) {
      _scanPollTimer!.cancel();
      _scanPollTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(tenantUploadsProvider);
    // Cuando el provider tenga datos, decidimos si hay que pollear.
    // Lo metemos en addPostFrameCallback para no setState durante build.
    async.whenData((files) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybePollPendingScans(files);
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.popOrGo(RouteNames.accountSettings),
        ),
        title: Text(l.filesTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                ..invalidate(tenantUploadsProvider)
                ..invalidate(tenantStorageQuotaProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: Text(l.filesUpload),
        onPressed: _uploading ? null : _onUpload,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: double.infinity),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: StorageQuotaBar(),
              ),
              const Divider(height: 1),
              Expanded(
                child: async.when(
                  loading: () => const AppLoadingState(),
                  error: (e, _) => AppErrorState(
                    message: l.filesLoadError,
                    detail: e.toString(),
                    onRetry: () => ref.invalidate(tenantUploadsProvider),
                    retryLabel: l.actionRetry,
                  ),
                  data: (files) {
                    if (files.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.folder_outlined,
                        title: l.filesEmptyTitle,
                        message: l.filesEmptyBody,
                      );
                    }
                    // Paginación client-side: la lista llega completa y la
                    // cortamos en páginas de [_pageSize]. `page` se clampa por
                    // si un borrado/refresh redujo el total bajo `_page`.
                    final totalPages = (files.length / _pageSize).ceil();
                    final page = _page.clamp(0, totalPages - 1);
                    final start = page * _pageSize;
                    final end = (start + _pageSize) > files.length
                        ? files.length
                        : start + _pageSize;
                    final pageFiles = files.sublist(start, end);
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 96),
                            itemCount: pageFiles.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (_, i) =>
                                _FileTile(file: pageFiles[i]),
                          ),
                        ),
                        AppPaginationBar(
                          currentPage: page,
                          totalPages: totalPages,
                          onPrevious: () => setState(() => _page = page - 1),
                          onNext: () => setState(() => _page = page + 1),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onUpload() async {
    final l = context.l10n;
    final picker = ImagePicker();
    final XFile? file;
    try {
      file = await picker.pickMedia();
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.filesPickError, isError: true);
      return;
    }
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? _guessMime(file.name);
      if (mime == null) {
        if (!mounted) return;
        context.showSnack(l.filesUnsupportedType, isError: true);
        return;
      }
      final tenantId = ref.read(currentTenantIdProvider);
      await ref.read(uploadsDataSourceProvider).upload(
            filename: file.name,
            mimeType: mime,
            bytes: bytes,
            tenantId: tenantId,
          );
      if (!mounted) return;
      ref
        ..invalidate(tenantUploadsProvider)
        ..invalidate(tenantStorageQuotaProvider);
      context.showSnack(l.filesUploaded);
    } on UploadException catch (e) {
      if (!mounted) return;
      context.showSnack(_friendlyUploadError(l, e), isError: true);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.filesUploadError, isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return null;
  }

  String _friendlyUploadError(AppLocalizations l, UploadException e) {
    switch (e.code) {
      case 'quota_exceeded':
        return l.filesQuotaExceeded;
      case 'file_too_large':
      case 'size_mismatch': // server cazo size declarado != real
        return l.filesTooLarge;
      case 'file_too_small':
        return l.filesEmptyFile;
      case 'unsupported_mime':
        return l.filesUnsupportedType;
      case 'magic_bytes_mismatch': // el archivo no corresponde al MIME declarado
      case 'invalid_utf8_text':    // .txt/.csv etc. con contenido binario
        return l.filesContentRejected;
      case 'rate_limited':
        return l.filesRateLimited;
      // Errores intermedios del flow 2 pasos -> mismo mensaje generico
      // (el user no necesita distinguir signed_url_error de put_failed).
      case 'signed_url_error':
      case 'put_failed':
      case 'object_not_found':
      case 'forbidden':
      default:
        return l.filesUploadError;
    }
  }
}

class _FileTile extends ConsumerStatefulWidget {
  const _FileTile({required this.file});
  final UploadedFile file;

  @override
  ConsumerState<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends ConsumerState<_FileTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final fmt = DateFormat.yMMMd(localeCode).add_Hm();
    final f = widget.file;
    final icon = _iconForMime(f.mimeType);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: context.colors.primary),
        title: Text(f.filename, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${formatBytes(f.sizeBytes)} • ${fmt.format(f.createdAt.toLocal())}',
            ),
            // PR-C: chip de estado del scan antivirus. Solo lo
            // mostramos cuando aporta valor (clean tras un scan exitoso,
            // pending mientras esta en cola, etc.). 'skipped' se oculta
            // para no contaminar la UI con archivos viejos / grandes.
            if (f.virusScanStatus != VirusScanStatus.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _VirusScanChip(status: f.virusScanStatus),
              ),
          ],
        ),
        isThreeLine: f.virusScanStatus != VirusScanStatus.skipped,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l.filesOpen,
              icon: const Icon(Icons.open_in_new),
              onPressed: _busy ? null : _onOpen,
            ),
            IconButton(
              tooltip: l.filesDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onOpen() async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final url = await ref
          .read(uploadsDataSourceProvider)
          .getSignedUrl(widget.file.id);
      if (!mounted) return;
      if (url == null) {
        context.showSnack(l.filesOpenError, isError: true);
        return;
      }
      // En web abrimos en nueva pestaña; en mobile delegamos a
      // url_launcher (queda fuera de esta PR para no inflar).
      // Por ahora: copiar al portapapeles y notificar.
      // En web abre nueva pestaña; en mobile delega al OS via
      // url_launcher (paquete ya en pubspec, usado por /admin/branding).
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        context.showSnack(l.filesOpenError, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.filesOpenError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    final l = context.l10n;
    final ok = await AppConfirmDialog.show(
      context,
      title: l.filesDeleteConfirmTitle,
      body: l.filesDeleteConfirmBody(widget.file.filename),
      confirmLabel: l.filesDelete,
      cancelLabel: l.actionCancel,
      danger: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(uploadsDataSourceProvider).delete(widget.file.id);
      if (!mounted) return;
      ref
        ..invalidate(tenantUploadsProvider)
        ..invalidate(tenantStorageQuotaProvider);
      context.showSnack(l.filesDeleted);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.filesDeleteError, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.contains('spreadsheet') || mime == 'text/csv') {
      return Icons.table_chart_outlined;
    }
    if (mime.contains('word')) return Icons.description_outlined;
    if (mime == 'application/zip') return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

/// Chip visual que muestra el estado del scan antivirus de un upload.
/// PR-C: ayuda al user a entender por que un archivo recien subido
/// aparece marcado como "Escaneando..." (no es un bug, es VirusTotal
/// procesando). Si suspicious, el upload ya esta soft-deleted asi que
/// normalmente no se ve en la lista; el caso de mostrar 'suspicious'
/// aqui es para admin (que ve uploads de todos los tenants).
class _VirusScanChip extends StatelessWidget {
  const _VirusScanChip({required this.status});

  final VirusScanStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final (label, icon, bg, fg) = switch (status) {
      VirusScanStatus.pending => (
          l.virusScanPending,
          Icons.hourglass_top_outlined,
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      VirusScanStatus.clean => (
          l.virusScanClean,
          Icons.verified_outlined,
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
      VirusScanStatus.suspicious => (
          l.virusScanSuspicious,
          Icons.warning_amber_outlined,
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
      VirusScanStatus.error => (
          l.virusScanError,
          Icons.error_outline,
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      // 'skipped' no debería renderizar; el caller ya filtra. Por
      // seguridad damos un fallback discreto.
      VirusScanStatus.skipped => (
          l.virusScanSkipped,
          Icons.info_outline,
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
