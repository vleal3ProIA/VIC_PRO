import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:myapp/core/providers/supabase_providers.dart';

import '../data/webhooks_datasource.dart';
import '../domain/webhook_delivery.dart';
import '../domain/webhook_endpoint.dart';

final webhooksDataSourceProvider = Provider<WebhooksDataSource>((ref) {
  return WebhooksDataSource(ref.watch(supabaseClientProvider));
});

/// Lista de endpoints visibles para el user actual. Se invalida tras
/// create/delete/pause/resume.
final webhookEndpointsProvider =
    FutureProvider<List<WebhookEndpoint>>((ref) async {
  final ds = ref.watch(webhooksDataSourceProvider);
  return ds.listEndpoints();
});

/// Deliveries de un endpoint concreto. Se invalida tras test ping.
final webhookDeliveriesProvider =
    FutureProvider.family<List<WebhookDelivery>, String>((ref, endpointId) {
  final ds = ref.watch(webhooksDataSourceProvider);
  return ds.listDeliveries(endpointId);
});
