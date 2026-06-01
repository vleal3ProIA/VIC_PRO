// ============================================================================
// core/util/backend_error.dart · Helper para no filtrar detalles a la UI
// ----------------------------------------------------------------------------
// Punto de entrada UNICO para mapear cualquier error proveniente del backend
// (Edge Functions, RPC, PostgrestException, SubjectsException, etc.) al
// MENSAJE GENERICO que ve el usuario final:
//
//   "Ha ocurrido un error, inténtelo de nuevo más tarde."
//
// Los detalles tecnicos (mensajes del proveedor IA, stacks, etc.) NUNCA salen
// del backend hacia el cliente: las Edge Functions los registran en la tabla
// `error_reports` y el cliente recibe solo `{ok:false, error_code:'generic_error',
// error_id:<uuid>}`. El admin puede abrir el error en /admin/errors.
//
// Por que el helper toma `Object? raw` sin usarlo? Para hacer EXPLICITO en cada
// callsite "que estamos tirando esta info a proposito". Si en el futuro
// queremos meter telemetria (capturar el codigo en analytics o adjuntar el
// `error_id` a un snackbar contextual), todos los callsites estan ya
// preparados sin tener que tocar nada.
// ============================================================================

import 'package:flutter/widgets.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Genericiza CUALQUIER error backend en el mensaje canonico.
///
/// **Usar SIEMPRE** para superficies que ve el usuario final:
///   - SnackBar / showSnack tras una invoke a EF que tira.
///   - AppErrorState en zonas controladas por el user (no zonas admin).
///   - Diálogos de error tras una acción que devolvió `ok:false`.
///
/// **NO usar** para:
///   - Errores de validación inline (form fields).
///   - Errores de auth con mensaje específico (login failed, etc.).
///   - Pantallas DEV detrás de flags.
///   - Pantallas /admin/* donde el detalle es deseable.
String mapBackendError(BuildContext context, Object? raw) {
  // El `raw` se ignora a proposito (defensive). El admin verá el detalle
  // tecnico en /admin/errors via `error_reports.error_message`.
  return context.l10n.errorGeneric;
}
