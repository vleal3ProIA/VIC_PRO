import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/tenants/application/tenant_providers.dart';
import 'package:myapp/features/tenants/domain/tenant.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests del notifier de tenant actual: prioriza el id guardado en
/// SharedPreferences sobre el default, persiste cambios y se resetea bien.
///
/// Aislamos `myTenantsProvider` con un override que devuelve una lista
/// controlada — no necesitamos backend.
void main() {
  late SharedPreferences prefs;

  Tenant t(String id, {bool isPersonal = false, int day = 1}) {
    return Tenant.fromMap({
      'id': id,
      'name': id,
      'slug': id,
      'owner_id': 'u1',
      'is_personal': isPersonal,
      'created_at': '2026-01-${day.toString().padLeft(2, '0')}T10:00:00Z',
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer makeContainer({
    required List<Tenant> tenants,
  }) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        myTenantsProvider.overrideWith((ref) async => tenants),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('currentTenantProvider', () {
    test('returns null when there are no tenants', () async {
      final c = makeContainer(tenants: []);
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantProvider).valueOrNull, isNull);
    });

    test('defaults to the first tenant when no preference is saved',
        () async {
      final c = makeContainer(
        tenants: [t('real-1', day: 2), t('personal', isPersonal: true, day: 1)],
      );
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantProvider).valueOrNull?.id, 'real-1');
    });

    test('respects saved preference when present and valid', () async {
      await prefs.setString(currentTenantPrefsKey, 'real-2');
      final c = makeContainer(
        tenants: [t('real-1', day: 2), t('real-2', day: 3)],
      );
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantProvider).valueOrNull?.id, 'real-2');
    });

    test('falls back to first when saved id is no longer in the list',
        () async {
      await prefs.setString(currentTenantPrefsKey, 'gone-tenant');
      final c = makeContainer(tenants: [t('real-1')]);
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantProvider).valueOrNull?.id, 'real-1');
    });

    test('setCurrent() persists the choice and updates state', () async {
      final c = makeContainer(
        tenants: [t('a'), t('b'), t('c')],
      );
      await c.read(myTenantsProvider.future);
      // El default es 'a'.
      expect(c.read(currentTenantProvider).valueOrNull?.id, 'a');

      await c.read(currentTenantProvider.notifier).setCurrent('c');
      expect(c.read(currentTenantProvider).valueOrNull?.id, 'c');
      expect(prefs.getString(currentTenantPrefsKey), 'c');
    });

    test('setCurrent() throws if id is not in user tenants', () async {
      final c = makeContainer(tenants: [t('a')]);
      await c.read(myTenantsProvider.future);
      expect(
        () => c.read(currentTenantProvider.notifier).setCurrent('xx'),
        throwsStateError,
      );
    });

    test('clear() removes the persisted preference', () async {
      await prefs.setString(currentTenantPrefsKey, 'a');
      final c = makeContainer(tenants: [t('a')]);
      await c.read(myTenantsProvider.future);

      await c.read(currentTenantProvider.notifier).clear();
      expect(prefs.getString(currentTenantPrefsKey), isNull);
    });
  });

  group('currentTenantIdProvider', () {
    test('returns the id of the active tenant', () async {
      final c = makeContainer(tenants: [t('a'), t('b')]);
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantIdProvider), 'a');
    });

    test('returns null when no tenant is active', () async {
      final c = makeContainer(tenants: []);
      await c.read(myTenantsProvider.future);
      expect(c.read(currentTenantIdProvider), isNull);
    });
  });
}
