import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Estado del login social (OAuth).
///
/// - `idle`: sin acción en curso.
/// - `redirecting`: se ha pedido el redirect a Google. En web el navegador
///   navega fuera de la app, así que este estado normalmente no se llega a
///   "ver" mucho tiempo: la pestaña cambia de URL.
/// - `failure`: el SDK no pudo iniciar el redirect (red, config, etc.).
enum OAuthStatus { idle, redirecting, failure }

class OAuthState {
  const OAuthState({
    this.status = OAuthStatus.idle,
    this.failure,
  });

  final OAuthStatus status;
  final AuthFailure? failure;

  bool get isBusy => status == OAuthStatus.redirecting;

  OAuthState copyWith({
    OAuthStatus? status,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return OAuthState(
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Notifier "fire-and-forget" para login con Google.
///
/// `signInWithGoogle` en web dispara un *full-page redirect*: si todo va bien,
/// la pestaña sale de la app y vuelve por `/auth/callback?type=oauth`. Por eso
/// solo gestionamos el caso de error (cuando el redirect ni siquiera arranca).
class OAuthNotifier extends Notifier<OAuthState> {
  @override
  OAuthState build() => const OAuthState();

  Future<void> signInWithGoogle() async {
    if (state.isBusy) return;
    state = state.copyWith(status: OAuthStatus.redirecting, clearFailure: true);

    final repo = ref.read(authRepositoryProvider);
    final result = await repo.signInWithGoogle();
    result.match(
      (failure) => state = state.copyWith(
        status: OAuthStatus.failure,
        failure: failure,
      ),
      // Éxito: el navegador está redirigiendo. Mantenemos `redirecting`.
      (_) {},
    );
  }

  void reset() => state = const OAuthState();
}

final oauthNotifierProvider =
    NotifierProvider<OAuthNotifier, OAuthState>(OAuthNotifier.new);
