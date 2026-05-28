import 'package:flutter/material.dart';

/// Marco de LECTURA: envuelve un contenido textual (Markdown o plano) con la
/// tipografía propia de un documento: márgenes laterales y verticales cómodos,
/// ancho máximo legible (~760 px — más allá el ojo se cansa al saltar de línea)
/// y scroll con barra. Se usa en el panel de estudio para el "Original" del
/// nodo raíz, el de cada sección y las vistas Explicado/Resumen.
class ReaderFrame extends StatelessWidget {
  const ReaderFrame({
    required this.child,
    super.key,
    this.maxWidth = 880,
    this.horizontalPadding = 12,
    this.verticalPadding = 20,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: verticalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
