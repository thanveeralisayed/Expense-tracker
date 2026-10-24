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

  testWidgets('Category UI & Smart Auto-Categorize Wizard Integration Flow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    // 1. Seed accounts and categories
    await mockDb.into(mockDb.accounts).insert(
      const AccountsCompanion(id: drift.Value(1), label: drift.Value('Cash')),
    );
    await mockDb.seedDefaultCategoriesIfEmpty();

    // Insert 2 uncategorized transactions
    final now = DateTime.now();
    await mockDb.createTransaction(
      TransactionsCompanion.insert(
        amount: -50000,
        accountId: 1,
        date: now,
        valueDate: now,
        comment: const drift.Value('Filled petrol for bike'),
      ),
    );
    await mockDb.createTransaction(
      TransactionsCompanion.insert(
        amount: -12000,
        accountId: 1,
        date: now,
        valueDate: now,
        comment: const drift.Value('Morning milk packet'),
      ),
    );

    // 2. Boot App
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

    // 3. Navigate to CategoryListScreen via AppBar icon
    final categoriesBtn = find.byTooltip('Categories');
    expect(categoriesBtn, findsOneWidget);
    await tester.tap(categoriesBtn);
    await tester.pumpAndSettle();

    // Verify CategoryListScreen opened
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);

    // 4. Verify Uncategorized banner is visible
    expect(find.text('2 Uncategorized Entries'), findsOneWidget);
    expect(find.text('Scan & Fix'), findsOneWidget);

    // 5. Tap "Scan & Fix" to open AutoCategorizeWizardSheet
    await tester.tap(find.text('Scan & Fix'));
    await tester.pumpAndSettle();

    // Verify Wizard sheet opened with suggestions
    expect(find.text('Smart Auto-Categorizer'), findsOneWidget);
    expect(find.text('Filled petrol for bike'), findsOneWidget);
    expect(find.text('Morning milk packet'), findsOneWidget);
    expect(find.text('Fuel & Transport'), findsWidgets);
    expect(find.text('Groceries'), findsWidgets);

    // 6. Apply Batch
    final applyBtn = find.widgetWithText(FilledButton, 'Apply to 2 Transactions');
    expect(applyBtn, findsOneWidget);
    await tester.tap(applyBtn);
    await tester.pumpAndSettle();

    // Verify returning to category list and uncategorized banner is gone
    expect(find.text('2 Uncategorized Entries'), findsNothing);

    // 7. Test creating a new category
    final addCategoryBtn = find.widgetWithText(FloatingActionButton, 'New Category');
    await tester.tap(addCategoryBtn);
    await tester.pumpAndSettle();

    expect(find.text('New Category'), findsWidgets);
    await tester.enterText(find.widgetWithText(TextFormField, 'Category Name'), 'Pet Care');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Create Category'));
    await tester.pumpAndSettle();

    // Verify "Pet Care" appears in the category list
    expect(find.text('Pet Care'), findsOneWidget);

    // Pop back to Dashboard
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await mockDb.close();
  });

  testWidgets('Live Category Auto-Suggestion during transaction creation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    await mockDb.into(mockDb.accounts).insert(
      const AccountsCompanion(id: drift.Value(1), label: drift.Value('Main Wallet')),
    );
    await mockDb.seedDefaultCategoriesIfEmpty();

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

    // 1. Open Add Transaction Sheet
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Enter amount 250
    await tester.tap(find.widgetWithText(InkWell, '2'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '5'));
    await tester.pump();
    await tester.tap(find.widgetWithText(InkWell, '0'));
    await tester.pump();

    // Initially category is "No Category"
    expect(find.text('No Category'), findsOneWidget);

    // 2. Type note "Dinner with family at restaurant"
    final noteField = find.widgetWithText(TextField, 'Note (e.g. Milk, Petrol, Roofing)');
    await tester.enterText(noteField, 'Dinner with family at restaurant');
    await tester.pump();

    // Verify auto-categorizer automatically selected "Food & Dining"!
    expect(find.text('Food & Dining'), findsWidgets);

    // 3. Save Entry
    await tester.tap(find.widgetWithText(FilledButton, 'Save Entry'));
    await tester.pumpAndSettle();

    // 4. Verify transaction appears in dashboard with Food & Dining badge
    expect(find.text('Dinner with family at restaurant'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);

    // Tap transaction to open Detail sheet
    final txFinder = find.text('Dinner with family at restaurant');
    await tester.ensureVisible(txFinder);
    await tester.tap(txFinder);
    await tester.pumpAndSettle();

    // Verify category displayed in detail sheet
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Food & Dining'), findsWidgets);

    await mockDb.close();
  });
}
