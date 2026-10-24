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

  testWidgets('Settings screen opens, toggles theme, and displays data metrics', (WidgetTester tester) async {
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

    // 1. Verify on Dashboard and tap Settings icon
    final settingsIcon = find.byTooltip('Settings');
    expect(settingsIcon, findsOneWidget);
    await tester.tap(settingsIcon);
    await tester.pumpAndSettle();

    // 2. Verify Settings screen is opened
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);

    // 3. Switch theme mode to Dark
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // 4. Verify financial tools shortcuts are visible
    expect(find.text('Monthly Budgets & Limits'), findsOneWidget);
    expect(find.text('Categories & Rules'), findsOneWidget);

    // 5. Verify database storage stats and about information
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Version 1.0.0 (Phase 5 Build)'), findsOneWidget);

    // 6. Navigate back to Dashboard
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('My Expenses'), findsOneWidget);

    await mockDb.close();
  });
}
