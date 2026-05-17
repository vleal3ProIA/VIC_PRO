import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/personal_access_token.dart';

/// Dialog que muestra el secret de un PAT RECIÉN creado.
///
/// El usuario SOLO ve el secret en este dialog -- si lo cierra sin
/// copiarlo, el secret se pierde para siempre y debe crear otro
/// token. Por eso:
///  - el cerrar requiere check explícito ("entiendo, lo guardé")
///  - el dialog NO es dismissible (no se cierra clickando fuera)
///  - botón de copiar destacado al lado del campo
class TokenSecretDialog extends StatefulWidget {
  const TokenSecretDialog({required this.token, super.key});

  final PersonalAccessToken token;

  @override
  State<TokenSecretDialog> createState() => _TokenSecretDialogState();
}

class _TokenSecretDialogState extends State<TokenSecretDialog> {
  bool _acknowledged = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final secret = widget.token.secret ?? '';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: context.colors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l.tokensSecretDialogTitle)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.tokensSecretIntro(widget.token.name)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: context.colors.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        secret,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _copied
                          ? l.tokensSecretCopied
                          : l.tokensSecretCopy,
                      icon: Icon(_copied ? Icons.check : Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: secret));
                        if (!mounted) return;
                        setState(() => _copied = true);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colors.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      color: context.colors.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.tokensSecretWarning,
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                onChanged: (v) => setState(() => _acknowledged = v ?? false),
                title: Text(l.tokensSecretAcknowledge),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _acknowledged
              ? () => Navigator.of(context).pop()
              : null,
          child: Text(l.actionDone),
        ),
      ],
    );
  }
}
