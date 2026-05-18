// ignore_for_file: always_put_required_named_parameters_first
// Ver razonamiento en premium_card.dart.

import 'package:flutter/material.dart';
import 'package:myapp/core/theme/app_tokens.dart';

/// Header consistente para todas las pages de la zona privada. Estilo
/// Stripe / Linear: titulo H1 muy bold + subtitulo gris + slot a la
/// derecha para acciones (botones, dropdown, KPIs compactos).
///
/// **Diferencia con `SectionHeader`** (Fase 1):
/// - `SectionHeader` es para sub-bloques dentro de una page ("Recent
///   activity", "Your invoices"). Texto mediano.
/// - `PageHeader` es para el titulo principal de la page entera
///   ("Account Settings", "Home"). Texto grande, mas spacing.
///
/// **Breadcrumb opcional**: lista de pares (label, ruta). Solo se
/// muestra si hay >= 1 elemento.
///
/// **Responsive**: en mobile (width < 480) los actions trailing se
/// envuelven a una segunda linea bajo el titulo. En desktop ocupan
/// la derecha en horizontal.
///
/// **Uso**:
/// ```dart
/// PageHeader(
///   title: 'Account Settings',
///   subtitle: 'Manage your profile, security and preferences.',
///   breadcrumb: [
///     BreadcrumbItem(label: 'Home', onTap: () => context.goNamed('home')),
///     BreadcrumbItem(label: 'Settings'),
///   ],
///   actions: [
///     PremiumButton(label: 'Save changes', onPressed: _save),
///   ],
/// )
/// ```
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.breadcrumb,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  });

  /// Titulo principal. H1 estilo Stripe: weight 800, letter-spacing -0.5.
  final String title;

  /// Subtitulo descriptivo opcional. Color secundario.
  final String? subtitle;

  /// Breadcrumb opcional (lista de items). Se renderiza arriba del
  /// titulo, fontSize 13, color secundario, separadores con chevron.
  final List<BreadcrumbItem>? breadcrumb;

  /// Acciones a la derecha (botones, dropdowns). En mobile se wrapean
  /// abajo. Lista vacia o null = sin acciones.
  final List<Widget>? actions;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hasBreadcrumb = breadcrumb != null && breadcrumb!.isNotEmpty;
    final hasActions = actions != null && actions!.isNotEmpty;

    final titleWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasBreadcrumb) ...[
          _Breadcrumb(items: breadcrumb!),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            height: 1.15,
            color: scheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Mobile: stack vertical (titulo arriba, acciones abajo).
          final isMobile = constraints.maxWidth < 480;
          if (!hasActions || isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleWidget,
                if (hasActions) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: actions!,
                  ),
                ],
              ],
            );
          }
          // Desktop: titulo a la izq, acciones a la derecha.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleWidget),
              const SizedBox(width: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions!,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Item de breadcrumb. Si `onTap` es null se renderiza como texto
/// (ultima ruta, no clickable). Si tiene onTap se renderiza como
/// link estilizado.
class BreadcrumbItem {
  const BreadcrumbItem({
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.items});
  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final isLast = i == items.length - 1;

      if (item.onTap != null && !isLast) {
        children.add(
          InkWell(
            onTap: item.onTap,
            borderRadius: AppRadii.brSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 2,
              ),
              child: Text(
                item.label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      } else {
        // Ultimo elemento o sin tap: solo texto, mas visible.
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              item.label,
              style: TextStyle(
                color: isLast ? scheme.onSurface : scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        );
      }

      if (!isLast) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        );
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}
