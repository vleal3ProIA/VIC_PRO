import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:myapp/features/auth/presentation/pages/register_page.dart';

import '_helpers.dart';

void main() {
  testGoldens(
    'RegisterPage matches golden in mobile + desktop',
    (tester) async {
      final overrides = await defaultGoldenOverrides();
      final widget = buildForGolden(
        child: const RegisterPage(),
        overrides: overrides,
      );
      await tester.pumpWidgetBuilder(widget);
      await multiScreenGolden(
        tester,
        'register_page',
        devices: goldenDevices,
      );
    },
    tags: ['golden'],
  );
}
