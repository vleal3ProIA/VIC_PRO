import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Input de N dígitos (por defecto 6) para códigos OTP.
///
/// Comportamiento:
/// - Cada caja avanza al siguiente foco al escribir un dígito.
/// - Backspace en una caja vacía vuelve al foco anterior y limpia.
/// - Pegar 6 dígitos (o más, se truncan) rellena automáticamente todas las
///   cajas. También funciona si el navegador pasa autofill.
/// - Llama `onCompleted(code)` cuando hay [length] dígitos. La pantalla
///   decide si dispara submit automático o no (recomendado: sí).
/// - `hasError` pinta el borde de rojo sin acoplar a un mensaje concreto.
class PinCodeInput extends StatefulWidget {
  const PinCodeInput({
    required this.onChanged,
    super.key,
    this.length = 6,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;
  final bool autofocus;

  @override
  State<PinCodeInput> createState() => _PinCodeInputState();
}

class _PinCodeInputState extends State<PinCodeInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _currentCode() => _controllers.map((c) => c.text).join();

  void _emitChange() {
    final code = _currentCode();
    widget.onChanged(code);
    if (code.length == widget.length) widget.onCompleted?.call(code);
  }

  /// Si el usuario pega varios dígitos en una caja, los reparte.
  void _handleInput(int index, String value) {
    final digits = value.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) {
      _controllers[index].text = '';
      _emitChange();
      return;
    }
    if (digits.length == 1) {
      _controllers[index].text = digits;
      _controllers[index].selection = TextSelection.collapsed(
        offset: digits.length,
      );
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
      _emitChange();
      return;
    }

    // Paste — distribuir.
    final usable = digits.substring(0, digits.length.clamp(0, widget.length));
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < usable.length ? usable[i] : '';
    }
    final lastFilled = usable.length - 1;
    if (lastFilled >= 0 && lastFilled < widget.length - 1) {
      _focusNodes[lastFilled + 1].requestFocus();
    } else {
      _focusNodes[widget.length - 1].unfocus();
    }
    _emitChange();
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
        _controllers[index - 1].text = '';
        _emitChange();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.hasError ? context.colors.error : context.colors.outline;
    final focusedColor =
        widget.hasError ? context.colors.error : context.colors.primary;

    OutlineInputBorder border(Color c, {double w = 1}) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        return SizedBox(
          width: 48,
          height: 56,
          child: Focus(
            onKeyEvent: (_, e) => _handleKey(i, e),
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              enabled: widget.enabled,
              autofocus: widget.autofocus && i == 0,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              maxLength: null,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                enabledBorder: border(borderColor),
                focusedBorder: border(focusedColor, w: 1.6),
                errorBorder: border(context.colors.error),
                focusedErrorBorder: border(context.colors.error, w: 1.6),
              ),
              onChanged: (v) => _handleInput(i, v),
            ),
          ),
        );
      }),
    );
  }
}
