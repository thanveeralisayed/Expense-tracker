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

  testWidgets('Reproduction & Verification test: Adding transaction with category selected should not show uncategorized notice or badge', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    // 1. Boot app with empty database
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

    // 2. Create account with opening balance
    await tester.tap(find.text('+ Create Your First Account (e.g. Cash, Bank)'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Account Name'), 'Cash');
    await tester.enterText(find.widgetWithText(TextField, 'Opening Balance'), '500');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pumpAndSettle();

    // 3. Add an expense transaction with category selected
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Enter amount 100
    await tester.tap(find.widgetWithText(InkWell, '1'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();

    // Select category 'Groceries' from dropdown
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();

    // Save transaction
    await tester.tap(find.widgetWithText(FilledButton, 'Save Entry'));
    await tester.pumpAndSettle();

    // 4. Navigate to Categories page
    final categoriesBtn = find.byTooltip('Categories');
    await tester.tap(categoriesBtn);
    await tester.pumpAndSettle();

    // 5. Verify no uncategorized notice / badge is shown
    expect(find.text('1 Uncategorized Entry'), findsNothing);
    expect(find.widgetWithText(Badge, '1'), findsNothing);

    // 6. Open Auto-Categorizer Wizard
    final wizardBtn = find.byTooltip('Auto-Categorize Wizard');
    expect(wizardBtn, findsOneWidget);
    await tester.tap(wizardBtn);
    await tester.pumpAndSettle();

    // Verify wizard empty state says all transactions categorized cleanly
    expect(find.text('All transactions categorized!'), findsOneWidget);
    expect(find.text('Every single transaction already has an assigned category.'), findsOneWidget);

    // Dismiss wizard modal sheet by tapping barrier
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Pop back to Dashboard
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // 7. Now add a truly uncategorized transaction (no category selected)
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(InkWell, '4'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '5'));
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, 'Note (e.g. Groceries)'), 'Custom unclassified item');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save Entry'));
    await tester.pumpAndSettle();

    // Navigate to Categories again
    await tester.tap(find.byTooltip('Categories'));
    await tester.pumpAndSettle();

    // Now it should legitimately show 1 uncategorized entry notice and badge
    expect(find.text('1 Uncategorized Entry'), findsOneWidget);
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);

    // Tap "Scan & Fix" on banner
    await tester.tap(find.text('Scan & Fix'));
    await tester.pumpAndSettle();

    // Verify the unmatched uncategorized item is clearly visible in the wizard!
    expect(find.text('Custom unclassified item'), findsOneWidget);
    expect(find.text('UNMATCHED ENTRIES (1)'), findsOneWidget);

    // Dismiss wizard
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Pop back to Dashboard
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await mockDb.close();
  });
}
