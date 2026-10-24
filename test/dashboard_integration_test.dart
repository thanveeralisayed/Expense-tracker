import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';
import 'package:expense_tracker/core/services/backup_restore_service.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Dashboard renders restored backup data and filters by account', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final restoreService = BackupRestoreService(db);

    // 1. Restore real file backup using runAsync (required for real disk I/O in testWidgets)
    await tester.runAsync(() async {
      final res = await restoreService.restoreBackup('myexpenses-backup-20261006-094710');
      expect(res.success, isTrue);
    });

    // 2. Pump the application
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
        child: const ExpenseTrackerApp(),
      ),
    );

    // Settle async stream & future providers
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 3. Verify Total Balance Card shows the exact aggregated net balance: -₹3,26,336.00
    expect(find.text('-₹3,26,336.00'), findsOneWidget);
    expect(find.text('₹3,26,995.00'), findsOneWidget); // Outflow
    expect(find.text('₹659.00'), findsOneWidget);      // Inflow
    expect(find.text('470 Transactions'), findsOneWidget);

    // 4. Verify Account Carousel shows all accounts
    expect(find.text('All Accounts'), findsOneWidget);
    expect(find.text('Home Expense'), findsWidgets);
    expect(find.text('Self Expense'), findsWidgets);
    expect(find.text('Extras'), findsWidgets);
    expect(find.text('Hospital Expenses'), findsWidgets);

    // 5. Verify Monthly headers and recent transactions
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('X ray,ecg and echo 2d'), findsOneWidget);

    // 6. Tap "Extras" in the carousel to filter by Extras account
    await tester.tap(find.byKey(const ValueKey('account_card_Extras')));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Verify Extras account balance is shown: -₹1,21,330.00
    expect(find.text('-₹1,21,330.00'), findsWidgets);
    expect(find.text('5 Transactions'), findsOneWidget);
    expect(find.text('Zulfi'), findsOneWidget);

    await db.close();
  });
}
