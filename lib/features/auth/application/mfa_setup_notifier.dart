import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/features/audit/application/audit_logger.dart';
import 'package:myapp/features/audit/domain/audit_events.dart';
import 'package:myapp/features/auth/application/auth_providers.dart';
import 'package:myapp/features/auth/application/mfa_providers.dart';
import 'package:myapp/features/auth/domain/entities/mfa_enrollment.dart';
import 'package:myapp/features/auth/domain/failures/auth_failure.dart';

/// Máquina de estados de la pantalla `/mfa-setup`:
///
///   loading ─┬─► alreadyEnabled ──(disable)──► unenrolling ──► disabled
///            └─► qrCode ──(verify)──► verifying ──► generatingCodes
///                  ▲                     │              │
///                  └──── failure ◄───────┘              ▼
///                                            recoveryCodes ──(ack)──► done
enum MfaSetupStep {
  loading,
  alreadyEnabled,
  qrCode,
  verifying,
  generatingCodes,
  recoveryCodes,
  done,
  unenrolling,
  disabled,
  failure,
}

class MfaSetupState {
  const MfaSetupState({
    this.step = MfaSetupStep.loading,
    this.enrollment,
    this.existingFactorId,
    this.code = '',
    this.recoveryCodes = const [],
    this.failure,
  });

  final MfaSetupStep step;
  final MfaTotpEnrollment? enrollment;

  /// Si el usuario ya tiene un factor TOTP verificado, su id (para poder
  /// desenrolarlo).
  final String? existingFactorId;

  final String code;

  /// Códigos de recuperación recién generados. Solo se muestran una vez, en
  /// el paso `recoveryCodes`.
  final List<String> recoveryCodes;

  final AuthFailure? failure;

  static const int codeLength = 6;

  bool get canSubmit =>
      step == MfaSetupStep.qrCode &&
      code.length == codeLength &&
      enrollment != null;

  MfaSetupState copyWith({
    MfaSetupStep? step,
    MfaTotpEnrollment? enrollment,
    String? existingFactorId,
    String? code,
    List<String>? recoveryCodes,
    AuthFailure? failure,
    bool clearFailure = false,
  }) {
    return MfaSetupState(
      step: step ?? this.step,
      enrollment: enrollment ?? this.enrollment,
      existingFactorId: existingFactorId ?? this.existingFactorId,
      code: code ?? this.code,
      recoveryCodes: recoveryCodes ?? this.recoveryCodes,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class MfaSetupNotifier extends Notifier<MfaSetupState> {
  @override
  MfaSetupState build() {
    _init();
    return const MfaSetupState();
  }

  /// Al entrar a la pantalla: comprueba si ya hay un factor TOTP verificado.
  /// - Sí → step `alreadyEnabled` (el usuario puede desactivarlo).
  /// - No → arranca el enrollment automáticamente.
  Future<void> _init() async {
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.listMfaFactors();
    final factors = result.fold(
      (_) => <MfaFactor>[],
      (f) => f,
    );
    final verified =
        factors.where((f) => f.isVerified && f.type == 'totp').toList();
    if (verified.isNotEmpty) {
      state = state.copyWith(
        step: MfaSetupStep.alreadyEnabled,
        existingFactorId: verified.first.id,
      );
    } else {
      // Limpia los factores TOTP SIN VERIFICAR acumulados: cada visita previa
      // a esta pantalla crea uno nuevo via enroll(), y Supabase limita el
      // numero de factores -> al pasarse, enroll() falla con "Algo salio mal".
      // Borrarlos garantiza que enroll() siempre tenga sitio.
      final stale =
          factors.where((f) => !f.isVerified && f.type == 'totp').toList();
      for (final f in stale) {
        await repo.unenrollMfa(f.id);
      }
      await _startEnrollment();
    }
  }

  Future<void> _startEnrollment() async {
    state = state.copyWith(step: MfaSetupStep.loading, clearFailure: true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.enrollTotp(friendlyName: 'myapp');
    result.match(
      (failure) => state = state.copyWith(
        step: MfaSetupStep.failure,
        failure: failure,
      ),
      (enrollment) => state = state.copyWith(
        step: MfaSetupStep.qrCode,
        enrollment: enrollment,
      ),
    );
  }

  /// Reintenta el enrollment tras un fallo de red, etc.
  Future<void> retryEnrollment() => _startEnrollment();

  void codeChanged(String v) {
    state = state.copyWith(code: v, clearFailure: true);
  }

  /// Verifica el código del autenticador para completar el enrollment.
  /// Si tiene éxito, encadena la generación de los códigos de recuperación.
  Future<void> verify() async {
    if (!state.canSubmit) return;
    state = state.copyWith(step: MfaSetupStep.verifying, clearFailure: true);
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.verifyMfaEnrollment(
      factorId: state.enrollment!.factorId,
      code: state.code,
    );
    final failure = result.fold<AuthFailure?>((l) => l, (_) => null);
    if (failure != null) {
      state = state.copyWith(step: MfaSetupStep.qrCode, failure: failure);
      return;
    }
    // MFA ya está activo. Audita el evento + genera los códigos de recuperación.
    ref.invalidate(mfaFactorsProvider);
    unawaited(ref.read(auditLoggerProvider).log(AuditEvents.mfaEnabled));
    await _generateRecoveryCodes();
  }

  Future<void> _generateRecoveryCodes() async {
    state = state.copyWith(
      step: MfaSetupStep.generatingCodes,
      clearFailure: true,
    );
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.generateRecoveryCodes();
    result.match(
      // Aunque falle, el MFA YA está activo: vamos igualmente al paso de
      // códigos, pero mostrando el error y un botón de reintento.
      (failure) => state = state.copyWith(
        step: MfaSetupStep.recoveryCodes,
        failure: failure,
      ),
      (codes) => state = state.copyWith(
        step: MfaSetupStep.recoveryCodes,
        recoveryCodes: codes,
      ),
    );
  }

  /// Reintenta la generación de códigos (p. ej. si la Edge Function no
  /// estaba desplegada la primera vez).
  Future<void> retryGenerateRecoveryCodes() => _generateRecoveryCodes();

  /// El usuario confirma que ha guardado los códigos → pantalla final.
  void acknowledgeRecoveryCodes() {
    state = state.copyWith(step: MfaSetupStep.done);
  }

  /// Desactiva (unenroll) el factor TOTP verificado existente.
  Future<void> disable() async {
    final factorId = state.existingFactorId;
    if (factorId == null) return;
    state = state.copyWith(
      step: MfaSetupStep.unenrolling,
      clearFailure: true,
    );
    final repo = ref.read(authRepositoryProvider);
    final result = await repo.unenrollMfa(factorId);
    result.match(
      (failure) => state = state.copyWith(
        step: MfaSetupStep.alreadyEnabled,
        failure: failure,
      ),
      (_) {
        state = state.copyWith(step: MfaSetupStep.disabled);
        ref.invalidate(mfaFactorsProvider);
        ref.read(auditLoggerProvider).log(AuditEvents.mfaDisabled);
      },
    );
  }

  void reset() => state = const MfaSetupState();
}

final mfaSetupNotifierProvider =
    NotifierProvider<MfaSetupNotifier, MfaSetupState>(MfaSetupNotifier.new);
