import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/observability/sentry_service.dart';

import 'tenant_providers.dart';

/// Side-effect-only: mantiene `tenant_id` / `tenant_slug` como tags
/// globales en Sentry. Cualquier evento posterior los llevará y permitirá
/// filtrar el panel de errores por workspace.
///
/// Se monta una vez desde `MyApp` con `ref.watch(tenantSentrySyncProvider);`.
final tenantSentrySyncProvider = Provider<void>((ref) {
  ref.listen(
    currentTenantProvider,
    (prev, next) {
      final tenant = next.valueOrNull;
      // ignore: discarded_futures
      SentryService.setTenant(id: tenant?.id, slug: tenant?.slug);
    },
    fireImmediately: true,
  );
});
