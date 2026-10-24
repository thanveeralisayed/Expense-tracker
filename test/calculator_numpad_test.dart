import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/features/transactions/presentation/widgets/calculator_numpad.dart';

void main() {
  group('CalculatorNumpad Widget & Expression Edge Cases', () {
    testWidgets('Tapping digits appends numbers to current expression', (WidgetTester tester) async {
      String value = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CalculatorNumpad(
                  currentValue: value,
                  onChanged: (val) => setState(() => value = val),
                  onSubmitted: () {},
                );
              },
            ),
          ),
        ),
      );

      // Tap 1, 2, 5
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pump();

      expect(value, equals('125'));
    });

    testWidgets('Tapping backspace removes the last character', (WidgetTester tester) async {
      String value = '250';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CalculatorNumpad(
                  currentValue: value,
                  onChanged: (val) => setState(() => value = val),
                  onSubmitted: () {},
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(InkWell, '⌫'));
      await tester.pump();
      expect(value, equals('25'));

      await tester.tap(find.widgetWithText(InkWell, '⌫'));
      await tester.pump();
      expect(value, equals('2'));

      await tester.tap(find.widgetWithText(InkWell, '⌫'));
      await tester.pump();
      expect(value, equals(''));

      // Backspacing empty string should safely do nothing
      await tester.tap(find.widgetWithText(InkWell, '⌫'));
      await tester.pump();
      expect(value, equals(''));
    });

    testWidgets('Tapping decimal point handles empty and operator splits correctly', (WidgetTester tester) async {
      String value = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CalculatorNumpad(
                  currentValue: value,
                  onChanged: (val) => setState(() => value = val),
                  onSubmitted: () {},
                );
              },
            ),
          ),
        ),
      );

      // Decimal on empty string inserts '0.'
      await tester.tap(find.widgetWithText(InkWell, '.'));
      await tester.pump();
      expect(value, equals('0.'));

      // Tapping decimal again on same number is rejected
      await tester.tap(find.widgetWithText(InkWell, '.'));
      await tester.pump();
      expect(value, equals('0.'));

      // Append '5'
      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pump();
      expect(value, equals('0.5'));

      // Add operator '+'
      await tester.tap(find.widgetWithText(InkWell, '+'));
      await tester.pump();
      expect(value, equals('0.5+'));

      // Next decimal should be allowed on the second operand
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '.'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '5'));
      await tester.pump();
      expect(value, equals('0.5+2.5'));

      // Another decimal on second operand is rejected
      await tester.tap(find.widgetWithText(InkWell, '.'));
      await tester.pump();
      expect(value, equals('0.5+2.5'));
    });

    testWidgets('Consecutive operators replace the previous operator', (WidgetTester tester) async {
      String value = '100';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CalculatorNumpad(
                  currentValue: value,
                  onChanged: (val) => setState(() => value = val),
                  onSubmitted: () {},
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(InkWell, '+'));
      await tester.pump();
      expect(value, equals('100+'));

      // Immediately tap '-' -> should replace '+' with '-'
      await tester.tap(find.widgetWithText(InkWell, '-'));
      await tester.pump();
      expect(value, equals('100-'));

      // Immediately tap '×' -> should replace '-' with '×'
      await tester.tap(find.widgetWithText(InkWell, '×'));
      await tester.pump();
      expect(value, equals('100×'));
    });

    testWidgets('Operator on empty string does nothing', (WidgetTester tester) async {
      String value = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return CalculatorNumpad(
                  currentValue: value,
                  onChanged: (val) => setState(() => value = val),
                  onSubmitted: () {},
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(InkWell, '+'));
      await tester.pump();
      expect(value, equals(''));

      await tester.tap(find.widgetWithText(InkWell, '÷'));
      await tester.pump();
      expect(value, equals(''));
    });
  });
}
