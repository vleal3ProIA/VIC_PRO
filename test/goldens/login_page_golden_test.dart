import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:myapp/features/auth/presentation/pages/login_page.dart';

import '_helpers.dart';

void main() {
  testGoldens(
    'LoginPage matches golden in mobile + desktop',
    (tester) async {
      final overrides = await defaultGoldenOverrides();
      final widget = buildForGolden(
        child: const LoginPage(),
        overrides: overrides,
      );
      await tester.pumpWidgetBuilder(widget);
      await multiScreenGolden(
        tester,
        'login_page',
        devices: goldenDevices,
      );
    },
    tags: ['golden'],
  );
}
