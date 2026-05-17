import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/email_log_datasource.dart';
import '../domain/email_log_entry.dart';

final emailLogDataSourceProvider = Provider<EmailLogDataSource>((ref) {
  return EmailLogDataSource(ref.watch(supabaseClientProvider));
});

/// Últimos 100 emails. Se invalida tras send-test.
final emailLogProvider = FutureProvider<List<EmailLogEntry>>((ref) async {
  final ds = ref.watch(emailLogDataSourceProvider);
  return ds.list();
});
