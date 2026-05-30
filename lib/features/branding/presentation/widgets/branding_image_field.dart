import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/providers/supabase_providers.dart';
import 'package:myapp/core/security/image_magic_bytes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Campo combinado para los assets de branding (logo, favicon, og-image)
/// del admin panel: muestra una vista previa cuadrada arriba, un
/// `TextFormField` editable con la URL en medio (para que el admin pueda
/// pegar una URL externa de CDN sin pasar por Supabase Storage), y un
/// boton "subir" que abre el selector de imagenes del dispositivo y sube
/// los bytes al bucket publico `branding-assets` bajo `<kind>` (singleton
/// por deploy — los re-uploads sobrescriben con `upsert: true`).
///
/// **Seguridad**: antes de subir validamos magic bytes contra
/// `kAllowedBrandingMimes`. RLS del bucket gatea la escritura a admins
/// con `manage_app_branding` (ver migracion 0077).
///
/// **Cache busting**: tras subir, la URL publica recibe `?v=<millis>` para
/// invalidar el cache del navegador y que la nueva imagen se vea ya.
class BrandingImageField extends ConsumerStatefulWidget {
  const BrandingImageField({
    required this.controller,
    required this.label,
    required this.helperText,
    required this.kind,
    required this.icon,
    super.key,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String helperText;

  /// Subcarpeta dentro del bucket: 'logo' | 'logo-dark' | 'favicon' |
  /// 'og-image'. Sin slashes ni rutas anidadas.
  final String kind;

  /// Icono que se muestra como `prefixIcon` del campo de URL.
  final IconData icon;

  final bool enabled;

  @override
  ConsumerState<BrandingImageField> createState() =>
      _BrandingImageFieldState();
}

class _BrandingImageFieldState extends ConsumerState<BrandingImageField> {
  static const String _bucket = 'branding-assets';
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    if (_uploading) return;
    final l = context.l10n;

    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.brandingImageUploadError, isError: true);
      return;
    }
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final contentType = file.mimeType ?? _guessContentType(file.name);

    // Gate magic-bytes: rechazo client-side ANTES de tocar Storage.
    // Para SVG/ICO los headers son distintos a los rasters de avatar; ver
    // `kAllowedBrandingMimes` y signatures en image_magic_bytes.dart.
    if (!kAllowedBrandingMimes.contains(contentType) ||
        !validateImageMagicBytes(bytes, contentType)) {
      if (!mounted) return;
      context.showSnack(l.brandingImageInvalidFormat, isError: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.storage.from(_bucket).uploadBinary(
            widget.kind,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );
      final publicUrl =
          client.storage.from(_bucket).getPublicUrl(widget.kind);
      final urlWithBust =
          '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
      if (!mounted) return;
      widget.controller.text = urlWithBust;
      context.showSnack(l.brandingImageUploadSuccess);
    } catch (_) {
      if (!mounted) return;
      context.showSnack(l.brandingImageUploadError, isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final fieldEnabled = widget.enabled && !_uploading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Preview ───
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            return _Preview(
              url: value.text.trim(),
              emptyLabel: l.brandingImageNoPreview,
            );
          },
        ),
        const SizedBox(height: 8),
        // ─── URL field + upload button ───
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            prefixIcon: Icon(widget.icon),
            suffixIcon: IconButton(
              tooltip: l.brandingUploadImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              onPressed: fieldEnabled ? _pickAndUpload : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Vista previa cuadrada (64x64) del asset apuntado por `url`. Si la URL
/// esta vacia muestra un placeholder con borde discontinuo + icono. Si
/// es SVG usamos `flutter_svg` (ya en pubspec) — el resto via `Image.network`
/// que en web cubre PNG/JPG/WEBP/GIF/ICO nativamente.
class _Preview extends StatelessWidget {
  const _Preview({required this.url, required this.emptyLabel});

  final String url;
  final String emptyLabel;

  bool get _isSvg => url.toLowerCase().split('?').first.endsWith('.svg');

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final border = Border.all(
      color: scheme.outlineVariant,
      width: 1,
    );

    if (url.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: border,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: scheme.onSurfaceVariant,
            size: 28,
          ),
        ),
      );
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: border,
        color: scheme.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: _isSvg
          ? SvgPicture.network(
              url,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: scheme.error,
                  size: 28,
                ),
              ),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
