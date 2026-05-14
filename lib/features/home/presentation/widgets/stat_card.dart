import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Tarjeta KPI reutilizable del dashboard: icono + etiqueta + valor.
///
/// Pensada para ir dentro de un `Wrap`/`GridView` — tiene ancho fijo y se
/// adapta en alto al contenido.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Color de acento del icono (por defecto, el primary del tema).
  final Color? accent;

  /// Si se indica, la tarjeta es pulsable.
  final VoidCallback? onTap;

  static const double width = 220;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? context.colors.primary;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: color),
                    ),
                    const Spacer(),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: context.colors.onSurfaceVariant,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
