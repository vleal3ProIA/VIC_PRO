import 'package:meta/meta.dart';

/// Plan del catálogo. Inmutable; el cliente solo lo lee (los admins editan
/// vía pantallas dedicadas que vendrán en bloques posteriores).
@immutable
class Plan {
  const Plan({
    required this.id,
    required this.slug,
    required this.name,
    required this.currency,
    required this.features,
    required this.position,
    required this.isActive,
    this.description,
    this.priceMonthlyCents,
    this.priceYearlyCents,
  });

  factory Plan.fromMap(Map<String, dynamic> map) {
    return Plan(
      id: map['id'] as String,
      slug: map['slug'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      priceMonthlyCents: map['price_monthly_cents'] as int?,
      priceYearlyCents: map['price_yearly_cents'] as int?,
      currency: (map['currency'] as String?) ?? 'EUR',
      features: Map<String, dynamic>.from(
        (map['features'] as Map?) ?? const {},
      ),
      position: (map['position'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
    );
  }

  final String id;
  final String slug;
  final String name;
  final String? description;
  final int? priceMonthlyCents;
  final int? priceYearlyCents;
  final String currency;

  /// Mapa de entitlements del plan. Convención: snake_case en claves;
  /// valor `-1` para cuotas significa "ilimitado".
  final Map<String, dynamic> features;
  final int position;
  final bool isActive;

  /// True si el plan no tiene precio público (típicamente Enterprise).
  bool get isCustomPriced =>
      priceMonthlyCents == null && priceYearlyCents == null;

  /// True solo si AMBOS precios son explícitamente 0. Plan custom-priced
  /// (Enterprise con nulls) NO se considera free.
  bool get isFree => priceMonthlyCents == 0 && priceYearlyCents == 0;

  /// Formato "€19" o "Custom" para mostrar en una card.
  String formatPrice({required bool yearly}) {
    final cents = yearly ? priceYearlyCents : priceMonthlyCents;
    if (cents == null) return '—';
    if (cents == 0) return 'Free';
    final euros = cents / 100;
    final symbol = switch (currency) {
      'EUR' => '€',
      'USD' => r'$',
      'GBP' => '£',
      _ => currency,
    };
    final formatted = euros == euros.roundToDouble()
        ? euros.toStringAsFixed(0)
        : euros.toStringAsFixed(2);
    return '$symbol$formatted';
  }
}
