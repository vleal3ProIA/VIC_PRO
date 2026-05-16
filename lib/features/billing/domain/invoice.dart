import 'package:meta/meta.dart';

/// Estado de una factura Stripe. Lo que más nos importa para mostrar es
/// `paid` (gris OK) vs cualquier otro (warn/error).
enum InvoiceStatus {
  draft,
  open,
  paid,
  uncollectible,
  voided;

  static InvoiceStatus fromString(String? v) => switch (v) {
        'draft' => InvoiceStatus.draft,
        'open' => InvoiceStatus.open,
        'paid' => InvoiceStatus.paid,
        'uncollectible' => InvoiceStatus.uncollectible,
        'void' => InvoiceStatus.voided,
        _ => InvoiceStatus.open,
      };
}

/// Una factura de Stripe asociada a la suscripción del tenant. Inmutable.
@immutable
class Invoice {
  const Invoice({
    required this.id,
    required this.status,
    required this.amountDueCents,
    required this.amountPaidCents,
    required this.currency,
    required this.createdAt,
    this.number,
    this.hostedInvoiceUrl,
    this.invoicePdfUrl,
    this.periodStart,
    this.periodEnd,
  });

  factory Invoice.fromMap(Map<String, dynamic> map) {
    DateTime? unixToDate(Object? raw) {
      if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
      return null;
    }

    return Invoice(
      id: map['id'] as String,
      number: map['number'] as String?,
      status: InvoiceStatus.fromString(map['status'] as String?),
      amountDueCents: (map['amount_due'] as int?) ?? 0,
      amountPaidCents: (map['amount_paid'] as int?) ?? 0,
      currency: (map['currency'] as String?) ?? 'eur',
      createdAt: unixToDate(map['created']) ?? DateTime.now(),
      hostedInvoiceUrl: map['hosted_invoice_url'] as String?,
      invoicePdfUrl: map['invoice_pdf'] as String?,
      periodStart: unixToDate(map['period_start']),
      periodEnd: unixToDate(map['period_end']),
    );
  }

  final String id;
  final String? number;
  final InvoiceStatus status;
  final int amountDueCents;
  final int amountPaidCents;
  final String currency;
  final DateTime createdAt;

  /// Página de Stripe con detalle + opción de pagar (si está pendiente).
  /// La UI puede mostrarla en una pestaña nueva como alternativa al PDF.
  final String? hostedInvoiceUrl;

  /// URL directa al PDF (signed, expira). La UI puede abrirla con
  /// launchUrl para descargar/imprimir.
  final String? invoicePdfUrl;

  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// "€19,00" — formatea el monto pagado (o el due si no pagado).
  String formatAmount() {
    final cents = status == InvoiceStatus.paid
        ? amountPaidCents
        : amountDueCents;
    final euros = cents / 100;
    final symbol = switch (currency.toUpperCase()) {
      'EUR' => '€',
      'USD' => r'$',
      'GBP' => '£',
      _ => currency.toUpperCase(),
    };
    final formatted = euros == euros.roundToDouble()
        ? '${euros.toStringAsFixed(0)},00'
        : euros.toStringAsFixed(2).replaceAll('.', ',');
    return '$symbol$formatted';
  }
}
