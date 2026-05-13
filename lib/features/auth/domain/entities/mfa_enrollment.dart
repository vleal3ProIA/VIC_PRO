/// Datos devueltos por Supabase al iniciar el enrollment de un factor TOTP.
/// La pantalla de setup muestra `qrCodeSvg` (para escanear con Google
/// Authenticator/Authy/1Password/etc.) y `secret` (alternativa manual).
class MfaTotpEnrollment {
  const MfaTotpEnrollment({
    required this.factorId,
    required this.secret,
    required this.qrCodeSvg,
    required this.uri,
  });

  final String factorId;

  /// Secret en base32 (lo que el usuario ve y puede introducir manual en
  /// la app autenticadora si no escanea el QR).
  final String secret;

  /// SVG XML del QR (Supabase devuelve un data: URI con SVG).
  final String qrCodeSvg;

  /// URI `otpauth://totp/...` — la usamos para pintar nuestro propio QR
  /// con `qr_flutter`, ignorando el SVG remoto (menos sorpresas).
  final String uri;
}

/// Item simple de la lista de factores enrollados.
class MfaFactor {
  const MfaFactor({
    required this.id,
    required this.type,
    required this.status,
    this.friendlyName,
  });

  final String id;
  final String type; // "totp"
  final String status; // "verified" | "unverified"
  final String? friendlyName;

  bool get isVerified => status == 'verified';
}
