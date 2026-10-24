import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;

import 'package:expense_tracker/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Create 3 test accounts
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(1), label: 'Checking A'),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(2), label: 'Savings B'),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(id: const drift.Value(3), label: 'Wallet C'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Transaction Edge Cases & Stress Testing', () {
    test('High volume insertion (500 transactions) maintains precise balance and totals', () async {
      int expectedExpenses = 0;
      int expectedIncome = 0;

      await db.batch((batch) {
        for (int i = 0; i < 500; i++) {
          final isExpense = i % 2 == 0;
          final amount = isExpense ? -(i + 1) * 100 : (i + 1) * 100;
          if (isExpense) {
            expectedExpenses += -amount;
          } else {
            expectedIncome += amount;
          }

          batch.insert(
            db.transactions,
            TransactionsCompanion.insert(
              accountId: (i % 3) + 1,
              amount: amount,
              date: DateTime(2026, 1, 1).add(Duration(hours: i)),
              valueDate: DateTime(2026, 1, 1).add(Duration(hours: i)),
              comment: drift.Value('Tx #$i'),
            ),
          );
        }
      });

      final totals = await db.getTotals();
      expect(totals['count'], equals(500));
      expect(totals['expenses'], equals(expectedExpenses));
      expect(totals['income'], equals(expectedIncome));
      expect(totals['net'], equals(expectedIncome - expectedExpenses));
    });

    test('Circular inter-account transfers do not affect net worth', () async {
      // Transfer 1: ₹1,000 from Account 1 to Account 2
      await db.createTransfer(
        fromAccountId: 1,
        toAccountId: 2,
        amountPaise: 100000,
        date: DateTime.now(),
        comment: 'Transfer A -> B',
      );

      // Transfer 2: ₹600 from Account 2 to Account 3
      await db.createTransfer(
        fromAccountId: 2,
        toAccountId: 3,
        amountPaise: 60000,
        date: DateTime.now(),
        comment: 'Transfer B -> C',
      );

      // Transfer 3: ₹400 from Account 3 to Account 1
      await db.createTransfer(
        fromAccountId: 3,
        toAccountId: 1,
        amountPaise: 40000,
        date: DateTime.now(),
        comment: 'Transfer C -> A',
      );

      // Account 1: -1,000 + 400 = -600
      // Account 2: +1,000 - 600 = +400
      // Account 3: +600 - 400 = +200
      expect(await db.getAccountBalance(1), equals(-60000));
      expect(await db.getAccountBalance(2), equals(40000));
      expect(await db.getAccountBalance(3), equals(20000));

      // Net worth MUST remain exactly 0
      final totals = await db.getTotals();
      expect(totals['net'], equals(0));
      expect(totals['count'], equals(6)); // 3 transfers * 2 peer records
    });

    test('Split bill with odd paise splits sums exactly and prevents duplicate counting', () async {
      // Total ₹100.00 (10000 paise) split into 3333 + 3333 + 3334
      final parentCompanion = TransactionsCompanion.insert(
        amount: -10000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Dinner with friends (3-way split)'),
        status: const drift.Value(1),
      );

      final splits = [
        TransactionsCompanion.insert(
          amount: -3333,
          accountId: 1,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Friend 1 share'),
        ),
        TransactionsCompanion.insert(
          amount: -3333,
          accountId: 1,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Friend 2 share'),
        ),
        TransactionsCompanion.insert(
          amount: -3334,
          accountId: 1,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('My share'),
        ),
      ];

      final parentId = await db.createSplitTransaction(
        parent: parentCompanion,
        splits: splits,
      );

      // 1. Splits query returns all 3 child items
      final childSplits = await db.getSplitsForParent(parentId);
      expect(childSplits.length, equals(3));
      final childSum = childSplits.fold<int>(0, (sum, c) => sum + c.amount);
      expect(childSum, equals(-10000));

      // 2. Account balance is -10000 (NOT -20000)
      final balance = await db.getAccountBalance(1);
      expect(balance, equals(-10000));

      // 3. Totals count only the parent transaction (1 transaction)
      final totals = await db.getTotals(accountId: 1);
      expect(totals['count'], equals(1));
      expect(totals['expenses'], equals(10000));
    });

    test('Search query handles special characters and edge-case date/amount filters', () async {
      final baseDate = DateTime(2026, 6, 15, 12, 0);

      // Insert diverse transactions
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: 1,
          amount: -50000,
          date: baseDate,
          valueDate: baseDate,
          comment: const drift.Value('Shopping [Special Offer 50%]'),
        ),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: 1,
          amount: -150000,
          date: baseDate.add(const Duration(days: 5)),
          valueDate: baseDate.add(const Duration(days: 5)),
          comment: const drift.Value('Laptop repair (screen + ram)'),
        ),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: 2,
          amount: 200000,
          date: baseDate.add(const Duration(days: 10)),
          valueDate: baseDate.add(const Duration(days: 10)),
          comment: const drift.Value('Consulting bonus'),
        ),
      );

      // Special character search: "[Special Offer"
      final specialTxs = await db.searchTransactionsStream(queryText: 'Special Offer').first;
      expect(specialTxs.length, equals(1));
      expect(specialTxs.first.amount, equals(-50000));

      // Date range filter: between June 14 and June 18 -> only first tx
      final dateFiltered = await db.searchTransactionsStream(
        startDate: DateTime(2026, 6, 14),
        endDate: DateTime(2026, 6, 18),
      ).first;
      expect(dateFiltered.length, equals(1));
      expect(dateFiltered.first.comment, contains('Shopping'));

      // Amount range filter: min 1,000 INR (100000 paise) and max 1,800 INR (180000 paise)
      final amountFiltered = await db.searchTransactionsStream(
        minPaise: 100000,
        maxPaise: 180000,
      ).first;
      expect(amountFiltered.length, equals(1));
      expect(amountFiltered.first.comment, contains('Laptop'));

      // Empty search results for non-existent keyword
      final emptyResults = await db.searchTransactionsStream(queryText: 'NonExistentXYZ').first;
      expect(emptyResults, isEmpty);
    });
  });
}
