import 'package:flutter/material.dart';

import 'package:myapp/core/extensions/context_extensions.dart';

/// DropdownButton de países. Lista limitada a los soportados por Stripe
/// para test mode (~ 40 países comunes). Para producción puedes expandir
/// a la lista completa (https://stripe.com/docs/development/quickstart
/// #stripe-supported-countries).
///
/// Devuelve el código ISO 3166-1 alpha-2 ('ES', 'US', etc.).
class CountryPicker extends StatelessWidget {
  const CountryPicker({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.validator,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String? Function(String?)? validator;

  /// Lista corta de países habituales en SaaS B2B en EU + LATAM. Cada
  /// entrada: (ISO code, display name in English — local locale tendrá
  /// que mostrar nombres traducidos a futuro).
  static const List<({String code, String name})> _countries = [
    (code: 'ES', name: 'Spain'),
    (code: 'PT', name: 'Portugal'),
    (code: 'FR', name: 'France'),
    (code: 'IT', name: 'Italy'),
    (code: 'DE', name: 'Germany'),
    (code: 'AT', name: 'Austria'),
    (code: 'BE', name: 'Belgium'),
    (code: 'NL', name: 'Netherlands'),
    (code: 'IE', name: 'Ireland'),
    (code: 'LU', name: 'Luxembourg'),
    (code: 'DK', name: 'Denmark'),
    (code: 'SE', name: 'Sweden'),
    (code: 'FI', name: 'Finland'),
    (code: 'NO', name: 'Norway'),
    (code: 'PL', name: 'Poland'),
    (code: 'CZ', name: 'Czech Republic'),
    (code: 'GR', name: 'Greece'),
    (code: 'GB', name: 'United Kingdom'),
    (code: 'CH', name: 'Switzerland'),
    (code: 'US', name: 'United States'),
    (code: 'CA', name: 'Canada'),
    (code: 'MX', name: 'Mexico'),
    (code: 'AR', name: 'Argentina'),
    (code: 'BR', name: 'Brazil'),
    (code: 'CL', name: 'Chile'),
    (code: 'CO', name: 'Colombia'),
    (code: 'PE', name: 'Peru'),
    (code: 'UY', name: 'Uruguay'),
    (code: 'AU', name: 'Australia'),
    (code: 'NZ', name: 'New Zealand'),
    (code: 'JP', name: 'Japan'),
    (code: 'SG', name: 'Singapore'),
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: context.l10n.billingInfoFieldCountry),
      onChanged: enabled ? onChanged : null,
      validator: validator,
      items: [
        for (final c in _countries)
          DropdownMenuItem(
            value: c.code,
            child: Text('${c.code} · ${c.name}'),
          ),
      ],
    );
  }
}
