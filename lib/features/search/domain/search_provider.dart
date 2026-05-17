import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import 'search_result.dart';

/// Contrato que toda fuente de resultados del palette Cmd+K debe
/// implementar. Los providers se registran globalmente en
/// `searchRegistryProvider` y se ejecutan en paralelo cada vez que el
/// user escribe una query.
///
/// **Diseño**:
/// - El provider recibe el [Ref] de Riverpod en [search] para que pueda
///   leer otros providers (auth, profile, planes…) y devolver
///   resultados contextuales.
/// - La query llega ya en minúsculas y trimmed para que cada provider
///   no tenga que repetir esa normalización.
/// - Si la query está vacía, [search] devuelve los "resultados por
///   defecto" del provider (ej. para Pages: las páginas principales
///   sin filtrar; para Recent Members: los últimos 5 que abriste).
///   Devuelve `[]` si no tiene sentido sin query.
abstract class SearchProvider {
  const SearchProvider();

  /// Nombre interno (debug only). Útil cuando hay que entender por qué
  /// un resultado aparece o no.
  String get name;

  /// Devuelve los resultados que coinciden con [query]. Si [query] es
  /// vacía, devuelve los "defaults" del provider (típicamente los más
  /// usados / más recientes / siempre disponibles).
  ///
  /// La firma es síncrona: para providers que necesitan I/O (BD,
  /// network) cachear el listado en un Riverpod provider y leerlo aquí
  /// con `ref.read(...)`. Así el palette responde instantáneo y se
  /// invalida cuando los datos subyacentes cambien.
  ///
  /// [l10n] llega ya resuelto al locale actual para que los titles de
  /// los SearchResult estén traducidos sin necesidad de `BuildContext`.
  ///
  /// [ref] es `WidgetRef` (no `Ref`) porque el palette se construye en
  /// un `ConsumerWidget`. Esto evita la fricción de envolver providers
  /// dentro de providers — los SearchProvider pueden leer cualquier
  /// estado igual que un widget.
  List<SearchResult> search(WidgetRef ref, AppLocalizations l10n, String query);
}

/// Helper de matching fuzzy MUY simple: case-insensitive substring sobre
/// title + keywords. Suficiente para el 95% de casos. Si en el futuro
/// queremos algo más sofisticado (Fuse-style fuzzy, scoring por
/// posición del match, etc.), se cambia aquí en un sitio.
///
/// Devuelve `true` si [query] aparece en title o en alguna keyword.
/// Query vacía siempre matchea (defaults).
bool matchesQuery(SearchResult result, String query) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  if (result.title.toLowerCase().contains(q)) return true;
  if (result.subtitle?.toLowerCase().contains(q) ?? false) return true;
  for (final kw in result.keywords) {
    if (kw.toLowerCase().contains(q)) return true;
  }
  return false;
}
