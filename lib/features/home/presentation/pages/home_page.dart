import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/features/subjects/presentation/pages/subjects_home.dart';

/// Dashboard de la zona privada (destino `/home` del shell).
///
/// **Fase 1b**: la Home muestra "Mis temarios" — el desplegable de temarios,
/// crear uno nuevo y subir material para que la IA lo procese. La Fase 2
/// ampliará esto al layout completo estilo NotebookLM (card central con 3
/// pestañas + recursos a la derecha).
///
/// Acepta `?subjectId=X` como deep-link desde `/mis-temarios` (Mi Material):
/// si viene el parametro, lo pasamos a `SubjectsHome` para que pre-seleccione
/// ese temario al montar.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final initialSubjectId =
        GoRouterState.of(context).uri.queryParameters['subjectId'];
    return SubjectsHome(initialSubjectId: initialSubjectId);
  }
}
