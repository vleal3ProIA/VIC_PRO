import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

import '_helpers.dart';

void main() {
  testGoldens(
    'WelcomePage matches golden in mobile + desktop',
    (tester) async {
      final overrides = await defaultGoldenOverrides();
      final widget = buildForGolden(
        child: const WelcomePage(),
        overrides: overrides,
      );
      await tester.pumpWidgetBuilder(widget);
      await multiScreenGolden(
        tester,
        'welcome_page',
        devices: goldenDevices,
      );
    },
    tags: ['golden'],
  );
}
