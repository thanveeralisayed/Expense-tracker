import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;

import 'package:expense_tracker/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());

    // Create 2 test accounts
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: const drift.Value(1),
        label: 'Account A',
        openingBalance: const drift.Value(0),
        currency: const drift.Value('INR'),
      ),
    );
    await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: const drift.Value(2),
        label: 'Account B',
        openingBalance: const drift.Value(0),
        currency: const drift.Value('INR'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('Create expense, income, and verify balance calculations', () async {
    // 1. Create Expense of ₹350 (-35000 paise) in Account A
    await db.createTransaction(
      TransactionsCompanion.insert(
        amount: -35000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Groceries store'),
      ),
    );

    // 2. Create Income of ₹1,000 (+100000 paise) in Account A
    await db.createTransaction(
      TransactionsCompanion.insert(
        amount: 100000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Freelance gig'),
      ),
    );

    final balanceA = await db.getAccountBalance(1);
    expect(balanceA, equals(65000)); // +₹650.00

    final totals = await db.getTotals();
    expect(totals['expenses'], equals(35000)); // ₹350.00
    expect(totals['income'], equals(100000));   // ₹1,000.00
    expect(totals['net'], equals(65000));       // ₹650.00
    expect(totals['count'], equals(2));
  });

  test('Execute inter-account transfer and verify linked peer and balances', () async {
    // Transfer ₹500 from Account A to Account B
    await db.createTransfer(
      fromAccountId: 1,
      toAccountId: 2,
      amountPaise: 50000,
      date: DateTime.now(),
      comment: 'Monthly pocket money',
    );

    final balanceA = await db.getAccountBalance(1);
    final balanceB = await db.getAccountBalance(2);

    expect(balanceA, equals(-50000)); // -₹500.00
    expect(balanceB, equals(50000));  // +₹500.00

    // Overall net should be 0 (transfers don't alter net worth)
    final totals = await db.getTotals();
    expect(totals['net'], equals(0));
    expect(totals['count'], equals(2));

    // Verify transfer linkage
    final txs = await db.select(db.transactions).get();
    final fromTx = txs.firstWhere((t) => t.accountId == 1);
    final toTx = txs.firstWhere((t) => t.accountId == 2);

    expect(fromTx.transferAccount, equals(2));
    expect(fromTx.transferPeer, equals(toTx.id));
    expect(toTx.transferAccount, equals(1));
    expect(toTx.transferPeer, equals(fromTx.id));

    // Delete one side of the transfer -> should cascade and delete peer
    await db.deleteTransactionById(fromTx.id);
    final remainingTxs = await db.select(db.transactions).get();
    expect(remainingTxs.isEmpty, isTrue);
  });

  test('Edit and delete transaction lifecycle', () async {
    final id = await db.createTransaction(
      TransactionsCompanion.insert(
        amount: -20000, // ₹200
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Book purchase'),
      ),
    );

    var balance = await db.getAccountBalance(1);
    expect(balance, equals(-20000));

    // Update transaction to ₹250
    final tx = await (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();
    final updated = tx.copyWith(
      amount: -25000,
      comment: const drift.Value('Book purchase + notebook'),
    );
    await db.updateTransaction(updated);

    balance = await db.getAccountBalance(1);
    expect(balance, equals(-25000));

    // Delete transaction
    await db.deleteTransactionById(id);
    balance = await db.getAccountBalance(1);
    expect(balance, equals(0));
  });

  test('Search transactions by comment query and account filter', () async {
    await db.createTransaction(
      TransactionsCompanion.insert(
        amount: -10000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Shell Petrol pump'),
      ),
    );
    await db.createTransaction(
      TransactionsCompanion.insert(
        amount: -4500,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Organic Milk bottle'),
      ),
    );
    await db.createTransaction(
      TransactionsCompanion.insert(
        amount: -8000,
        accountId: 2,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('HP Petrol refill'),
      ),
    );

    // Search "petrol" across all accounts
    final petrolTxs = await db.searchTransactionsStream(queryText: 'petrol').first;
    expect(petrolTxs.length, equals(2));

    // Search "petrol" filtered by Account 2
    final petrolAcc2 = await db.searchTransactionsStream(queryText: 'petrol', accountId: 2).first;
    expect(petrolAcc2.length, equals(1));
    expect(petrolAcc2.first.comment, equals('HP Petrol refill'));

    // Search "milk"
    final milkTxs = await db.searchTransactionsStream(queryText: 'milk').first;
    expect(milkTxs.length, equals(1));
    expect(milkTxs.first.amount, equals(-4500));
  });

  test('Create split transaction, verify non-double-counted balance, splits query, and cascade delete', () async {
    // Parent expense: ₹2,500 (250000 paise)
    final parentCompanion = TransactionsCompanion.insert(
      amount: -250000,
      accountId: 1,
      date: DateTime.now(),
      valueDate: DateTime.now(),
      comment: const drift.Value('Hypermarket Grocery & Household'),
      status: const drift.Value(1),
    );

    // Splits: ₹1,500 + ₹1,000
    final splitCompanions = [
      TransactionsCompanion.insert(
        amount: -150000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Groceries & Food'),
      ),
      TransactionsCompanion.insert(
        amount: -100000,
        accountId: 1,
        date: DateTime.now(),
        valueDate: DateTime.now(),
        comment: const drift.Value('Household essentials'),
      ),
    ];

    final parentId = await db.createSplitTransaction(
      parent: parentCompanion,
      splits: splitCompanions,
    );

    // Verify parent was created
    final parent = await (db.select(db.transactions)..where((t) => t.id.equals(parentId))).getSingle();
    expect(parent.amount, equals(-250000));
    expect(parent.status, equals(1));
    expect(parent.parentId, isNull);

    // Verify child splits query
    final splits = await db.getSplitsForParent(parentId);
    expect(splits.length, equals(2));
    final splitsSum = splits.fold<int>(0, (sum, s) => sum + s.amount);
    expect(splitsSum, equals(parent.amount));

    // Verify account balance reflects ONLY the parent transaction (-₹2,500) and does not double-count splits
    final balance = await db.getAccountBalance(1);
    expect(balance, equals(-250000));

    // Verify feed stream only shows parent transaction by default
    final feed = await db.watchTransactions(accountId: 1).first;
    expect(feed.length, equals(1));
    expect(feed.first.id, equals(parentId));

    // Verify cascade delete: deleting parent removes splits as well
    await db.deleteTransactionById(parentId);
    final remainingSplits = await db.getSplitsForParent(parentId);
    expect(remainingSplits.isEmpty, isTrue);

    final balanceAfterDelete = await db.getAccountBalance(1);
    expect(balanceAfterDelete, equals(0));
  });
}
