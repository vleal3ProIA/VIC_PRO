// ============================================================================
// subjects · Lectura en voz alta (TTS) — Web Speech API (Fase 3)
// ----------------------------------------------------------------------------
// Usa `SpeechSynthesis` del navegador para leer el contenido generado
// (Explicado/Resumen/Guía). Sin backend ni dependencias. Solo web.
// ============================================================================

import 'package:web/web.dart' as web;

/// Limpia marcas Markdown básicas para que la voz no lea los símbolos.
String _plain(String text) => text
    .replaceAll(RegExp(r'\[\[|\]\]'), '')
    .replaceAll(RegExp('[#*_`>]'), '')
    .trim();

/// Lee [text] en voz alta. [lang] es un código BCP-47 ('es', 'es-ES', ...)
/// para elegir la voz. Cancela cualquier lectura en curso antes de empezar.
void ttsSpeak(String text, {String? lang}) {
  final clean = _plain(text);
  if (clean.isEmpty) return;
  final synth = web.window.speechSynthesis..cancel();
  final u = web.SpeechSynthesisUtterance(clean);
  if (lang != null && lang.isNotEmpty) u.lang = lang;
  synth.speak(u);
}

/// Detiene la lectura en curso.
void ttsStop() {
  web.window.speechSynthesis.cancel();
}
