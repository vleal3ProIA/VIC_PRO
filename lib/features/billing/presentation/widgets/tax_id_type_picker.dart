import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// Tipo de Tax ID según la convención de Stripe. Subconjunto común;
/// lista completa: https://stripe.com/docs/api/customers/object#customer_object-tax_ids
class TaxIdTypePicker extends StatelessWidget {
  const TaxIdTypePicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  static const List<({String code, String label})> _types = [
    (code: 'eu_vat', label: 'VAT EU (eu_vat)'),
    (code: 'es_cif', label: 'NIF/CIF España (es_cif)'),
    (code: 'gb_vat', label: 'VAT UK (gb_vat)'),
    (code: 'us_ein', label: 'EIN US (us_ein)'),
    (code: 'ca_bn', label: 'Business Number Canada (ca_bn)'),
    (code: 'mx_rfc', label: 'RFC México (mx_rfc)'),
    (code: 'br_cnpj', label: 'CNPJ Brasil (br_cnpj)'),
    (code: 'ar_cuit', label: 'CUIT Argentina (ar_cuit)'),
    (code: 'au_abn', label: 'ABN Australia (au_abn)'),
    (code: 'ch_vat', label: 'VAT Suiza (ch_vat)'),
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: context.l10n.billingInfoFieldTaxIdType,
      ),
      onChanged: enabled ? onChanged : null,
      items: [
        for (final t in _types)
          DropdownMenuItem(value: t.code, child: Text(t.label)),
      ],
    );
  }
}
