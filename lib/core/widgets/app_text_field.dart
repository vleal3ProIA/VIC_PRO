import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/error_text_slot.dart';

/// Input estándar de la app — estética **Premium** (Stripe / Linear).
///
/// Reglas obligatorias del proyecto que este widget respeta:
/// - Cuando hay error: borde rojo + label rojo + texto rojo debajo (en el
///   [ErrorTextSlot]).
/// - El espacio del error SIEMPRE está reservado → la card no salta.
/// - Si [isPassword] = true, muestra un icono de ojo para alternar visibilidad.
///
/// **Diseño** (vs el `TextField` Material plano anterior):
/// - Label ENCIMA del campo (no floating): `labelLarge` en w600.
/// - Campo con relleno sutil + borde 1px; al enfocar, borde `primary` +
///   "focus ring" suave (sombra difusa de color primary).
/// - Esquinas redondeadas (`AppRadii.md` = 12).
/// - Icono prefix teñido según estado (normal / focus / error).
/// - Transición animada (`AppDurations.fast`) entre estados.
///
/// La API pública es idéntica a la versión anterior, así que todos los
/// formularios que ya lo usan se actualizan sin tocarse. Internamente sigue
/// montando un [TextField] (no [TextFormField]) para no alterar los tests de
/// widget que cuentan `find.byType(TextField)`.
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
  late FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    // Solo lo destruimos si lo creamos nosotros.
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final enabled = widget.enabled;

    // Color del borde según estado (error > focus > normal > disabled).
    final borderColor = !enabled
        ? scheme.outline.withValues(alpha: 0.08)
        : hasError
            ? scheme.error
            : _focused
                ? scheme.primary
                : scheme.outline.withValues(alpha: isDark ? 0.28 : 0.20);

    // Relleno sutil; al enfocar "sube" a surface puro para dar sensación
    // de elevación.
    final fillColor = !enabled
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.30)
        : _focused
            ? scheme.surface
            : scheme.surfaceContainerHighest
                .withValues(alpha: isDark ? 0.40 : 0.55);

    final iconColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.30)
        : hasError
            ? scheme.error
            : _focused
                ? scheme.primary
                : scheme.onSurfaceVariant;

    final labelColor = !enabled
        ? scheme.onSurface.withValues(alpha: 0.45)
        : hasError
            ? scheme.error
            : scheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label encima del campo.
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            widget.label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        // Campo.
        AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: AppRadii.brMd,
            border: Border.all(
              color: borderColor,
              width: _focused || hasError ? 1.5 : 1,
            ),
            boxShadow: _focused && !hasError
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12),
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            enabled: enabled,
            obscureText: widget.isPassword && _obscure,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            inputFormatters: widget.inputFormatters,
            maxLength: widget.maxLength,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.40),
              ),
              counterText: '',
              isDense: true,
              filled: false,
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, size: 20, color: iconColor)
                  : null,
              suffixIcon: widget.isPassword
                  ? IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      iconSize: 20,
                      color: iconColor,
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    )
                  : null,
              // El contenedor ya pinta borde/fondo: el TextField va "desnudo".
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        ErrorTextSlot(message: widget.errorText),
      ],
    );
  }
}
