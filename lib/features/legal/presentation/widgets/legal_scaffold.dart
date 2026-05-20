import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/nav_helpers.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/features/welcome/presentation/widgets/top_bar.dart';

/// Una sección de un documento legal: un encabezado y un cuerpo.
class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

/// Layout reutilizable para páginas legales (`/terms`, `/privacy`).
///
/// Documento estático, desplazable, con ancho máximo legible. Muestra arriba
/// un aviso de "borrador pendiente de revisión legal" para ser honestos en
/// una auditoría: el contenido es una plantilla, no asesoramiento jurídico.
class LegalScaffold extends StatelessWidget {
  const LegalScaffold({
    required this.title,
    required this.lastUpdated,
    required this.sections,
    super.key,
  });

  final String title;

  /// Fecha legible de última actualización (p. ej. `2026-05-14`).
  final String lastUpdated;

  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const PublicTopBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l.legalLastUpdated(lastUpdated),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DraftNotice(message: l.legalDraftNotice),
                  const SizedBox(height: 24),
                  for (final section in sections) ...[
                    Text(
                      section.heading,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      section.body,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    child: TextButton.icon(
                      onPressed: () => context.popOrGo(RouteNames.welcome),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: Text(l.actionGoHome),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftNotice extends StatelessWidget {
  const _DraftNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
