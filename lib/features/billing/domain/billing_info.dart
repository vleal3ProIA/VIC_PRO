import 'package:meta/meta.dart';

/// Datos de facturación del usuario, almacenados en `public.profiles` y
/// pasados a Stripe Customer al crear/actualizar la suscripción. Aparecen
/// automáticamente en las facturas PDF.
///
/// Es un VO leído del `profiles` row; persistirlo es responsabilidad del
/// `ProfileRepository`/datasource (no de esta clase).
@immutable
class BillingInfo {
  const BillingInfo({
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.postalCode,
    this.country,
    this.taxId,
    this.taxIdType,
  });

  /// Lee la sección "billing" del map de profile. Tolerante: cualquier
  /// campo ausente queda en null.
  factory BillingInfo.fromProfileMap(Map<String, dynamic> map) {
    DateTime? parseDate(Object? raw) {
      if (raw == null) return null;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    return BillingInfo(
      firstName: map['first_name'] as String?,
      lastName: map['last_name'] as String?,
      dateOfBirth: parseDate(map['date_of_birth']),
      addressLine1: map['address_line1'] as String?,
      addressLine2: map['address_line2'] as String?,
      city: map['city'] as String?,
      postalCode: map['postal_code'] as String?,
      country: map['country'] as String?,
      taxId: map['tax_id'] as String?,
      taxIdType: map['tax_id_type'] as String?,
    );
  }

  /// Vacío — útil como default cuando aún no hay profile cargado.
  static const empty = BillingInfo();

  final String? firstName;
  final String? lastName;
  final DateTime? dateOfBirth;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? postalCode;
  final String? country;
  final String? taxId;
  final String? taxIdType;

  /// True si tiene los datos **mínimos** requeridos para emitir una
  /// factura legalmente válida en EU: nombre completo + dirección + país.
  /// El tax_id es OPCIONAL (consumidor particular vs empresa).
  bool get isCompleteForBilling {
    bool nonEmpty(String? s) => s != null && s.trim().isNotEmpty;
    return nonEmpty(firstName) &&
        nonEmpty(lastName) &&
        nonEmpty(addressLine1) &&
        nonEmpty(city) &&
        nonEmpty(postalCode) &&
        nonEmpty(country);
  }

  /// True si AL MENOS UN campo está relleno. Lo usamos para decidir entre
  /// el "empty state" (todavía no has añadido nada) y la card de lectura
  /// con los datos guardados.
  bool get hasAnyData {
    bool nonEmpty(String? s) => s != null && s.trim().isNotEmpty;
    return nonEmpty(firstName) ||
        nonEmpty(lastName) ||
        dateOfBirth != null ||
        nonEmpty(addressLine1) ||
        nonEmpty(addressLine2) ||
        nonEmpty(city) ||
        nonEmpty(postalCode) ||
        nonEmpty(country) ||
        nonEmpty(taxId);
  }

  /// Nombre completo "Firstname Lastname" si existen, si no null.
  String? get fullName {
    final f = firstName?.trim() ?? '';
    final l = lastName?.trim() ?? '';
    final out = '$f $l'.trim();
    return out.isEmpty ? null : out;
  }

  /// Serializa al formato del map de profile para persistir. Devuelve solo
  /// las claves no-null para que el datasource haga un patch limpio.
  Map<String, dynamic> toUpdateMap() {
    final m = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (dateOfBirth != null)
        'date_of_birth':
            '${dateOfBirth!.year.toString().padLeft(4, '0')}-'
            '${dateOfBirth!.month.toString().padLeft(2, '0')}-'
            '${dateOfBirth!.day.toString().padLeft(2, '0')}',
      if (addressLine1 != null) 'address_line1': addressLine1,
      if (addressLine2 != null) 'address_line2': addressLine2,
      if (city != null) 'city': city,
      if (postalCode != null) 'postal_code': postalCode,
      if (country != null) 'country': country,
      if (taxId != null) 'tax_id': taxId,
      if (taxIdType != null) 'tax_id_type': taxIdType,
    };
    return m;
  }

  BillingInfo copyWith({
    String? firstName,
    String? lastName,
    DateTime? dateOfBirth,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? postalCode,
    String? country,
    String? taxId,
    String? taxIdType,
    bool clearTaxId = false,
  }) {
    return BillingInfo(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      addressLine1: addressLine1 ?? this.addressLine1,
      addressLine2: addressLine2 ?? this.addressLine2,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      taxId: clearTaxId ? null : (taxId ?? this.taxId),
      taxIdType: clearTaxId ? null : (taxIdType ?? this.taxIdType),
    );
  }
}
