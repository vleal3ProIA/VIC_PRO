import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/theme/app_tokens.dart';
import 'package:myapp/core/widgets/premium/premium.dart';

/// Un elemento del menú izquierdo del [SettingsMasterDetail].
class SettingsDetailItem {
  const SettingsDetailItem({
    required this.icon,
    required this.label,
    required this.builder,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Construye el contenido del panel derecho para este elemento.
  final WidgetBuilder builder;

  /// Resalta en color de error (p. ej. "Eliminar cuenta").
  final bool destructive;
}

/// Layout master-detail para las secciones de Ajustes (Workspace/Facturación/
/// Seguridad) en pantallas anchas: un card a la izquierda con el menú de la
/// sección y, al seleccionar, un card a la derecha con el contenido.
class SettingsMasterDetail extends StatefulWidget {
  const SettingsMasterDetail({required this.items, super.key});

  final List<SettingsDetailItem> items;

  @override
  State<SettingsMasterDetail> createState() => _SettingsMasterDetailState();
}

class _SettingsMasterDetailState extends State<SettingsMasterDetail> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final sel = _selected.clamp(0, widget.items.length - 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Menú de la sección ───
        SizedBox(
          width: 240,
          child: PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.items.length; i++)
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      widget.items[i].icon,
                      size: 20,
                      color: widget.items[i].destructive ? scheme.error : null,
                    ),
                    title: Text(
                      widget.items[i].label,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color:
                            widget.items[i].destructive ? scheme.error : null,
                        fontWeight:
                            i == sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    selected: i == sel,
                    selectedTileColor: scheme.primary.withValues(alpha: 0.10),
                    selectedColor: scheme.primary,
                    onTap: () => setState(() => _selected = i),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        // ─── Contenido del elemento seleccionado ───
        Expanded(
          child: PremiumCard(
            child: KeyedSubtree(
              key: ValueKey(sel),
              child: widget.items[sel].builder(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Panel derecho para un elemento cuyo contenido es un flujo de pantalla
/// completa (p. ej. el asistente de MFA): muestra icono + descripción + un
/// botón que abre la ruta correspondiente.
class SettingsOpenFullScreen extends StatelessWidget {
  const SettingsOpenFullScreen({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.routeName,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          description,
          style: context.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => context.pushNamed(routeName),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(buttonLabel),
        ),
      ],
    );
  }
}
