import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myapp/core/extensions/context_extensions.dart';

import '../../domain/webhook_endpoint.dart';

/// Dialog que muestra el secret HMAC de un endpoint recién creado.
/// El secret es necesario para que el cliente verifique las firmas
/// HMAC de los webhooks entrantes -- por eso lo enseñamos UNA VEZ
/// con copia destacada y checkbox de confirmación.
class WebhookSecretDialog extends StatefulWidget {
  const WebhookSecretDialog({required this.endpoint, super.key});

  final WebhookEndpoint endpoint;

  @override
  State<WebhookSecretDialog> createState() => _WebhookSecretDialogState();
}

class _WebhookSecretDialogState extends State<WebhookSecretDialog> {
  bool _acknowledged = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final secret = widget.endpoint.secret ?? '';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.check_circle, color: context.colors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l.webhooksSecretDialogTitle)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.webhooksSecretIntro),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.colors.outlineVariant),
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
                          ? l.webhooksSecretCopied
                          : l.webhooksSecretCopy,
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
                        l.webhooksSecretWarning,
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Snippet de cómo verificar la firma en el cliente.
              Text(
                l.webhooksSecretHowToVerify,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '''
// Node example
const sig = req.headers['x-webhook-signature'];
const expected = 'sha256=' + crypto
  .createHmac('sha256', WEBHOOK_SECRET)
  .update(rawBody)
  .digest('hex');
if (sig !== expected) return res.sendStatus(401);''',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _acknowledged,
                onChanged: (v) => setState(() => _acknowledged = v ?? false),
                title: Text(l.webhooksSecretAcknowledge),
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
