import 'package:flutter/material.dart';

import 'package:myapp/core/constants/app_constants.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

/// Card de auth con tamaño FIJO.
///
/// El ancho es constante (`AppConstants.authCardWidth`). El alto se fija
/// pasando [reservedHeight]: la pantalla calcula cuánto necesita para
/// mostrar todos los inputs + slots de error reservados + botones, y lo
/// pasa una vez. Así, aparecer/desaparecer errores no mueve la card.
class AuthCard extends StatelessWidget {
  const AuthCard({
    required this.child,
    super.key,
    this.reservedHeight,
    this.title,
    this.subtitle,
    this.leading,
  });

  final Widget child;
  final double? reservedHeight;
  final String? title;
  final String? subtitle;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppConstants.authCardWidth,
            minHeight: reservedHeight ?? 0,
          ),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: context.colors.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    Center(child: leading),
                    const SizedBox(height: 16),
                  ],
                  if (title != null)
                    Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: context.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
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
