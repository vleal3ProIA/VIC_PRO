import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/widgets/markdown_text.dart';

import '../../helpers/pump_widget.dart';

void main() {
  testWidgets('renderiza encabezado, viñeta y negrita sin mostrar los símbolos',
      (tester) async {
    await pumpForTest(
      tester,
      child: const MarkdownText(
        '## Título\n\n'
        '- primer punto\n'
        'Texto con **negrita** dentro.',
      ),
    );

    // El contenido limpio aparece (encabezado/párrafo van en Text.rich).
    expect(find.text('Título', findRichText: true), findsOneWidget);
    expect(find.text('primer punto', findRichText: true), findsOneWidget);
    // Los marcadores Markdown NO se muestran como texto literal.
    expect(find.textContaining('##', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    // La viñeta se dibuja como marcador (Text plano).
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('una lista numerada conserva su número', (tester) async {
    await pumpForTest(
      tester,
      child: const MarkdownText('1. primero\n2. segundo'),
    );

    expect(find.text('1.'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('primero', findRichText: true), findsOneWidget);
    expect(find.text('segundo', findRichText: true), findsOneWidget);
  });
}
