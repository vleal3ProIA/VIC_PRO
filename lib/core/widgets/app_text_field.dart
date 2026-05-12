import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';

/// Input estándar de la app.
///
/// Reglas obligatorias del proyecto:
/// - Cuando hay error: borde rojo + texto rojo debajo (en el [ErrorTextSlot]).
/// - El espacio del error siempre está reservado → la card no salta.
/// - Si [isPassword] = true, muestra un icono de ojo para alternar visibilidad.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    required this.label,
    super.key,
    this.hint,
    this.errorText,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.inputFormatters,
    this.maxLength,
    this.isPassword = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? errorText;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final bool isPassword;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final errorColor = context.colors.error;
    final borderRadius = BorderRadius.circular(12);

    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          obscureText: widget.isPassword && _obscure,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          inputFormatters: widget.inputFormatters,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            counterText: '',
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: hasError ? errorColor : null,
                  )
                : null,
            suffixIcon: widget.isPassword
                ? IconButton(
                    tooltip: _obscure ? 'Show' : 'Hide',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            labelStyle: hasError ? TextStyle(color: errorColor) : null,
            floatingLabelStyle:
                hasError ? TextStyle(color: errorColor) : null,
            enabledBorder: border(hasError ? errorColor : context.colors.outline),
            focusedBorder: border(
              hasError ? errorColor : context.colors.primary,
              width: 1.6,
            ),
            errorBorder: border(errorColor),
            focusedErrorBorder: border(errorColor, width: 1.6),
          ),
        ),
        ErrorTextSlot(message: widget.errorText),
      ],
    );
  }
}
