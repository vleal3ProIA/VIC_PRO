import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Proveedores de login social soportados.
enum SocialProvider { google, apple }

/// Estado del login social (OAuth).
///
/// - `idle`: sin acción en curso.
/// - `redirecting`: se ha pedido el redirect al proveedor. En web el navegador
///   navega fuera de la app, así que este estado normalmente no se llega a
///   "ver" mucho tiempo: la pestaña cambia de URL.
/// - `failure`: el SDK no pudo iniciar el redirect (red, config, etc.).
///
/// [provider] indica con qué proveedor se está operando, para que la UI sepa
/// en qué botón mostrar el spinner.
enum OAuthStatus { idle, redirecting, failure }

class OAuthState {
  const OAuthState({
    this.status = OAuthStatus.idle,
    this.provider,
    this.failure,
  });

  final OAuthStatus status;
  final SocialProvider? provider;
  final AuthFailure? failure;

  bool get isBusy => status == OAuthStatus.redirecting;

  /// `true` si hay un redirect en curso para ese proveedor concreto.
  bool isBusyWith(SocialProvider p) => isBusy && provider == p;

  OAuthState copyWith({
    OAuthStatus? status,
    SocialProvider? provider,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return OAuthState(
      status: status ?? this.status,
      provider: provider ?? this.provider,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Notifier "fire-and-forget" para login social (Google, Apple).
///
/// `signIn` en web dispara un *full-page redirect*: si todo va bien, la
/// pestaña sale de la app y vuelve por `/auth/callback?type=oauth`. Por eso
/// solo gestionamos el caso de error (cuando el redirect ni siquiera arranca).
class OAuthNotifier extends Notifier<OAuthState> {
  @override
  OAuthState build() => const OAuthState();

  Future<void> signIn(SocialProvider provider) async {
    if (state.isBusy) return;
    state = state.copyWith(
      status: OAuthStatus.redirecting,
      provider: provider,
      clearFailure: true,
    );

    final repo = ref.read(authRepositoryProvider);
    final result = await switch (provider) {
      SocialProvider.google => repo.signInWithGoogle(),
      SocialProvider.apple => repo.signInWithApple(),
    };
    result.match(
      (failure) => state = state.copyWith(
        status: OAuthStatus.failure,
        failure: failure,
      ),
      // Éxito: el navegador está redirigiendo. Mantenemos `redirecting`.
      (_) {},
    );
  }

  /// Atajo legible para Google.
  Future<void> signInWithGoogle() => signIn(SocialProvider.google);

  /// Atajo legible para Apple.
  Future<void> signInWithApple() => signIn(SocialProvider.apple);

  void reset() => state = const OAuthState();
}

final oauthNotifierProvider =
    NotifierProvider<OAuthNotifier, OAuthState>(OAuthNotifier.new);
