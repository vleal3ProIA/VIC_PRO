import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/features/welcome/presentation/pages/welcome_page.dart';

import '../../../helpers/pump_widget.dart';

void main() {
  group('WelcomePage', () {
    testWidgets('renders app title and "under construction" copy',
        (tester) async {
      await pumpForTest(tester, child: const WelcomePage());
      expect(find.text('myapp'), findsWidgets);
      expect(find.text('Under construction'), findsOneWidget);
    });

    testWidgets('legal footer exposes Terms · Privacy · Cookies',
        (tester) async {
      await pumpForTest(tester, child: const WelcomePage());
      expect(
        find.widgetWithText(TextButton, 'Terms of Service'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Privacy Policy'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Cookie policy'),
        findsOneWidget,
      );
    });
  });
}
