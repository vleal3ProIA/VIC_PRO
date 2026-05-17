import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/branding/application/branding_providers.dart';

import 'meta_tags_sync_stub.dart'
    if (dart.library.js_interop) 'meta_tags_sync_web.dart' as impl;
import 'seo_meta.dart';

/// Side-effect widget que sincroniza los meta tags del documento HTML
/// con el branding + la ruta actual. Solo tiene efecto en web.
///
/// **Crawler tip**: la mayoría de crawlers (Twitter, LinkedIn, Slack)
/// NO ejecutan JS — solo leen el HTML inicial, que tiene los tags
/// inyectados por `scripts/generate_seo.dart` en build. Este widget
/// SOLO ayuda a:
///   - Google moderno y otros crawlers que sí ejecutan JS
///   - Browsers reales (cambia el title de la pestaña al navegar)
///
/// Para crawlers tontos por ruta concreta hay que hacer prerendering
/// estático (pendiente — depende de hosting).
class MetaTagsSync extends ConsumerWidget {
  const MetaTagsSync({required this.meta, super.key});
  final SeoMeta meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) {
      final branding = ref.watch(brandingOrFallbackProvider);
      impl.applyMetaTags(
        title: meta.title,
        description: meta.description,
        siteName: branding.commercialName,
        ogImageUrl: meta.ogImageUrl ?? branding.ogImageUrl,
        canonical: meta.canonical,
      );
    }
    return const SizedBox.shrink();
  }
}
