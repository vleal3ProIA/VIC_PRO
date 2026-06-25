// ============================================================================
// billing · plan gates
// ----------------------------------------------------------------------------
// Helpers para condicionar acciones del Panel y de Mi Material en función del
// plan del usuario. El plan top (con generación "de todo el temario") se
// llama `max` (slug en la tabla `plans`).
//
// Filosofía: en planes inferiores, los botones de "Generar (todo el temario)"
// SIGUEN VISIBLES pero al pulsarlos se muestra un modal "Disponible solo en
// plan Max" con CTA al checkout. Así el usuario descubre la feature y se le
// invita al upgrade. Para generar de UNA sección concreta (modo de estudio
// punto-por-punto) NO hay gate — todos los planes pueden.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/observability/analytics_service.dart';
import 'package:myapp/core/router/route_names.dart';

import 'billing_providers.dart';

/// Slug del plan top en la tabla `plans`.
const String kMaxPlanSlug = 'max';

/// `true` si el plan vigente del tenant actual es el plan Max (slug `max`).
/// Si no hay plan resuelto aún (loading o usuario sin suscripción), devuelve
/// `false` por seguridad — los gates bloquean por defecto.
final isMaxPlanProvider = Provider<bool>((ref) {
  final plan = ref.watch(currentPlanProvider).valueOrNull;
  return plan?.slug == kMaxPlanSlug;
});

/// Modal "Esta función requiere plan Max". Devuelve `true` si el usuario
/// pulsa el CTA (que navega a `/billing/plans`), `null` o `false` si cierra.
///
/// Llámalo cuando el usuario, en un plan menor a Max, intente disparar una
/// acción de generación "de todo el temario" (notas, flashcards, quiz, test,
/// tf, essay). NO lo llames para generación por sección — esa no tiene gate.
///
/// Tracking: registra dos eventos en analytics:
///   - `max_gate_shown`: cada vez que el modal se muestra (medir intención).
///   - `max_gate_cta_clicked`: cuando el usuario pulsa "Ver plan Max"
///     (medir conversion del upsell).
/// El parámetro [source] etiqueta el origen del gate (ej. `mock_test_all`,
/// `tf_panel`, `essay_panel`, `mock_my_material`).
Future<bool?> showMaxOnlyDialog(
  BuildContext context, {
  String source = 'unknown',
}) {
  final l = context.l10n;
  // Tracking del impression: el gate apareció.
  final container = ProviderScope.containerOf(context, listen: false);
  container
      .read(analyticsServiceProvider)
      .trackSync('max_gate_shown', properties: {'source': source});
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.workspace_premium_outlined,
          size: 32, color: ctx.colors.primary,),
      title: Text(l.studyMaxOnlyTitle),
      content: Text(l.studyMaxOnlyBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.actionCancel),
        ),
        FilledButton.icon(
          onPressed: () {
            // Tracking del click: conversion potencial.
            container
                .read(analyticsServiceProvider)
                .trackSync(
              'max_gate_cta_clicked',
              properties: {'source': source},
            );
            Navigator.of(ctx).pop(true);
            ctx.goNamed(RouteNames.plans);
          },
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: Text(l.studyMaxOnlyAction),
        ),
      ],
    ),
  );
}
