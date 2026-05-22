import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Barra de paginación reutilizable: « Anterior · Página X de Y · Siguiente ».
///
/// Paginación **client-side**: el caller ya tiene toda la lista cargada,
/// la corta en páginas y solo nos pasa `currentPage` (0-indexed) + el total
/// de páginas para pintar los controles. No hace fetch ni conoce los datos.
///
/// Se oculta sola (devuelve `SizedBox.shrink`) cuando solo hay una página,
/// para no añadir ruido cuando no hace falta paginar.
class AppPaginationBar extends StatelessWidget {
  const AppPaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  /// Página actual, **0-indexed** (la UI muestra `currentPage + 1`).
  final int currentPage;

  /// Número total de páginas (>= 1).
  final int totalPages;

  /// Llamado al pulsar «Anterior». Se ignora si ya estamos en la primera.
  final VoidCallback onPrevious;

  /// Llamado al pulsar «Siguiente». Se ignora si ya estamos en la última.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final l = context.l10n;
    final canPrev = currentPage > 0;
    final canNext = currentPage < totalPages - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: l.paginationPrevious,
            icon: const Icon(Icons.chevron_left),
            onPressed: canPrev ? onPrevious : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l.paginationPageOf(currentPage + 1, totalPages),
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: l.paginationNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: canNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}
