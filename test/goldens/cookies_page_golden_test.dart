import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:myapp/features/legal/presentation/pages/cookies_page.dart';

import '_helpers.dart';

void main() {
  testGoldens(
    'CookiesPage matches golden in mobile + desktop',
    (tester) async {
      final overrides = await defaultGoldenOverrides();
      final widget = buildForGolden(
        child: const CookiesPage(),
        overrides: overrides,
      );
      await tester.pumpWidgetBuilder(widget);
      await multiScreenGolden(
        tester,
        'cookies_page',
        devices: goldenDevices,
      );
    },
    tags: ['golden'],
  );
}
