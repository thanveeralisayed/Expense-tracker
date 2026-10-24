import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Complete End-to-End User Flow: Account creation, add expense, duplicate, and delete', (WidgetTester tester) async {
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

    // Settle providers
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 2. Verify empty state prompts to create account
    expect(find.text('+ Create Your First Account (e.g. Cash, Bank)'), findsOneWidget);
    expect(find.text('Create New Account'), findsOneWidget);

    // 3. Tap "+ Create Your First Account"
    await tester.tap(find.text('+ Create Your First Account (e.g. Cash, Bank)'));
    await tester.pumpAndSettle();

    // Verify CreateAccountDialog opened
    expect(find.text('Create New Account'), findsWidgets);

    // Enter account name "Main Wallet" and opening balance "1000"
    await tester.enterText(find.widgetWithText(TextField, 'Account Name'), 'Main Wallet');
    await tester.enterText(find.widgetWithText(TextField, 'Opening Balance'), '1000');
    await tester.pump();

    // Tap "Create Account"
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pumpAndSettle();

    // 4. Verify Account was created and appears in carousel
    expect(find.text('Main Wallet'), findsWidgets);
    expect(find.text('+₹1,000.00'), findsWidgets); // Opening balance

    // 5. Tap FAB (+) to add a transaction
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify AddTransactionSheet is visible
    expect(find.text('Expense'), findsWidgets);
    expect(find.text('Income'), findsWidgets);
    expect(find.text('Transfer'), findsWidgets);

    // Enter amount 250 using calculator numpad keys
    await tester.tap(find.widgetWithText(InkWell, '2'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '5'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();

    // Enter note "Dinner with family"
    await tester.enterText(find.widgetWithText(TextField, 'Note (e.g. Groceries)'), 'Dinner with family');
    await tester.pump();

    // Save transaction
    await tester.tap(find.widgetWithText(FilledButton, 'Save Entry'));
    await tester.pumpAndSettle();

    // 6. Verify Transaction appeared in feed
    expect(find.text('Dinner with family'), findsOneWidget);
    expect(find.text('-₹250.00'), findsOneWidget);

    // Verify Net worth reduced from 1,000 to +750
    expect(find.text('+₹750.00'), findsWidgets);

    // 7. Tap transaction to open Detail Sheet
    await tester.tap(find.text('Dinner with family'));
    await tester.pumpAndSettle();

    // Verify Detail Sheet opened
    expect(find.text('EXPENSE'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Tap "Duplicate"
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    // 8. Verify duplication: Now 2 dinner entries appear in feed and balance reduced to +500
    expect(find.text('Dinner with family (Copy)'), findsOneWidget);
    expect(find.text('+₹500.00'), findsWidgets);

    // Settle and dismiss SnackBar
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // 9. Open duplicated transaction and Delete it
    final copyFinder = find.text('Dinner with family (Copy)');
    await tester.ensureVisible(copyFinder);
    await tester.tap(copyFinder);
    await tester.pumpAndSettle();

    final deleteBtn = find.widgetWithText(FilledButton, 'Delete');
    await tester.ensureVisible(deleteBtn);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Confirm deletion dialog
    expect(find.text('Delete Transaction?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      ),
    );
    await tester.pumpAndSettle();

    // 10. Verify deleted transaction is gone and balance restored to +750
    expect(find.text('Dinner with family (Copy)'), findsNothing);
    expect(find.text('+₹750.00'), findsWidgets);

    await mockDb.close();
  });

  testWidgets('Inter-Account Transfer UI: Debits source, credits destination, and maintains net balance', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    // Seed 2 accounts: Bank (+₹2,000) and Cash (+₹500)
    await mockDb.into(mockDb.accounts).insert(
      AccountsCompanion.insert(id: const Value(1), label: 'Bank Account'),
    );
    await mockDb.into(mockDb.accounts).insert(
      AccountsCompanion.insert(id: const Value(2), label: 'Cash In Hand'),
    );
    await mockDb.createTransaction(
      TransactionsCompanion.insert(
        accountId: 1,
        amount: 200000,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const Value('Initial Bank Balance'),
      ),
    );
    await mockDb.createTransaction(
      TransactionsCompanion.insert(
        accountId: 2,
        amount: 50000,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const Value('Initial Cash Balance'),
      ),
    );

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

    // Net worth = ₹2,500
    expect(find.text('+₹2,500.00'), findsWidgets);

    // Tap FAB (+)
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Tap Transfer tab
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();

    // Enter ₹800 (8, 0, 0)
    await tester.tap(find.widgetWithText(InkWell, '8'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();

    // Enter note "ATM Withdrawal"
    await tester.enterText(find.widgetWithText(TextField, 'Note (e.g. Groceries)'), 'ATM Withdrawal');
    await tester.pump();

    // Save Transfer
    await tester.tap(find.widgetWithText(FilledButton, 'Save Entry'));
    await tester.pumpAndSettle();

    // Net worth remains ₹2,500.00
    expect(find.text('+₹2,500.00'), findsWidgets);

    // Tap "Bank Account" card in carousel to filter
    await tester.tap(find.byKey(const ValueKey('account_card_Bank Account')));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Bank Account: 2,000 - 800 = +₹1,200.00
    expect(find.text('+₹1,200.00'), findsWidgets);

    // Tap "Cash In Hand" card in carousel to filter
    await tester.tap(find.byKey(const ValueKey('account_card_Cash In Hand')));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Cash In Hand: 500 + 800 = +₹1,300.00
    expect(find.text('+₹1,300.00'), findsWidgets);

    await mockDb.close();
  });

  testWidgets('Split Transaction UI: Allocate bill into multiple items with auto-sum and SPLIT badge', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    // Seed 1 account: "Main Account" (+₹5,000)
    await mockDb.into(mockDb.accounts).insert(
      AccountsCompanion.insert(id: const Value(1), label: 'Main Account'),
    );
    await mockDb.createTransaction(
      TransactionsCompanion.insert(
        accountId: 1,
        amount: 500000,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const Value('Opening Funds'),
      ),
    );

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

    // Tap FAB (+)
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Tap "Split" tab
    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();

    // Verify SplitTransactionScreen opened
    expect(find.text('Split Transaction'), findsWidgets);

    // Enter overall description
    await tester.enterText(find.widgetWithText(TextField, 'Overall Description'), 'Supermarket Trip');
    await tester.pump();

    // Enter Split Item 1 amount "600"
    final amountFields = find.widgetWithText(TextField, '0.00');
    await tester.enterText(amountFields.at(0), '600');
    await tester.pump();

    // Enter Split Item 2 amount "400"
    await tester.enterText(amountFields.at(1), '400');
    await tester.pump();

    // Tap Save Split
    final saveSplitBtn = find.widgetWithText(FilledButton, 'Save Split (₹1,000.00)');
    await tester.ensureVisible(saveSplitBtn);
    await tester.tap(saveSplitBtn);
    await tester.pumpAndSettle();

    // Verify returns to dashboard
    expect(find.text('Supermarket Trip'), findsOneWidget);
    expect(find.text('-₹1,000.00'), findsOneWidget);
    expect(find.text('SPLIT'), findsOneWidget);

    // Balance updated: 5,000 - 1,000 = +₹4,000.00
    expect(find.text('+₹4,000.00'), findsWidgets);

    // Tap Supermarket Trip to verify Split Allocations display in detail sheet
    final tripFinder = find.text('Supermarket Trip');
    await tester.ensureVisible(tripFinder);
    await tester.tap(tripFinder);
    await tester.pumpAndSettle();

    expect(find.text('Split Allocations (2)'), findsOneWidget);
    expect(find.text('₹600.00'), findsOneWidget);
    expect(find.text('₹400.00'), findsOneWidget);

    await mockDb.close();
  });
}
