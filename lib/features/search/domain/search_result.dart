import 'package:flutter/widgets.dart';

/// Un resultado de búsqueda en el palette Cmd+K. Es un VO sin estado —
/// cada provider construye y devuelve estos cuando se le pide
/// `search(query)`.
///
/// El callback [onSelect] encapsula la acción a ejecutar cuando el user
/// pulsa Enter o hace tap. Recibe el `BuildContext` actual del palette
/// para poder navegar, abrir un dialog, leer providers, etc.
@immutable
class SearchResult {
  const SearchResult({
    required this.id,
    required this.title,
    required this.section,
    required this.icon,
    required this.onSelect,
    this.subtitle,
    this.keywords = const [],
    this.priority = 50,
  });

  /// Identificador único estable — usado como key de widget y para
  /// dedupe si dos providers devuelven lo mismo.
  final String id;

  /// Texto principal del resultado.
  final String title;

  /// Sección/categoría visible: "Pages", "Actions", "Members", etc.
  /// El palette agrupa resultados por esta clave.
  final String section;

  /// Texto secundario opcional bajo el título (ej. "Manage your team").
  final String? subtitle;

  /// Icono mostrado a la izquierda del resultado.
  final IconData icon;

  /// Palabras clave adicionales para el matching, además del [title].
  /// Útil para sinónimos: una página "Plans" puede tener keywords
  /// ["pricing", "subscription", "billing"] para que se encuentre con
  /// cualquiera de esos términos.
  final List<String> keywords;

  /// Prioridad de orden (0..100). Mayor = más arriba en los resultados.
  /// Default 50. Una página actual o una acción contextual debería
  /// subir a 80-90.
  final int priority;

  /// Callback ejecutado al seleccionar. Debe cerrar el palette
  /// internamente si la acción navega (la mayoría lo hacen).
  final void Function(BuildContext context) onSelect;
}
