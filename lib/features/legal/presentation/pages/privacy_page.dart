import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/features/legal/presentation/widgets/legal_scaffold.dart';

/// Página `/privacy` — Política de Privacidad.
///
/// El contenido es una plantilla concisa orientada a GDPR (ver aviso de
/// borrador en [LegalScaffold]); las cadenas viven en i18n para los 8 idiomas.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  /// Fecha de la última revisión del documento. Actualizar al cambiar el texto.
  static const String lastUpdated = '2026-05-14';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return LegalScaffold(
      title: l.privacyTitle,
      lastUpdated: lastUpdated,
      sections: [
        LegalSection(heading: l.privacyS1Title, body: l.privacyS1Body),
        LegalSection(heading: l.privacyS2Title, body: l.privacyS2Body),
        LegalSection(heading: l.privacyS3Title, body: l.privacyS3Body),
        LegalSection(heading: l.privacyS4Title, body: l.privacyS4Body),
        LegalSection(heading: l.privacyS5Title, body: l.privacyS5Body),
        LegalSection(heading: l.privacyS6Title, body: l.privacyS6Body),
      ],
    );
  }
}
