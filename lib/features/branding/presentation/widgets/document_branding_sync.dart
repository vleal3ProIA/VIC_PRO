import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/branding_providers.dart';
import 'document_branding_sync_stub.dart'
    if (dart.library.js_interop) 'document_branding_sync_web.dart' as impl;

/// Side-effect widget que sincroniza el `<title>` y el `<link rel="icon">`
/// del documento HTML con el branding configurado en la BD. Solo tiene
/// efecto en web; en mobile/desktop es no-op (los conceptos no aplican).
///
/// Se monta en `MaterialApp.builder` para que el rebuild ocurra cada
/// vez que el provider de branding emite. Sin esto el navegador
/// seguiría mostrando "myapp" eternamente en la pestaña, ignorando
/// el nombre comercial elegido en `/setup`.
class DocumentBrandingSync extends ConsumerWidget {
  const DocumentBrandingSync({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      final branding = ref.watch(brandingOrFallbackProvider);
      // Implementación condicional vía conditional import — en mobile
      // este simbolo no se enlaza, en web sí.
      impl.applyToDocument(
        title: branding.commercialName,
        faviconUrl: branding.faviconUrl,
      );
    }
    return child;
  }
}
