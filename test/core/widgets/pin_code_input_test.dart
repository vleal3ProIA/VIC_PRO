import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/core/widgets/pin_code_input.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 400, child: child)));

void main() {
  testWidgets('renders 6 cells by default', (tester) async {
    await tester.pumpWidget(_wrap(PinCodeInput(onChanged: (_) {})));
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('emits joined code as user types', (tester) async {
    final history = <String>[];
    String? completed;
    await tester.pumpWidget(
      _wrap(
        PinCodeInput(
          onChanged: history.add,
          onCompleted: (v) => completed = v,
        ),
      ),
    );

    final fields = find.byType(TextField);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(fields.at(i), '${i + 1}');
      await tester.pump();
    }

    expect(history.last, '123456');
    expect(completed, '123456');
  });

  testWidgets('paste fills all cells in one go', (tester) async {
    String? completed;
    await tester.pumpWidget(
      _wrap(
        PinCodeInput(
          onChanged: (_) {},
          onCompleted: (v) => completed = v,
        ),
      ),
    );

    final first = find.byType(TextField).first;
    await tester.enterText(first, '987654');
    await tester.pump();

    expect(completed, '987654');
  });

  testWidgets('non-digit characters are stripped', (tester) async {
    String? completed;
    await tester.pumpWidget(
      _wrap(
        PinCodeInput(
          onChanged: (_) {},
          onCompleted: (v) => completed = v,
        ),
      ),
    );

    final first = find.byType(TextField).first;
    await tester.enterText(first, '12-34-56');
    await tester.pump();

    expect(completed, '123456');
  });
}
