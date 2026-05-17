import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_confirm_dialog.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(tenantUploadsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
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
          constraints: const BoxConstraints(maxWidth: 720),
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
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: files.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) => _FileTile(file: files[i]),
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
        return l.filesTooLarge;
      case 'unsupported_mime':
        return l.filesUnsupportedType;
      case 'rate_limited':
        return l.filesRateLimited;
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
        subtitle: Text(
          '${formatBytes(f.sizeBytes)} • ${fmt.format(f.createdAt.toLocal())}',
        ),
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
