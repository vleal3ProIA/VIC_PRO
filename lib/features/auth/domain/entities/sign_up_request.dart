class SignUpRequest {
  const SignUpRequest({
    required this.username,
    required this.email,
    required this.password,
  });

  final String username;
  final String email;
  final String password;
}

/// Resultado de un signUp exitoso.
class SignUpResult {
  const SignUpResult({required this.email, required this.needsEmailConfirmation});

  final String email;
  final bool needsEmailConfirmation;
}
