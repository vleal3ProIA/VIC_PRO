import 'package:flutter/material.dart';

/// Dashboard de la zona privada (destino `/home` del shell).
///
/// **Rediseño (Fase 1)**: por ahora la Home queda intencionalmente EN BLANCO.
/// Su contenido se definirá más adelante. El cromo (header + sidebar) lo
/// aporta `PrivateShell`; aquí solo devolvemos un lienzo vacío.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
