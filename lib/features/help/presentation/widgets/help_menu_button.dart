import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/changelog_providers.dart';
import 'keyboard_shortcuts_dialog.dart';

/// Botón "?" en el AppBar que despliega un menú con:
///   - "What's new" → `/changelog` (con badge rojo si hay novedades)
///   - "Keyboard shortcuts" → modal con la lista
///   - "Documentation" → URL externa configurada en .env
///   - "Contact support" → mailto con asunto prefijado
///
/// El badge rojo se alimenta de [hasUnseenChangelogProvider]; al
/// entrar en `/changelog` se marca como visto y desaparece.
class HelpMenuButton extends ConsumerWidget {
  const HelpMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final hasUnseen = ref.watch(hasUnseenChangelogProvider).valueOrNull
        ?? false;
    final docsUrl = dotenv.maybeGet('DOCS_URL');
    final supportEmail = dotenv.maybeGet('SUPPORT_EMAIL');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        PopupMenuButton<_HelpAction>(
          tooltip: l.helpMenuTooltip,
          icon: const Icon(Icons.help_outline),
          onSelected: (action) async {
            switch (action) {
              case _HelpAction.changelog:
                context.goNamed(RouteNames.changelog);
              case _HelpAction.shortcuts:
                await showDialog<void>(
                  context: context,
                  builder: (_) => const KeyboardShortcutsDialog(),
                );
              case _HelpAction.docs:
                if (docsUrl != null && docsUrl.isNotEmpty) {
                  final ok = await launchUrl(
                    Uri.parse(docsUrl),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && context.mounted) {
                    context.showSnack(l.helpOpenError, isError: true);
                  }
                }
              case _HelpAction.support:
                if (supportEmail != null && supportEmail.isNotEmpty) {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: supportEmail,
                    queryParameters: {
                      'subject': l.helpSupportEmailSubject,
                    },
                  );
                  final ok = await launchUrl(uri);
                  if (!ok && context.mounted) {
                    context.showSnack(l.helpOpenError, isError: true);
                  }
                }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _HelpAction.changelog,
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(l.helpWhatsNew),
                  if (hasUnseen) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        l.helpWhatsNewBadge,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colors.onError,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuItem(
              value: _HelpAction.shortcuts,
              child: Row(
                children: [
                  const Icon(Icons.keyboard_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(l.helpShortcuts),
                ],
              ),
            ),
            if (docsUrl != null && docsUrl.isNotEmpty)
              PopupMenuItem(
                value: _HelpAction.docs,
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(l.helpDocs),
                    const SizedBox(width: 8),
                    const Icon(Icons.open_in_new, size: 14),
                  ],
                ),
              ),
            if (supportEmail != null && supportEmail.isNotEmpty)
              PopupMenuItem(
                value: _HelpAction.support,
                child: Row(
                  children: [
                    const Icon(Icons.contact_support_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(l.helpContactSupport),
                  ],
                ),
              ),
          ],
        ),
        // Mini-dot rojo sobre el icono cuando hay novedades sin ver,
        // para que el badge sea visible sin abrir el menu.
        if (hasUnseen)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: context.colors.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.colors.surface,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _HelpAction { changelog, shortcuts, docs, support }
