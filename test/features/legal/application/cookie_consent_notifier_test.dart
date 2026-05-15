import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/providers/preferences_provider.dart';
import 'package:myapp/features/legal/application/cookie_consent_notifier.dart';
import 'package:myapp/features/legal/domain/cookie_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
  });

  CookieConsentNotifier notifier() =>
      container.read(cookieConsentNotifierProvider.notifier);
  CookieConsent state() => container.read(cookieConsentNotifierProvider);

  test('initial state: undecided, analytics off, essential always on', () {
    expect(state().isDecided, isFalse);
    expect(state().analytics, isFalse);
    expect(state().essential, isTrue);
  });

  test('acceptAll → decided + analytics ON', () async {
    await notifier().acceptAll();
    expect(state().isDecided, isTrue);
    expect(state().analytics, isTrue);
  });

  test('rejectOptional → decided + analytics OFF', () async {
    await notifier().rejectOptional();
    expect(state().isDecided, isTrue);
    expect(state().analytics, isFalse);
  });

  test('setAnalytics toggles + marks decided', () async {
    await notifier().setAnalytics(value: true);
    expect(state().analytics, isTrue);
    expect(state().isDecided, isTrue);

    await notifier().setAnalytics(value: false);
    expect(state().analytics, isFalse);
    expect(state().isDecided, isTrue);
  });

  test('decision persists across notifier re-builds', () async {
    await notifier().acceptAll();
    final prefsValue = prefs.getString('cookie_consent_v1');
    expect(prefsValue, isNotNull);

    // Re-leemos el provider en un container nuevo con los mismos prefs:
    // el estado debe llegar ya decidido.
    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    final loaded = c2.read(cookieConsentNotifierProvider);
    expect(loaded.isDecided, isTrue);
    expect(loaded.analytics, isTrue);
  });

  test('old-version payloads in prefs are ignored', () async {
    await prefs.setString('cookie_consent_v1', '{"version": 0}');
    final c2 = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c2.dispose);
    final loaded = c2.read(cookieConsentNotifierProvider);
    expect(loaded.isDecided, isFalse); // re-pregunta
  });
}
