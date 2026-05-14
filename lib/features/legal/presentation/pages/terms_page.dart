import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/legal/presentation/widgets/legal_scaffold.dart';

/// Página `/terms` — Términos de Servicio.
///
/// El contenido es una plantilla concisa (ver aviso de borrador en
/// [LegalScaffold]); las cadenas viven en i18n para los 8 idiomas.
class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  /// Fecha de la última revisión del documento. Actualizar al cambiar el texto.
  static const String lastUpdated = '2026-05-14';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LegalScaffold(
      title: l.termsTitle,
      lastUpdated: lastUpdated,
      sections: [
        LegalSection(heading: l.termsS1Title, body: l.termsS1Body),
        LegalSection(heading: l.termsS2Title, body: l.termsS2Body),
        LegalSection(heading: l.termsS3Title, body: l.termsS3Body),
        LegalSection(heading: l.termsS4Title, body: l.termsS4Body),
        LegalSection(heading: l.termsS5Title, body: l.termsS5Body),
        LegalSection(heading: l.termsS6Title, body: l.termsS6Body),
      ],
    );
  }
}
