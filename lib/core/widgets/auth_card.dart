import 'package:flutter/material.dart';

import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Card de auth con tamaño FIJO y estética Premium (Fase B1).
///
/// El ancho es constante (`AppConstants.authCardWidth`). El alto se fija
/// pasando [reservedHeight]: la pantalla calcula cuánto necesita para
/// mostrar todos los inputs + slots de error reservados + botones, y lo
/// pasa una vez. Así, aparecer/desaparecer errores no mueve la card
/// (regla "cards fijas" del proyecto).
///
/// **Premium UI**: en vez del `Card` plano de Material (elevation 0),
/// usamos un contenedor con sombra suave (`AppShadows.card`), border
/// sutil y fondo `surface`, consistente con `PremiumCard` del resto de
/// la app.
///
/// **Leading**: dos formas de poner el icono de cabecera:
///   - [icon] (IconData): renderiza un badge redondeado tintado (look
///     Premium, recomendado).
///   - [leading] (Widget): un widget custom (legacy / casos especiales).
/// Si se pasan ambos, gana [leading].
class AuthCard extends StatelessWidget {
  const AuthCard({
    required this.child,
    super.key,
    this.reservedHeight,
    this.title,
    this.subtitle,
    this.leading,
    this.icon,
    this.iconColor,
  });

  final Widget child;
  final double? reservedHeight;
  final String? title;
  final String? subtitle;

  /// Widget custom de cabecera. Tiene prioridad sobre [icon].
  final Widget? leading;

  /// Premium: si se pasa (y no hay [leading]), renderiza un badge
  /// redondeado tintado con este icono centrado arriba.
  final IconData? icon;

  /// Color del badge de [icon]. Default: `primary`.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final headerWidget = leading ??
        (icon != null
            ? _AuthIconBadge(icon: icon!, color: iconColor ?? scheme.primary)
            : null);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppConstants.authCardWidth,
            minHeight: reservedHeight ?? 0,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: AppRadii.brLg,
              border: Border.all(
                color: isDark
                    ? scheme.outline.withValues(alpha: 0.16)
                    : scheme.outline.withValues(alpha: 0.10),
              ),
              boxShadow: AppShadows.card(theme.brightness),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (headerWidget != null) ...[
                    Center(child: headerWidget),
                    const SizedBox(height: 20),
                  ],
                  if (title != null)
                    Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (title != null || subtitle != null)
                    const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Badge redondeado tintado para el icono de cabecera de [AuthCard].
/// Mismo lenguaje visual que los tiles de iconos del panel admin
/// (tile coloreado con el color base a baja opacidad).
class _AuthIconBadge extends StatelessWidget {
  const _AuthIconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.brMd,
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
}
