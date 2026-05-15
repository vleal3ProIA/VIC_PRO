import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/auth/application/webauthn_providers.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

enum PasskeyActionStatus { idle, busy, success, failure }

/// Estado del último intento (registrar / iniciar sesión / borrar).
class PasskeyActionState {
  const PasskeyActionState({
    this.status = PasskeyActionStatus.idle,
    this.failure,
  });

  final PasskeyActionStatus status;
  final AuthFailure? failure;

  bool get isBusy => status == PasskeyActionStatus.busy;

  PasskeyActionState copyWith({
    PasskeyActionStatus? status,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return PasskeyActionState(
      status: status ?? this.status,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

/// Notifier compartido por las pantallas que tocan passkeys: registro
/// (Ajustes), login (`/login`) y borrado (Ajustes).
class PasskeyNotifier extends Notifier<PasskeyActionState> {
  @override
  PasskeyActionState build() => const PasskeyActionState();

  Future<void> register({String? friendlyName}) async {
    if (state.isBusy) return;
    state = state.copyWith(
      status: PasskeyActionStatus.busy,
      clearFailure: true,
    );
    final repo = ref.read(webauthnRepositoryProvider);
    final result = await repo.registerPasskey(friendlyName: friendlyName);
    result.match(
      (failure) => state = state.copyWith(
        status: PasskeyActionStatus.failure,
        failure: failure,
      ),
      (_) {
        state = state.copyWith(status: PasskeyActionStatus.success);
        ref.invalidate(myPasskeysProvider);
      },
    );
  }

  Future<void> login() async {
    if (state.isBusy) return;
    state = state.copyWith(
      status: PasskeyActionStatus.busy,
      clearFailure: true,
    );
    final repo = ref.read(webauthnRepositoryProvider);
    final result = await repo.loginWithPasskey();
    result.match(
      (failure) => state = state.copyWith(
        status: PasskeyActionStatus.failure,
        failure: failure,
      ),
      (_) => state = state.copyWith(status: PasskeyActionStatus.success),
    );
  }

  Future<void> delete(String id) async {
    if (state.isBusy) return;
    state = state.copyWith(
      status: PasskeyActionStatus.busy,
      clearFailure: true,
    );
    final repo = ref.read(webauthnRepositoryProvider);
    final result = await repo.deletePasskey(id);
    result.match(
      (failure) => state = state.copyWith(
        status: PasskeyActionStatus.failure,
        failure: failure,
      ),
      (_) {
        state = state.copyWith(status: PasskeyActionStatus.success);
        ref.invalidate(myPasskeysProvider);
      },
    );
  }

  void reset() => state = const PasskeyActionState();
}

final passkeyNotifierProvider =
    NotifierProvider<PasskeyNotifier, PasskeyActionState>(
  PasskeyNotifier.new,
);
