// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Definicion de una tab. `icon` es opcional -- las tabs solo-texto
/// son muy comunes en pantallas de settings.
class PremiumTabItem {
  const PremiumTabItem({
    required this.label,
    this.icon,
    this.badge,
  });

  /// Etiqueta de la tab. i18n-ready.
  final String label;

  /// Icono opcional a la izquierda (estilo MaterialPro Account
  /// Settings: Account / Notifications / Bills / Security).
  final IconData? icon;

  /// Badge opcional (texto corto, ej. "3" para notifications, "new").
  /// Si null no se renderiza.
  final String? badge;
}

/// Barra de tabs premium estilo Stripe / Linear: linea inferior bajo
/// la tab activa, animacion suave de 200ms entre cambios, texto en
/// bold cuando activa, color secundario cuando inactiva.
///
/// **Diferencia con `TabBar` de Material**:
/// - Indicador es solo una linea de 2px abajo, sin pill ni recuadro.
/// - El text de la tab cambia de weight (500 -> 700) al activarse,
///   no solo color.
/// - Padding propio: vertical 12px, horizontal 16px por tab.
/// - Sin ripple intenso de Material -- hover sutil estilo Stripe.
///
/// **Uso**:
/// ```dart
/// PremiumTabs(
///   tabs: [
///     PremiumTabItem(label: 'Account', icon: Icons.person_outline),
///     PremiumTabItem(label: 'Security', icon: Icons.lock_outline),
///   ],
///   currentIndex: _tab,
///   onChanged: (i) => setState(() => _tab = i),
/// )
/// ```
///
/// **Responsive**: si las tabs no caben en el ancho del padre, la barra
/// se vuelve scroll horizontal. Por defecto NO hay scroll para
/// preservar UX de "pestañas siempre visibles". Cambiar con
/// `scrollable: true`.
class PremiumTabs extends StatelessWidget {
  const PremiumTabs({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
    this.scrollable = false,
  });

  final List<PremiumTabItem> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  /// Si true, la barra es scrolleable horizontal (util para muchas tabs).
  /// Si false, las tabs comparten ancho equitativamente con `Expanded`.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabButton(
                item: tabs[i],
                active: i == currentIndex,
                onTap: () => onChanged(i),
                scheme: scheme,
              ),
          ],
        ),
      );
    }

    // Modo no scrollable: equitativo via Row + Expanded.
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _TabButton(
                item: tabs[i],
                active: i == currentIndex,
                onTap: () => onChanged(i),
                scheme: scheme,
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.item,
    required this.active,
    required this.onTap,
    required this.scheme,
  });

  final PremiumTabItem item;
  final bool active;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? widget.scheme.primary
        : _hovered
            ? widget.scheme.onSurface
            : widget.scheme.onSurfaceVariant;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.item.icon != null) ...[
                    Icon(widget.item.icon, size: 16, color: color),
                    const SizedBox(width: 8),
                  ],
                  AnimatedDefaultTextStyle(
                    duration: AppDurations.fast,
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight:
                          widget.active ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                    child: Text(widget.item.label),
                  ),
                  if (widget.item.badge != null) ...[
                    const SizedBox(width: 8),
                    _Badge(
                      label: widget.item.badge!,
                      active: widget.active,
                      scheme: widget.scheme,
                    ),
                  ],
                ],
              ),
            ),
            // Indicador inferior animado (linea 2px primary). En tabs
            // inactivas el indicador es transparente para mantener
            // alineacion vertical.
            AnimatedContainer(
              duration: AppDurations.medium,
              curve: Curves.easeOutCubic,
              height: 2,
              decoration: BoxDecoration(
                color:
                    widget.active ? widget.scheme.primary : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.active,
    required this.scheme,
  });

  final String label;
  final bool active;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.brPill,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.3,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
