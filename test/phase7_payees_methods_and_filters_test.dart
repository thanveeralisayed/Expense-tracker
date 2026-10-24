import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:expense_tracker/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 7 - Payees Architecture & Cascade Unlinking', () {
    test('create, get, update, and watch payees', () async {
      final id1 = await db.createPayee(
        const PayeesCompanion(name: Value('Amazon India')),
      );
      final id2 = await db.createPayee(
        const PayeesCompanion(name: Value('Netflix')),
      );

      final payees = await db.getAllPayees();
      expect(payees.length, equals(2));
      expect(payees.any((p) => p.id == id1 && p.name == 'Amazon India'), isTrue);
      expect(payees.any((p) => p.id == id2 && p.name == 'Netflix'), isTrue);

      // Update payee
      await db.updatePayee(
        Payee(
          id: id1,
          name: 'Amazon Prime',
        ),
      );

      final updated = await db.getAllPayees();
      final prime = updated.firstWhere((p) => p.id == id1);
      expect(prime.name, equals('Amazon Prime'));

      // Stream emits update
      final streamPayees = await db.watchAllPayees().first;
      expect(streamPayees.length, equals(2));
    });

    test('deleting payee cascades null to linked transactions without deleting transaction', () async {
      final accId = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Bank'), currency: Value('INR')),
      );
      final payeeId = await db.createPayee(
        const PayeesCompanion(name: Value('Starbucks Coffee')),
      );

      final txnId = await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(accId),
          amount: const Value(-35000), // -350 INR
          payeeId: Value(payeeId),
          date: Value(DateTime.now()),
          valueDate: Value(DateTime.now()),
          comment: const Value('Latte'),
        ),
      );

      // Confirm payeeId is set
      var txn = await (db.select(db.transactions)..where((t) => t.id.equals(txnId))).getSingle();
      expect(txn.payeeId, equals(payeeId));

      // Delete Payee
      await db.deletePayee(payeeId);

      // Payee is gone from payees table
      final allPayees = await db.getAllPayees();
      expect(allPayees.any((p) => p.id == payeeId), isFalse);

      // Transaction still exists, but payeeId is unlinked (null)
      txn = await (db.select(db.transactions)..where((t) => t.id.equals(txnId))).getSingle();
      expect(txn.payeeId, isNull);
      expect(txn.comment, equals('Latte'));
    });
  });

  group('Phase 7 - Payment Methods Architecture & Seeding', () {
    test('seedDefaultPaymentMethodsIfEmpty initializes standard defaults and prevents duplicates', () async {
      // Initially empty
      var methods = await db.getAllPaymentMethods();
      expect(methods, isEmpty);

      // Seed
      await db.seedDefaultPaymentMethodsIfEmpty();
      methods = await db.getAllPaymentMethods();
      expect(methods.length, equals(5));

      final names = methods.map((m) => m.label).toSet();
      expect(names, containsAll(['Cash', 'UPI / QR', 'Credit Card', 'Debit Card', 'Bank Transfer']));

      // Calling seed a second time should be idempotent (no duplicate rows)
      await db.seedDefaultPaymentMethodsIfEmpty();
      final afterSecondSeed = await db.getAllPaymentMethods();
      expect(afterSecondSeed.length, equals(5));
    });

    test('create, update, and delete payment method with cascade unlinking', () async {
      final methodId = await db.createPaymentMethod(
        const PaymentMethodsCompanion(label: Value('Crypto Wallet'), icon: Value('currency_bitcoin')),
      );

      var methods = await db.getAllPaymentMethods();
      expect(methods.any((m) => m.id == methodId && m.label == 'Crypto Wallet'), isTrue);

      // Update
      await db.updatePaymentMethod(
        PaymentMethod(
          id: methodId,
          label: 'Hardware Wallet',
          type: 0,
        ),
      );
      final updated = await db.getAllPaymentMethods();
      expect(updated.firstWhere((m) => m.id == methodId).label, equals('Hardware Wallet'));

      // Link to transaction
      final accId = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Checking'), currency: Value('INR')),
      );
      final txnId = await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(accId),
          amount: const Value(-500000),
          methodId: Value(methodId),
          date: Value(DateTime.now()),
          valueDate: Value(DateTime.now()),
        ),
      );

      // Delete payment method
      await db.deletePaymentMethod(methodId);

      // Verify unlinked
      final txn = await (db.select(db.transactions)..where((t) => t.id.equals(txnId))).getSingle();
      expect(txn.methodId, isNull);
    });
  });

  group('Phase 7 - Multi-dimension Search, Filtering & Sorting Engine', () {
    late int acc1Id;
    late int acc2Id;
    late int catFoodId;
    late int catSalaryId;
    late int payeeSwiggyId;
    late int payeeEmployerId;
    late int methodUpiId;
    late int methodCashId;

    final now = DateTime(2026, 10, 15, 12, 0);

    setUp(() async {
      acc1Id = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('HDFC Bank'), currency: Value('INR')),
      );
      acc2Id = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Cash Wallet'), currency: Value('INR')),
      );

      catFoodId = await db.into(db.categories).insert(
        const CategoriesCompanion(label: Value('Food & Dining'), type: Value(0)),
      );
      catSalaryId = await db.into(db.categories).insert(
        const CategoriesCompanion(label: Value('Salary'), type: Value(1)),
      );

      payeeSwiggyId = await db.createPayee(const PayeesCompanion(name: Value('Swiggy')));
      payeeEmployerId = await db.createPayee(const PayeesCompanion(name: Value('TechCorp')));

      methodUpiId = await db.createPaymentMethod(const PaymentMethodsCompanion(label: Value('UPI')));
      methodCashId = await db.createPaymentMethod(const PaymentMethodsCompanion(label: Value('Cash')));

      // Transaction 1: Expense, Food, Swiggy, UPI, ₹450, Oct 10
      await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(acc1Id),
          amount: const Value(-45000),
          catId: Value(catFoodId),
          payeeId: Value(payeeSwiggyId),
          methodId: Value(methodUpiId),
          comment: const Value('Pizza delivery'),
          date: Value(now.subtract(const Duration(days: 5))),
          valueDate: Value(now.subtract(const Duration(days: 5))),
        ),
      );

      // Transaction 2: Income, Salary, Employer, UPI, ₹80,000, Oct 1
      await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(acc1Id),
          amount: const Value(8000000),
          catId: Value(catSalaryId),
          payeeId: Value(payeeEmployerId),
          methodId: Value(methodUpiId),
          comment: const Value('October Salary'),
          date: Value(now.subtract(const Duration(days: 14))),
          valueDate: Value(now.subtract(const Duration(days: 14))),
        ),
      );

      // Transaction 3: Expense, Food, Cash, ₹150, Oct 14
      await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(acc2Id),
          amount: const Value(-15000),
          catId: Value(catFoodId),
          methodId: Value(methodCashId),
          comment: const Value('Coffee and snacks'),
          date: Value(now.subtract(const Duration(days: 1))),
          valueDate: Value(now.subtract(const Duration(days: 1))),
        ),
      );

      // Transaction 4: Transfer from acc1 to acc2, ₹5,000, Oct 12
      await db.createTransfer(
        fromAccountId: acc1Id,
        toAccountId: acc2Id,
        amountPaise: 500000,
        comment: 'ATM cash withdrawal',
        date: now.subtract(const Duration(days: 3)),
      );
    });

    test('filter by transaction type: Expense (0), Income (1), Transfer (2)', () async {
      // Expense only
      final expenses = await db.searchTransactionsStream(transactionType: 0).first;
      expect(expenses.length, equals(2));
      expect(expenses.every((t) => t.amount < 0 && t.transferAccount == null), isTrue);

      // Income only
      final incomes = await db.searchTransactionsStream(transactionType: 1).first;
      expect(incomes.length, equals(1));
      expect(incomes.first.comment, equals('October Salary'));

      // Transfer only
      final transfers = await db.searchTransactionsStream(transactionType: 2).first;
      expect(transfers.length, equals(2)); // The out leg and in leg of the transfer
      expect(transfers.every((t) => t.transferAccount != null || t.transferPeer != null), isTrue);
    });

    test('filter by categoryId and payeeId', () async {
      // By Category Food
      final foodTxns = await db.searchTransactionsStream(categoryId: catFoodId).first;
      expect(foodTxns.length, equals(2));

      // By Payee Swiggy
      final swiggyTxns = await db.searchTransactionsStream(payeeId: payeeSwiggyId).first;
      expect(swiggyTxns.length, equals(1));
      expect(swiggyTxns.first.comment, equals('Pizza delivery'));
    });

    test('filter by payment method', () async {
      final cashTxns = await db.searchTransactionsStream(methodId: methodCashId).first;
      expect(cashTxns.length, equals(1));
      expect(cashTxns.first.comment, equals('Coffee and snacks'));

      final upiTxns = await db.searchTransactionsStream(methodId: methodUpiId).first;
      expect(upiTxns.length, equals(2)); // Pizza + Salary
    });

    test('filter by date range', () async {
      // Date between Oct 8 and Oct 11 -> only Pizza (Oct 10)
      final rangeTxns = await db.searchTransactionsStream(
        startDate: now.subtract(const Duration(days: 7)),
        endDate: now.subtract(const Duration(days: 4)),
      ).first;
      expect(rangeTxns.length, equals(1));
      expect(rangeTxns.first.comment, equals('Pizza delivery'));
    });

    test('filter by amount range', () async {
      // Between ₹200 and ₹600 (20,000 paise to 60,000 paise) -> Pizza delivery (₹450)
      final amountTxns = await db.searchTransactionsStream(
        minPaise: 20000,
        maxPaise: 60000,
      ).first;
      expect(amountTxns.length, equals(1));
      expect(amountTxns.first.comment, equals('Pizza delivery'));
    });

    test('dynamic sorting: date_desc, date_asc, amount_desc, amount_asc', () async {
      // date_desc (newest first)
      final byDateDesc = await db.searchTransactionsStream(
        transactionType: 0,
        sortBy: 'date_desc',
      ).first;
      expect(byDateDesc.length, equals(2));
      expect(byDateDesc[0].comment, equals('Coffee and snacks')); // Oct 14
      expect(byDateDesc[1].comment, equals('Pizza delivery')); // Oct 10

      // date_asc (oldest first)
      final byDateAsc = await db.searchTransactionsStream(
        transactionType: 0,
        sortBy: 'date_asc',
      ).first;
      expect(byDateAsc[0].comment, equals('Pizza delivery')); // Oct 10
      expect(byDateAsc[1].comment, equals('Coffee and snacks')); // Oct 14

      // amount_desc (highest amount first)
      final byAmtDesc = await db.searchTransactionsStream(
        transactionType: 0,
        sortBy: 'amount_desc',
      ).first;
      expect(byAmtDesc[0].amount.abs(), equals(45000)); // ₹450
      expect(byAmtDesc[1].amount.abs(), equals(15000)); // ₹150

      // amount_asc (lowest amount first)
      final byAmtAsc = await db.searchTransactionsStream(
        transactionType: 0,
        sortBy: 'amount_asc',
      ).first;
      expect(byAmtAsc[0].amount.abs(), equals(15000)); // ₹150
      expect(byAmtAsc[1].amount.abs(), equals(45000)); // ₹450
    });

    test('multi-filter combination yields precise intersection', () async {
      final combined = await db.searchTransactionsStream(
        queryText: 'Pizza',
        transactionType: 0,
        categoryId: catFoodId,
        payeeId: payeeSwiggyId,
        methodId: methodUpiId,
        minPaise: 10000,
        maxPaise: 50000,
      ).first;

      expect(combined.length, equals(1));
      expect(combined.first.comment, equals('Pizza delivery'));

      // Empty if one condition doesn't match
      final emptyResult = await db.searchTransactionsStream(
        queryText: 'Pizza',
        methodId: methodCashId, // Pizza was UPI, not Cash
      ).first;
      expect(emptyResult, isEmpty);
    });
  });
}
