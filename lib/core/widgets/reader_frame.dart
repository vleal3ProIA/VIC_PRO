import 'package:flutter/material.dart';

/// Marco de LECTURA: envuelve un contenido textual (Markdown o plano) con la
/// tipografía propia de un documento: scrollbar, padding vertical razonable y
/// padding lateral MUY pequeño para que el texto LLENE la columna (sin huecos
/// a los lados, como en el documento original). No usa ancho máximo ni centra:
/// la columna que contiene el ReaderFrame ya marca el ancho efectivo.
class ReaderFrame extends StatelessWidget {
  const ReaderFrame({
    required this.child,
    super.key,
    this.horizontalPadding = 16,
    this.verticalPadding = 16,
  });

  final Widget child;
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: child,
      ),
    );
  }
}
