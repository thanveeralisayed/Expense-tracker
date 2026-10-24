import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Bottom Navigation flow to Analytics and Budgets screens', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
        ],
        child: const ExpenseTrackerApp(),
      ),
    );

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. Verify on Dashboard
    expect(find.text('My Expenses'), findsOneWidget);

    // 2. Tap "Analytics" in bottom navigation bar
    await tester.tap(find.widgetWithText(NavigationDestination, 'Analytics'));
    await tester.pumpAndSettle();

    // 3. Verify AnalyticsScreen opened
    expect(find.text('Financial Analytics'), findsOneWidget);
    expect(find.text('Cash Flow & Savings'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
    expect(find.text('This Year'), findsOneWidget);

    // Switch timeframe chip to "This Year"
    await tester.tap(find.text('This Year'));
    await tester.pumpAndSettle();

    // Tap back button
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 4. Verify back on Dashboard
    expect(find.text('My Expenses'), findsOneWidget);

    // 5. Tap "Budgets" in bottom navigation bar
    await tester.tap(find.widgetWithText(NavigationDestination, 'Budgets'));
    await tester.pumpAndSettle();

    // 6. Verify BudgetScreen opened
    expect(find.text('Monthly Budgets'), findsOneWidget);
    expect(find.text('No Overall Budget Set'), findsOneWidget);

    // Tap "Set Monthly Budget"
    await tester.tap(find.text('Set Monthly Budget'));
    await tester.pumpAndSettle();

    // Verify SetBudgetDialog opened
    expect(find.text('Set New Budget'), findsOneWidget);
    expect(find.text('Monthly Limit (₹)'), findsOneWidget);

    // Enter budget 30000
    await tester.enterText(find.byType(TextField), '30000');
    await tester.pump();

    // Tap "Save Budget"
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save Budget'));
    await tester.pumpAndSettle();

    // 7. Verify overall budget card is now displayed with 30,000 limit
    expect(find.text('Total Monthly Budget'), findsOneWidget);
    expect(find.textContaining('30,000'), findsWidgets);
    expect(find.textContaining('On Track'), findsOneWidget);

    // 8. Tap the budget card to edit it and delete
    await tester.tap(find.text('Total Monthly Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Budget'), findsOneWidget);
    final deleteIcon = find.byIcon(Icons.delete_outline);
    expect(deleteIcon, findsOneWidget);
    await tester.tap(deleteIcon);
    await tester.pumpAndSettle();

    // 9. Verify budget was deleted and empty card restored
    expect(find.text('No Overall Budget Set'), findsOneWidget);

    await mockDb.close();
  });
}
