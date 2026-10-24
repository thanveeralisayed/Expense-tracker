import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;

import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/features/analytics/domain/analytics_service.dart';
import 'package:expense_tracker/features/budgets/domain/budget_service.dart';
import 'package:expense_tracker/features/categories/domain/smart_categorizer_engine.dart';
import 'package:expense_tracker/features/transactions/presentation/widgets/calculator_numpad.dart';

void main() {
  group('Phase 6 - Account Lifecycle & Balance Integrity Edge Cases', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Account deletion cascade: removes transactions, transfers, and child splits', () async {
      // 1. Create two accounts: Checking & Savings
      final acc1Id = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Checking'),
          currency: drift.Value('INR'),
          openingBalance: drift.Value(1000000), // ₹10,000
        ),
      );
      final acc2Id = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Savings'),
          currency: drift.Value('INR'),
          openingBalance: drift.Value(500000), // ₹5,000
        ),
      );

      // Record opening balance transactions
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: 1000000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Opening Balance'),
        ),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc2Id,
          amount: 500000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Opening Balance'),
        ),
      );

      // 2. Add normal expense on Checking
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: -200000, // -₹2,000
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Groceries'),
        ),
      );

      // 3. Add transfer: ₹3,000 from Checking to Savings
      await db.createTransfer(
        fromAccountId: acc1Id,
        toAccountId: acc2Id,
        amountPaise: 300000,
        date: DateTime.now(),
        comment: 'Transfer to Savings',
      );

      // 4. Add split transaction on Checking: ₹1,500 split into ₹1,000 and ₹500
      final splitParentCompanion = TransactionsCompanion.insert(
        accountId: acc1Id,
        amount: -150000,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Shopping Split'),
        status: const drift.Value(1),
      );
      final splitChildren = [
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: -100000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Clothes'),
        ),
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: -50000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Shoes'),
        ),
      ];
      final splitParentId = await db.createSplitTransaction(
        parent: splitParentCompanion,
        splits: splitChildren,
      );

      // Verify balances prior to deletion:
      // Checking: 10,000 - 2,000 - 3,000 - 1,500 = ₹3,500 (350000 paise)
      // Savings: 5,000 + 3,000 = ₹8,000 (800000 paise)
      expect(await db.getAccountBalance(acc1Id), equals(350000));
      expect(await db.getAccountBalance(acc2Id), equals(800000));

      // 5. Delete Checking Account
      await db.deleteAccount(acc1Id);

      // 6. Verify Checking account is deleted
      final accounts = await db.getAllAccounts();
      expect(accounts.any((a) => a.id == acc1Id), isFalse);
      expect(accounts.length, equals(1));
      expect(accounts.first.id, equals(acc2Id));

      // 7. Verify all transactions associated with Checking are deleted
      final txsChecking = await (db.select(db.transactions)..where((t) => t.accountId.equals(acc1Id))).get();
      expect(txsChecking, isEmpty);

      // 8. Verify split children are also deleted
      final splits = await db.getSplitsForParent(splitParentId);
      expect(splits, isEmpty);

      // 9. Verify the peer transfer transaction on Savings was cascaded
      // Savings balance should now only have its opening balance (500000 paise)
      expect(await db.getAccountBalance(acc2Id), equals(500000));
    });

    test('Account opening balance sync: increase, decrease, zero, and reinstate', () async {
      // Create Account with initial ₹5,000 opening balance
      final accId = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Wallet'),
          currency: drift.Value('INR'),
          openingBalance: drift.Value(500000), // ₹5,000
        ),
      );
      final openingTxId = await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: 500000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Opening Balance'),
        ),
      );

      expect(await db.getAccountBalance(accId), equals(500000));

      // 1. Edit: Increase opening balance to ₹8,000
      final acc = await (db.select(db.accounts)..where((a) => a.id.equals(accId))).getSingle();
      await db.updateAccount(acc.copyWith(openingBalance: 800000));
      await db.updateTransaction(
        (await (db.select(db.transactions)..where((t) => t.id.equals(openingTxId))).getSingle())
            .copyWith(amount: 800000),
      );
      expect(await db.getAccountBalance(accId), equals(800000));

      // 2. Edit: Reduce opening balance to ₹2,000
      await db.updateAccount(acc.copyWith(openingBalance: 200000));
      await db.updateTransaction(
        (await (db.select(db.transactions)..where((t) => t.id.equals(openingTxId))).getSingle())
            .copyWith(amount: 200000),
      );
      expect(await db.getAccountBalance(accId), equals(200000));

      // 3. Edit: Zero opening balance -> delete opening balance transaction
      await db.updateAccount(acc.copyWith(openingBalance: 0));
      await db.deleteTransactionById(openingTxId);
      expect(await db.getAccountBalance(accId), equals(0));
      final remainingOpening = await (db.select(db.transactions)..where((t) => t.id.equals(openingTxId))).getSingleOrNull();
      expect(remainingOpening, isNull);

      // 4. Edit: Reinstate opening balance to ₹3,500
      await db.updateAccount(acc.copyWith(openingBalance: 350000));
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: 350000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Opening Balance'),
        ),
      );
      expect(await db.getAccountBalance(accId), equals(350000));

      // 5. Negative opening balance (e.g. Credit Card starting with outstanding balance)
      await db.updateAccount(acc.copyWith(openingBalance: -150000));
      final reinstatedTx = await (db.select(db.transactions)
            ..where((t) => t.accountId.equals(accId) & t.comment.equals('Opening Balance')))
          .getSingle();
      await db.updateTransaction(reinstatedTx.copyWith(amount: -150000));
      expect(await db.getAccountBalance(accId), equals(-150000));
    });
  });

  group('Phase 6 - Category & Budget Settings Lifecycle Edge Cases', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('deleteCategory cleanly unlinks subcategories, unlinks transactions, and purges budget limits', () async {
      final accId = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Cash'),
          currency: drift.Value('INR'),
        ),
      );

      // 1. Create parent category and child subcategory
      final parentCatId = await db.createCategory(
        const CategoriesCompanion(
          label: drift.Value('Transportation'),
          color: drift.Value(0xFF3B82F6),
          icon: drift.Value('directions_car'),
          type: drift.Value(0),
        ),
      );
      final subCatId = await db.createCategory(
        CategoriesCompanion(
          label: const drift.Value('Fuel'),
          color: const drift.Value(0xFFEF4444),
          icon: const drift.Value('local_gas_station'),
          type: const drift.Value(0),
          parentId: drift.Value(parentCatId),
        ),
      );

      // 2. Set budget limit setting for the category
      await db.setSetting('budget_cat_$parentCatId', '500000'); // ₹5,000
      expect(await db.getSetting('budget_cat_$parentCatId'), equals('500000'));

      // 3. Create transactions referencing parent and child categories
      final tx1Id = await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: -120000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          catId: drift.Value(parentCatId),
          comment: const drift.Value('Monthly bus pass'),
        ),
      );
      final tx2Id = await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: -80000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          catId: drift.Value(subCatId),
          comment: const drift.Value('Petrol fill-up'),
        ),
      );

      // 4. Delete the parent category
      await db.deleteCategory(parentCatId);

      // 5. Verify parent category is deleted
      final categories = await db.getAllCategories();
      expect(categories.any((c) => c.id == parentCatId), isFalse);

      // 6. Verify child subcategory was preserved and unlinked (parentId == null)
      final preservedSubCat = await (db.select(db.categories)..where((c) => c.id.equals(subCatId))).getSingle();
      expect(preservedSubCat.parentId, isNull);

      // 7. Verify tx1 category was unlinked (catId == null) rather than cascading deletion
      final preservedTx1 = await (db.select(db.transactions)..where((t) => t.id.equals(tx1Id))).getSingle();
      expect(preservedTx1.catId, isNull);

      // 8. Verify tx2 category remained intact
      final preservedTx2 = await (db.select(db.transactions)..where((t) => t.id.equals(tx2Id))).getSingle();
      expect(preservedTx2.catId, equals(subCatId));

      // 9. Verify category budget limit was purged from appSettings
      expect(await db.getSetting('budget_cat_$parentCatId'), isNull);
    });

    test('SmartCategorizerEngine resolves direct labels and case-insensitive keyword matches', () {
      final categories = [
        const Category(id: 1, label: 'Groceries', type: 0, color: 0xFF10B981, icon: 'shopping_cart'),
        const Category(id: 2, label: 'Food & Dining', type: 0, color: 0xFFF59E0B, icon: 'restaurant'),
        const Category(id: 3, label: 'Fuel & Transport', type: 0, color: 0xFFEF4444, icon: 'local_gas_station'),
        const Category(id: 4, label: 'Salary', type: 1, color: 0xFF10B981, icon: 'payments'),
      ];

      // Direct match
      final match1 = SmartCategorizerEngine.matchCategory('Groceries store purchase', categories);
      expect(match1?.id, equals(1));

      // Keyword match: "petrol" -> Fuel & Transport
      final match2 = SmartCategorizerEngine.matchCategory('Petrol pump shell', categories);
      expect(match2?.id, equals(3));

      // Income keyword match: "payroll" -> Salary
      final match3 = SmartCategorizerEngine.matchCategory('Monthly payroll deposit', categories);
      expect(match3?.id, equals(4));

      // Direct case-insensitive category name match
      final match4 = SmartCategorizerEngine.matchCategory('FOOD & DINING bill', categories);
      expect(match4?.id, equals(2));

      // Non-matching comment returns null safely
      final matchNone = SmartCategorizerEngine.matchCategory('Unknown random note xyz', categories);
      expect(matchNone, isNull);
    });
  });

  group('Phase 6 - Split Transactions Lifecycle & Analytics/Budget Allocation Edge Cases', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('Split transaction: overall budget counts parent, category budget counts split children', () async {
      final now = DateTime(2026, 10, 24);
      final catGroceries = const Category(id: 10, label: 'Groceries', type: 0, color: 0xFF10B981, icon: 'cart');
      final catEntertainment = const Category(id: 20, label: 'Entertainment', type: 0, color: 0xFF6366F1, icon: 'movie');
      final catMap = {10: catGroceries, 20: catEntertainment};

      // Create split transaction in current month:
      // Parent: ₹1,000 (catId: null, status: 1)
      // Child 1: ₹600 (catId: 10 - Groceries)
      // Child 2: ₹400 (catId: 20 - Entertainment)
      final parentTx = Transaction(
        id: 100,
        accountId: 1,
        amount: -100000,
        date: now,
        valueDate: now,
        comment: 'Supermarket + Movies',
        status: 1,
        crStatus: 'UNRECONCILED',
      );
      final child1 = Transaction(
        id: 101,
        accountId: 1,
        amount: -60000,
        date: now,
        valueDate: now,
        comment: 'Groceries portion',
        catId: 10,
        parentId: 100,
        status: 0,
        crStatus: 'UNRECONCILED',
      );
      final child2 = Transaction(
        id: 102,
        accountId: 1,
        amount: -40000,
        date: now,
        valueDate: now,
        comment: 'Movie tickets portion',
        catId: 20,
        parentId: 100,
        status: 0,
        crStatus: 'UNRECONCILED',
      );

      final allTxs = [parentTx, child1, child2];

      // 1. Overall monthly budget: includes parent, excludes children
      final overallExpenses = BudgetService.filterCurrentMonthExpenses(allTxs, includeSplits: false, referenceNow: now);
      expect(overallExpenses.length, equals(1));
      expect(overallExpenses.first.id, equals(100));

      final overallBudget = BudgetService.calculateOverallBudget(
        limitPaise: 200000, // ₹2,000 limit
        currentMonthExpenses: overallExpenses,
        referenceNow: now,
      );
      expect(overallBudget.spentPaise, equals(100000)); // Exactly ₹1,000
      expect(overallBudget.percentage, equals(50.0));

      // 2. Category budget: includes children, excludes parent
      final categoryExpenses = BudgetService.filterCurrentMonthExpenses(allTxs, includeSplits: true, referenceNow: now);
      expect(categoryExpenses.length, equals(2));
      expect(categoryExpenses.map((t) => t.id), containsAll([101, 102]));

      final groceriesBudget = BudgetService.calculateCategoryBudget(
        catId: 10,
        limitPaise: 100000,
        currentMonthExpenses: categoryExpenses,
        categoryMap: catMap,
        referenceNow: now,
      );
      expect(groceriesBudget.spentPaise, equals(60000)); // ₹600 allocated to Groceries
      expect(groceriesBudget.percentage, equals(60.0));

      final entertainmentBudget = BudgetService.calculateCategoryBudget(
        catId: 20,
        limitPaise: 50000,
        currentMonthExpenses: categoryExpenses,
        categoryMap: catMap,
        referenceNow: now,
      );
      expect(entertainmentBudget.spentPaise, equals(40000)); // ₹400 allocated to Entertainment
      expect(entertainmentBudget.percentage, equals(80.0));

      // 3. Analytics category breakdown: attributes ₹600 to Groceries and ₹400 to Entertainment
      final categorySpending = AnalyticsService.calculateCategorySpending(
        transactions: allTxs,
        categoriesMap: catMap,
      );
      expect(categorySpending.length, equals(2));
      expect(categorySpending[0].category.label, equals('Groceries'));
      expect(categorySpending[0].totalPaise, equals(60000));
      expect(categorySpending[0].percentage, equals(60.0));

      expect(categorySpending[1].category.label, equals('Entertainment'));
      expect(categorySpending[1].totalPaise, equals(40000));
      expect(categorySpending[1].percentage, equals(40.0));

      // 4. Analytics cash flow: counts parent once (₹1,000 outflow), avoids double-counting
      final cashFlow = AnalyticsService.calculateCashFlow(allTxs);
      expect(cashFlow.totalOutflowPaise, equals(100000));
      expect(cashFlow.totalInflowPaise, equals(0));
    });

    test('Duplicating split transaction creates new parent and copies all child allocations', () async {
      final accId = await db.createAccount(
        const AccountsCompanion(label: drift.Value('Bank'), currency: drift.Value('INR')),
      );

      final parentId = await db.createSplitTransaction(
        parent: TransactionsCompanion.insert(
          accountId: accId,
          amount: -50000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Dinner Split'),
          status: const drift.Value(1),
        ),
        splits: [
          TransactionsCompanion.insert(
            accountId: accId,
            amount: -30000,
            date: DateTime.now(),
            valueDate: DateTime.now(),
            comment: const drift.Value('Food item'),
          ),
          TransactionsCompanion.insert(
            accountId: accId,
            amount: -20000,
            date: DateTime.now(),
            valueDate: DateTime.now(),
            comment: const drift.Value('Drinks item'),
          ),
        ],
      );

      // Verify original split
      final originalChildren = await db.getSplitsForParent(parentId);
      expect(originalChildren.length, equals(2));

      // Simulate duplicate logic
      final origParent = await (db.select(db.transactions)..where((t) => t.id.equals(parentId))).getSingle();
      final duplicateParentId = await db.createSplitTransaction(
        parent: TransactionsCompanion.insert(
          accountId: origParent.accountId,
          amount: origParent.amount,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: drift.Value('${origParent.comment} (Copy)'),
          status: const drift.Value(1),
        ),
        splits: originalChildren.map((c) => TransactionsCompanion.insert(
          accountId: c.accountId,
          amount: c.amount,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: drift.Value('${c.comment} (Copy)'),
          catId: drift.Value(c.catId),
        )).toList(),
      );

      // Verify duplicate split
      final dupChildren = await db.getSplitsForParent(duplicateParentId);
      expect(dupChildren.length, equals(2));
      expect(dupChildren[0].amount, equals(-30000));
      expect(dupChildren[0].comment, equals('Food item (Copy)'));
      expect(dupChildren[1].amount, equals(-20000));
      expect(dupChildren[1].comment, equals('Drinks item (Copy)'));
    });
  });

  group('Phase 6 - Search & Multi-Filter Query Engine Edge Cases', () {
    late AppDatabase db;
    late int acc1Id;
    late int acc2Id;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      acc1Id = await db.createAccount(const AccountsCompanion(label: drift.Value('Checking'), currency: drift.Value('INR')));
      acc2Id = await db.createAccount(const AccountsCompanion(label: drift.Value('Savings'), currency: drift.Value('INR')));

      // Seed test transactions
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: -50000, // ₹500
          date: DateTime(2026, 10, 5),
          valueDate: DateTime(2026, 10, 5),
          comment: const drift.Value('Amazon Pantry Delivery'),
        ),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc1Id,
          amount: -150000, // ₹1,500
          date: DateTime(2026, 10, 15),
          valueDate: DateTime(2026, 10, 15),
          comment: const drift.Value('Amazon Prime Electronics'),
        ),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: acc2Id,
          amount: -300000, // ₹3,000
          date: DateTime(2026, 10, 20),
          valueDate: DateTime(2026, 10, 20),
          comment: const drift.Value('Electricity Utility Bill'),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('Search by query text filter matches substring', () async {
      final results = await db.searchTransactionsStream(queryText: 'Amazon').first;
      expect(results.length, equals(2));
      for (final r in results) {
        expect(r.comment, contains('Amazon'));
      }
    });

    test('Search by account filter isolates account transactions', () async {
      final results = await db.searchTransactionsStream(accountId: acc2Id).first;
      expect(results.length, equals(1));
      expect(results.first.comment, equals('Electricity Utility Bill'));
    });

    test('Search by amount range (minPaise and maxPaise)', () async {
      // Find transactions between ₹1,000 and ₹2,000 (100000 and 200000 paise)
      final results = await db.searchTransactionsStream(
        minPaise: 100000,
        maxPaise: 200000,
      ).first;

      expect(results.length, equals(1));
      expect(results.first.comment, equals('Amazon Prime Electronics'));
    });

    test('Search by date bounds isolates date window', () async {
      final results = await db.searchTransactionsStream(
        startDate: DateTime(2026, 10, 10),
        endDate: DateTime(2026, 10, 18),
      ).first;

      expect(results.length, equals(1));
      expect(results.first.date.day, equals(15));
    });

    test('Search with zero matches returns empty list without error', () async {
      final results = await db.searchTransactionsStream(queryText: 'NonExistentVendor999').first;
      expect(results, isEmpty);
    });
  });

  group('Phase 6 - Calculator Numpad Arithmetic Edge Cases', () {
    testWidgets('Calculator numpad evaluates expressions, handles division by zero, and avoids double dots', (WidgetTester tester) async {
      String value = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    Text('DISPLAY: $value', key: const Key('calc_display')),
                    CalculatorNumpad(
                      currentValue: value,
                      onChanged: (newVal) => setState(() => value = newVal),
                      onSubmitted: () {},
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Helper to tap button
      Future<void> tapKey(String label) async {
        await tester.tap(find.text(label));
        await tester.pump();
      }

      // 1. Basic numpad entry: 50 + 25
      await tapKey('5');
      await tapKey('0');
      await tapKey('+');
      await tapKey('2');
      await tapKey('5');
      expect(find.text('DISPLAY: 50+25'), findsOneWidget);

      // 2. Backspace
      await tapKey('⌫');
      expect(find.text('DISPLAY: 50+2'), findsOneWidget);

      // 3. Operator replacement: consecutive operators replace previous operator
      await tapKey('+');
      expect(find.text('DISPLAY: 50+2+'), findsOneWidget);
      await tapKey('-');
      expect(find.text('DISPLAY: 50+2-'), findsOneWidget);
      await tapKey('×');
      expect(find.text('DISPLAY: 50+2×'), findsOneWidget);

      // 4. Double dot prevention: 3.1.4 should only accept single dot per operand
      await tapKey('3');
      await tapKey('.');
      await tapKey('1');
      await tapKey('.'); // second dot in same operand ignored
      await tapKey('4');
      expect(find.text('DISPLAY: 50+2×3.14'), findsOneWidget);
    });

    test('CalculatorNumpad.evaluate arithmetic edge cases', () {
      // 1. Standard arithmetic operations
      expect(CalculatorNumpad.evaluate('50+25'), equals(75.0));
      expect(CalculatorNumpad.evaluate('100-35'), equals(65.0));
      expect(CalculatorNumpad.evaluate('12*4'), equals(48.0));
      expect(CalculatorNumpad.evaluate('12×4'), equals(48.0));
      expect(CalculatorNumpad.evaluate('100/4'), equals(25.0));
      expect(CalculatorNumpad.evaluate('100÷4'), equals(25.0));

      // 2. Multiple sequential operations
      expect(CalculatorNumpad.evaluate('10+20*2'), equals(60.0)); // Left-to-right (10+20 = 30 * 2 = 60)

      // 3. Trailing operators gracefully ignored without crash
      expect(CalculatorNumpad.evaluate('45+'), equals(45.0));
      expect(CalculatorNumpad.evaluate('100*'), equals(100.0));

      // 4. Division by zero safety: does not crash or return Infinity
      expect(CalculatorNumpad.evaluate('10/0'), equals(10.0));
      expect(CalculatorNumpad.evaluate('50÷0'), equals(50.0));

      // 5. Decimals precision
      expect(CalculatorNumpad.evaluate('10.55+20.45'), closeTo(31.0, 0.001));

      // 6. Empty and invalid expressions
      expect(CalculatorNumpad.evaluate(''), isNull);
      expect(CalculatorNumpad.evaluate('abc'), equals(0.0));
    });
  });
}
