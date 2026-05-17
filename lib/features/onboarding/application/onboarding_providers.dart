import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/onboarding_datasource.dart';

final onboardingDataSourceProvider = Provider<OnboardingDataSource>((ref) {
  return OnboardingDataSource(ref.watch(supabaseClientProvider));
});

/// `true` si el user actual ya completó el onboarding. `null` mientras
/// carga (durante la carga el router NO redirige — evita un flash de
/// /onboarding antes de saber que ya lo hizo).
final onboardingCompletedProvider = FutureProvider<bool>((ref) async {
  final ds = ref.watch(onboardingDataSourceProvider);
  return ds.isCompleted();
});
