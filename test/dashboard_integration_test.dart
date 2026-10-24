import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Dashboard renders restored backup data and filters by account', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // 1. Seed in-memory database with realistic multi-account test data
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(1), label: 'Home Expense', currency: const drift.Value('INR')),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(2), label: 'Self Expense', currency: const drift.Value('INR')),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(3), label: 'Extras', currency: const drift.Value('INR')),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(4), label: 'Hospital Expenses', currency: const drift.Value('INR')),
    );

    // Outflow: 15,000 + 10,000 + 2,500 = 27,500.00 (2750000 paise)
    // Inflow: 50,000.00 (5000000 paise)
    // Net: +22,500.00 (2250000 paise)
    final testDate = DateTime(2026, 10, 15, 14, 30);
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        accountId: 4,
        amount: -1500000,
        comment: const drift.Value('X ray,ecg and echo 2d'),
        date: testDate,
        valueDate: testDate,
      ),
    );
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        accountId: 3,
        amount: -1000000,
        comment: const drift.Value('Zulfi'),
        date: testDate,
        valueDate: testDate,
      ),
    );
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        accountId: 1,
        amount: -250000,
        comment: const drift.Value('Groceries'),
        date: testDate,
        valueDate: testDate,
      ),
    );
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        accountId: 2,
        amount: 5000000,
        comment: const drift.Value('Salary'),
        date: testDate,
        valueDate: testDate,
      ),
    );

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

    // 3. Verify Total Balance Card shows the exact aggregated net balance: +₹22,500.00
    expect(find.text('+₹22,500.00'), findsWidgets);
    expect(find.text('₹27,500.00'), findsOneWidget); // Outflow
    expect(find.text('₹50,000.00'), findsWidgets);   // Inflow
    expect(find.text('4 Transactions'), findsOneWidget);

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

    // Verify Extras account balance is shown: -₹10,000.00
    expect(find.text('-₹10,000.00'), findsWidgets);
    expect(find.text('1 Transactions'), findsOneWidget);
    expect(find.text('Zulfi'), findsOneWidget);

    await db.close();
  });
}
