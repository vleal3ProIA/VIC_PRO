import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myapp/core/extensions/context_extensions.dart';
import 'package:myapp/core/router/route_names.dart';
import 'package:myapp/core/widgets/app_empty_state.dart';
import 'package:myapp/core/widgets/app_error_state.dart';
import 'package:myapp/core/widgets/app_loading_state.dart';
import 'package:myapp/generated/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/billing_providers.dart';
import '../../domain/invoice.dart';

/// Pantalla `/billing/invoices` — histórico de facturas del tenant.
///
/// Las facturas las genera Stripe automáticamente cuando renueva la
/// suscripción. La UI muestra fecha, importe, estado y botones de
/// **Download PDF** y **View** (página Stripe hosted con detalle).
///
/// El PDF es generado por Stripe con tu branding configurado en
/// **Dashboard → Settings → Branding** (logo, colores, datos fiscales
/// del emisor). Los datos del cliente vienen del Stripe Customer (que
/// nosotros sincronizamos desde `profiles` via la PR 1.F.4).
class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final invoicesAsync = ref.watch(myInvoicesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.goNamed(RouteNames.accountSettings),
        ),
        title: Text(l.invoicesTitle),
        actions: [
          IconButton(
            tooltip: l.actionRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myInvoicesProvider),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: invoicesAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: l.invoicesLoadError,
              detail: e.toString(),
              onRetry: () => ref.invalidate(myInvoicesProvider),
              retryLabel: l.actionRetry,
            ),
            data: (invoices) {
              if (invoices.isEmpty) {
                return AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: l.invoicesEmpty,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: invoices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _InvoiceRow(invoice: invoices[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final localeCode = Localizations.localeOf(context).languageCode;
    final formattedDate =
        DateFormat.yMMMd(localeCode).format(invoice.createdAt.toLocal());
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icono según estado.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _statusColor(context).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _statusIcon(),
                color: _statusColor(context),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            // Número / fecha / estado.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.number ?? invoice.id.substring(0, 12),
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$formattedDate · ${_statusLabel(l)}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Importe.
            Text(
              invoice.formatAmount(),
              style: context.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            // Acciones.
            if (invoice.invoicePdfUrl != null)
              IconButton(
                tooltip: l.invoicesDownloadPdf,
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _open(context, invoice.invoicePdfUrl!),
              ),
            if (invoice.hostedInvoiceUrl != null)
              IconButton(
                tooltip: l.invoicesViewOnline,
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _open(context, invoice.hostedInvoiceUrl!),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    // El PDF lo abrimos en pestaña nueva — así no nos llevamos al user
    // fuera de la app. Para el invoice_pdf, el navegador hará download
    // automático si el server manda Content-Disposition: attachment, o
    // mostrará el PDF inline si solo es application/pdf.
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok && context.mounted) {
      context.showSnack(context.l10n.invoicesOpenError, isError: true);
    }
  }

  IconData _statusIcon() => switch (invoice.status) {
        InvoiceStatus.paid => Icons.check_circle_outline,
        InvoiceStatus.open => Icons.schedule_outlined,
        InvoiceStatus.draft => Icons.edit_note_outlined,
        InvoiceStatus.voided => Icons.block_outlined,
        InvoiceStatus.uncollectible => Icons.error_outline,
      };

  Color _statusColor(BuildContext context) => switch (invoice.status) {
        InvoiceStatus.paid => context.colors.tertiary,
        InvoiceStatus.open => context.colors.primary,
        InvoiceStatus.draft => context.colors.outline,
        InvoiceStatus.voided => context.colors.outline,
        InvoiceStatus.uncollectible => context.colors.error,
      };

  String _statusLabel(AppLocalizations l) => switch (invoice.status) {
        InvoiceStatus.paid => l.invoiceStatusPaid,
        InvoiceStatus.open => l.invoiceStatusOpen,
        InvoiceStatus.draft => l.invoiceStatusDraft,
        InvoiceStatus.voided => l.invoiceStatusVoided,
        InvoiceStatus.uncollectible => l.invoiceStatusUncollectible,
      };
}
