/// Metadatos SEO de una página/ruta. Se pasan al
/// `MetaTagsSync` widget que los aplica al DOM en navegadores web.
class SeoMeta {
  const SeoMeta({
    required this.title,
    required this.description,
    this.ogImageUrl,
    this.canonical,
  });

  final String title;
  final String description;
  final String? ogImageUrl;
  final String? canonical;

  SeoMeta copyWith({
    String? title,
    String? description,
    String? ogImageUrl,
    String? canonical,
  }) {
    return SeoMeta(
      title: title ?? this.title,
      description: description ?? this.description,
      ogImageUrl: ogImageUrl ?? this.ogImageUrl,
      canonical: canonical ?? this.canonical,
    );
  }
}
