import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Anuncia mensajes a lectores de pantalla (NVDA, JAWS, VoiceOver…) sin
/// necesidad de mover el foco. Wrap delgado sobre
/// `SemanticsService.sendAnnouncement()` de Flutter.
///
/// **Cuándo usarlo**:
/// - Tras una acción que tiene éxito o falla y el usuario debe saberlo,
///   pero el cambio visual no es suficiente (snackbar fugaz, badge que
///   cambia de número, etc.). Sin announce, el lector se queda callado.
/// - Cuando el resultado de una operación asíncrona aparece pero el
///   foco no se mueve (por ejemplo: lista que se actualiza tras crear
///   un cupón).
///
/// **Cuándo NO usarlo**:
/// - Cuando ya navegas a otra pantalla (el lector lee la nueva
///   automáticamente).
/// - Cuando muestras un dialog (también se lee automáticamente).
///
/// Implementación: en web Flutter inyecta una `aria-live` region en el
/// DOM que los screen readers ya conocen; en mobile usa TalkBack
/// (Android) / VoiceOver (iOS) APIs nativas.
///
/// `context` es **obligatorio** porque la API moderna de Flutter
/// (`sendAnnouncement`) necesita el `FlutterView` al que dirigir el
/// evento (Flutter 3.35+ soporta múltiples ventanas).
class A11yAnnouncer {
  A11yAnnouncer._();

  /// Anuncio "polite": el lector lo dice cuando termina lo que estaba
  /// leyendo (no interrumpe). Para confirmaciones y feedback normal.
  static void announce(BuildContext context, String message) {
    if (message.isEmpty) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    SemanticsService.sendAnnouncement(
      view,
      message,
      Directionality.of(context),
    );
  }

  /// Anuncio "assertive": el lector interrumpe lo que estaba diciendo.
  /// Usar SOLO para errores y avisos críticos.
  static void announceAssertive(BuildContext context, String message) {
    if (message.isEmpty) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    SemanticsService.sendAnnouncement(
      view,
      message,
      Directionality.of(context),
      assertiveness: Assertiveness.assertive,
    );
  }
}
