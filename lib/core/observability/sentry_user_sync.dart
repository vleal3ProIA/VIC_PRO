import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/supabase_providers.dart';
import 'sentry_service.dart';

/// Mantiene sincronizado el `User` de Sentry con la sesión actual de
/// Supabase. Al hacer login: `setUser(id, email)`. Al hacer logout:
/// `setUser(null)`.
///
/// Es un provider "side-effect only": no expone valor, solo consume
/// `currentUserProvider` y propaga el cambio. Se monta una vez desde
/// `MyApp` con `ref.watch(sentryUserSyncProvider);`.
final sentryUserSyncProvider = Provider<void>((ref) {
  ref.listen(currentUserProvider, (prev, next) {
    if (next == null) {
      // ignore: discarded_futures
      SentryService.setUser();
    } else {
      // ignore: discarded_futures
      SentryService.setUser(id: next.id, email: next.email);
    }
  },
    fireImmediately: true,
  );
});
