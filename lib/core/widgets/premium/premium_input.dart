// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Text field premium estilo Stripe / Linear: label encima del input
/// (no floating tipo Material), border sutil, focus ring discreto,
/// error state inline debajo.
///
/// **Diferencias vs `TextFormField` Material default**:
/// - Label arriba en text-sm bold, no floating sobre el input.
/// - Border 1px en lugar de underline.
/// - Focus state: border color primary + shadow ring sutil.
/// - Error state: border rojo + texto error compacto debajo.
/// - Esquinas redondeadas (`AppRadii.sm` = 6px).
/// - Padding interno mayor (vertical 12, horizontal 14).
///
/// **Iconos**: opcional `prefixIcon` y `suffixIcon`. El suffix puede
/// ser interactivo (ej. boton de visibility toggle en passwords).
///
/// **Multi-line**: pasar `maxLines: > 1` o `null` para textarea
/// auto-expandible.
///
/// **Uso tipico**:
/// ```dart
/// PremiumInput(
///   label: 'Email',
///   controller: _emailController,
///   keyboardType: TextInputType.emailAddress,
///   prefixIcon: Icons.alternate_email_rounded,
///   hintText: 'you@example.com',
///   errorText: state.emailError,
///   validator: (v) => v == null || v.isEmpty ? 'Required' : null,
/// )
/// ```
class PremiumInput extends StatefulWidget {
  const PremiumInput({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.autofillHints,
    this.focusNode,
  });

  /// Label arriba del campo. Bold, color onSurface.
  final String label;

  final TextEditingController? controller;

  /// Placeholder dentro del campo cuando esta vacio.
  final String? hintText;

  /// Texto de ayuda debajo (color onSurfaceVariant).
  final String? helperText;

  /// Texto de error debajo (color error). Si no null, el border se
  /// pinta rojo.
  final String? errorText;

  final IconData? prefixIcon;
  final IconData? suffixIcon;

  /// Si suffixIcon es interactivo (ej. toggle visibility).
  final VoidCallback? onSuffixTap;

  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final List<String>? autofillHints;
  final FocusNode? focusNode;

  @override
  State<PremiumInput> createState() => _PremiumInputState();
}

class _PremiumInputState extends State<PremiumInput> {
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
    // Solo dispose si lo creamos nosotros.
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    // Colores del border segun estado:
    // - error: rojo
    // - focus: primary
    // - normal: outline sutil
    // - disabled: aun mas sutil
    final borderColor = !widget.enabled
        ? scheme.outline.withValues(alpha: 0.08)
        : hasError
            ? scheme.error
            : _focused
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.20);

    final iconColor = !widget.enabled
        ? scheme.onSurface.withValues(alpha: 0.30)
        : hasError
            ? scheme.error
            : _focused
                ? scheme.primary
                : scheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label.
        Text(
          widget.label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: widget.enabled
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 6),
        // Field.
        AnimatedContainer(
          duration: AppDurations.fast,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            // Campo "filled" suave en reposo (look moderno 2026); al enfocar
            // sube a `surface` limpio con el anillo de foco. Disabled queda
            // más apagado.
            color: !widget.enabled
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : _focused
                    ? scheme.surface
                    : scheme.surfaceContainerHighest
                        .withValues(alpha: isDark ? 0.45 : 0.7),
            borderRadius: AppRadii.brMd,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: _focused && !hasError
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.10),
                      blurRadius: 0,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            maxLength: widget.maxLength,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onSubmitted,
            validator: widget.validator,
            autofillHints: widget.autofillHints,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 12, right: 4),
                      child:
                          Icon(widget.prefixIcon, size: 18, color: iconColor),
                    )
                  : null,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              suffixIcon: widget.suffixIcon != null
                  ? widget.onSuffixTap != null
                      ? IconButton(
                          icon: Icon(
                            widget.suffixIcon,
                            size: 18,
                            color: iconColor,
                          ),
                          onPressed: widget.onSuffixTap,
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 12, left: 4),
                          child: Icon(
                            widget.suffixIcon,
                            size: 18,
                            color: iconColor,
                          ),
                        )
                  : null,
              border: InputBorder.none,
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              isDense: true,
            ),
          ),
        ),
        // Helper o error text debajo.
        if (hasError) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.error,
            ),
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helperText!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
