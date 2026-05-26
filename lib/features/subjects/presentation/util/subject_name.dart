// ============================================================================
// subject_name · saneado + limites para los nombres de temario (y la busqueda)
// ----------------------------------------------------------------------------
// Mismo criterio que los inputs del sistema de registro: limitar longitud y
// bloquear caracteres peligrosos (angulos `< >` que abren etiquetas HTML, y
// caracteres de control / saltos de linea). Se usa tanto en el campo de crear
// como en el de renombrar y en el buscador del selector de temarios.
// ============================================================================

import 'package:flutter/services.dart';

/// Longitud maxima de un nombre de temario.
const int kSubjectNameMaxLength = 120;

/// Longitud maxima del texto del buscador de temarios.
const int kSubjectSearchMaxLength = 60;

/// Angulos: apertura de etiquetas HTML. Se bloquean en vivo y al sanear.
final RegExp _angles = RegExp('[<>]');

/// `true` si el code unit es un caracter de control (U+0000..U+001F) o DEL
/// (U+007F). Saltos de linea y tabuladores entran aqui.
bool _isControl(int c) => c < 0x20 || c == 0x7f;

/// Formatters de entrada para nombres de temario y busquedas: bloquean en vivo
/// los angulos. La longitud se limita aparte con `maxLength` del campo y los
/// campos son de una sola linea, asi que los saltos no llegan a escribirse.
List<TextInputFormatter> subjectNameFormatters() => [
      FilteringTextInputFormatter.deny(_angles),
    ];

/// Sanea un nombre de temario: elimina caracteres de control y angulos,
/// colapsa espacios repetidos y recorta los extremos. Puede devolver cadena
/// vacia si el texto era invalido por completo (el caller debe tratarlo).
String sanitizeSubjectName(String raw) {
  final noControl =
      String.fromCharCodes(raw.runes.where((c) => !_isControl(c)));
  return noControl
      .replaceAll(_angles, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
