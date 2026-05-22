import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/widgets/app_pagination_bar.dart';

import '../../helpers/pump_widget.dart';

void main() {
  IconButton iconButton(WidgetTester tester, IconData icon) {
    return tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)),
    );
  }

  testWidgets('muestra "Page X of Y" y solo habilita Next en la 1.ª página',
      (tester) async {
    await pumpForTest(
      tester,
      child: AppPaginationBar(
        currentPage: 0,
        totalPages: 3,
        onPrevious: () {},
        onNext: () {},
      ),
    );

    expect(find.text('Page 1 of 3'), findsOneWidget);
    // Previous deshabilitado en la primera página, Next habilitado.
    expect(iconButton(tester, Icons.chevron_left).onPressed, isNull);
    expect(iconButton(tester, Icons.chevron_right).onPressed, isNotNull);
  });

  testWidgets('en la última página deshabilita Next y habilita Previous',
      (tester) async {
    await pumpForTest(
      tester,
      child: AppPaginationBar(
        currentPage: 2,
        totalPages: 3,
        onPrevious: () {},
        onNext: () {},
      ),
    );

    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(iconButton(tester, Icons.chevron_left).onPressed, isNotNull);
    expect(iconButton(tester, Icons.chevron_right).onPressed, isNull);
  });

  testWidgets('pulsar Next dispara onNext', (tester) async {
    var nextCalls = 0;
    await pumpForTest(
      tester,
      child: AppPaginationBar(
        currentPage: 0,
        totalPages: 2,
        onPrevious: () {},
        onNext: () => nextCalls++,
      ),
    );

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(nextCalls, 1);
  });

  testWidgets('con una sola página no pinta nada (se oculta)', (tester) async {
    await pumpForTest(
      tester,
      child: AppPaginationBar(
        currentPage: 0,
        totalPages: 1,
        onPrevious: () {},
        onNext: () {},
      ),
    );

    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });
}
