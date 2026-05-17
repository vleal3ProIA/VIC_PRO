import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';

import '../domain/search_provider.dart';
import '../domain/search_result.dart';
import 'built_in_providers.dart';

/// Registro de todas las `SearchProvider` activas. La lista se compone
/// aquí (no descubrimiento mágico) — para añadir un provider nuevo de
/// una feature, lo añades a la lista y listo.
///
/// En el futuro, si queremos plugins externos (apps custom de tenant),
/// se puede meter un `register()` mutable detrás de un Notifier que la
/// app expone como API pública.
final searchRegistryProvider = Provider<SearchRegistry>((ref) {
  return const SearchRegistry([
    PagesSearchProvider(),
    ActionsSearchProvider(),
  ]);
});

/// Ejecuta una búsqueda contra todos los providers en paralelo y
/// devuelve los resultados combinados, ordenados por:
///   1. Sección (alfabético, primero la sección del provider que tenga
///      el resultado de mayor prioridad).
///   2. Prioridad desc.
///   3. Título alfabético.
class SearchRegistry {
  const SearchRegistry(this._providers);

  final List<SearchProvider> _providers;

  /// Ejecuta todos los providers con [query] (puede ser vacía → defaults
  /// del provider). Devuelve los resultados combinados ya ordenados.
  /// [l10n] se pasa a cada provider para que los titles vengan
  /// localizados.
  List<SearchResult> search(WidgetRef ref, AppLocalizations l10n, String query) {
    final normalized = query.trim().toLowerCase();
    final all = <SearchResult>[];
    for (final p in _providers) {
      all.addAll(p.search(ref, l10n, normalized));
    }
    all.sort((a, b) {
      final s = a.section.compareTo(b.section);
      if (s != 0) return s;
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return all;
  }

  /// Agrupa una lista plana de resultados por sección, preservando el
  /// orden interno. Usado por la UI del palette para pintar headers.
  Map<String, List<SearchResult>> groupBySection(List<SearchResult> results) {
    final map = <String, List<SearchResult>>{};
    for (final r in results) {
      map.putIfAbsent(r.section, () => []).add(r);
    }
    return map;
  }
}
