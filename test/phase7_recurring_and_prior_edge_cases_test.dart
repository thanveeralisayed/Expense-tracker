import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';

import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/features/transactions/domain/recurring_commitments_service.dart';

void main() {
  group('Phase 7 - Recurring Commitments & Subscription Liability Tests', () {
    test('JSON serialization and parsing handles null, empty, corrupted, and valid payloads', () {
      // 1. Null / empty string
      expect(RecurringCommitmentsService.parseCommitments(null), isEmpty);
      expect(RecurringCommitmentsService.parseCommitments(''), isEmpty);
      expect(RecurringCommitmentsService.parseCommitments('   '), isEmpty);

      // 2. Corrupted JSON string
      expect(RecurringCommitmentsService.parseCommitments('{invalid json}'), isEmpty);
      expect(RecurringCommitmentsService.parseCommitments('{"title": "Not a list"}'), isEmpty);

      // 3. Valid serialization and deserialization
      final commitments = [
        const RecurringCommitment(
          id: 'sub_1',
          title: 'Netflix Premium 4K',
          amountPaise: 64900,
          frequency: 'monthly',
          dayNumber: 15,
          isExpense: true,
          isActive: true,
        ),
        const RecurringCommitment(
          id: 'sub_2',
          title: 'Gym Membership',
          amountPaise: 250000,
          frequency: 'yearly',
          dayNumber: 1,
          isExpense: true,
          isActive: false, // Inactive
        ),
        const RecurringCommitment(
          id: 'sub_3',
          title: 'Freelance Retainer',
          amountPaise: 1000000,
          frequency: 'weekly',
          dayNumber: 5, // Friday
          isExpense: false, // Income
          isActive: true,
        ),
      ];

      final jsonStr = RecurringCommitmentsService.serializeCommitments(commitments);
      expect(jsonStr, contains('Netflix Premium 4K'));
      expect(jsonStr, contains('sub_3'));

      final parsed = RecurringCommitmentsService.parseCommitments(jsonStr);
      expect(parsed.length, equals(3));
      expect(parsed[0].id, equals('sub_1'));
      expect(parsed[0].title, equals('Netflix Premium 4K'));
      expect(parsed[0].amountPaise, equals(64900));
      expect(parsed[0].isExpense, isTrue);
      expect(parsed[1].isActive, isFalse);
      expect(parsed[2].isExpense, isFalse);
    });

    test('calculateMonthlyEquivalentPaise handles frequencies accurately and ignores inactive items', () {
      // Monthly: ₹1,500
      const monthly = RecurringCommitment(
        id: '1',
        title: 'Broadband',
        amountPaise: 150000,
        frequency: 'monthly',
      );
      expect(RecurringCommitmentsService.calculateMonthlyEquivalentPaise(monthly), equals(150000));

      // Weekly: ₹1,000/wk -> 1000 * 52 / 12 = ₹4,333.33 -> 433333 paise
      const weekly = RecurringCommitment(
        id: '2',
        title: 'Weekly Grocery allowance',
        amountPaise: 100000,
        frequency: 'weekly',
      );
      expect(RecurringCommitmentsService.calculateMonthlyEquivalentPaise(weekly), equals(433333));

      // Yearly: ₹12,000/yr -> 12000 / 12 = ₹1,000/mo -> 100000 paise
      const yearly = RecurringCommitment(
        id: '3',
        title: 'Amazon Prime Yearly',
        amountPaise: 149900,
        frequency: 'yearly',
      );
      expect(RecurringCommitmentsService.calculateMonthlyEquivalentPaise(yearly), equals((149900 / 12).round()));

      // Inactive: returns 0
      final inactive = monthly.copyWith(isActive: false);
      expect(RecurringCommitmentsService.calculateMonthlyEquivalentPaise(inactive), equals(0));
    });

    test('calculateMonthlyTotals separates expenses, income, and computes net liability', () {
      final commitments = [
        const RecurringCommitment(
          id: '1',
          title: 'Rent',
          amountPaise: 3000000, // ₹30,000 / mo
          frequency: 'monthly',
          isExpense: true,
          isActive: true,
        ),
        const RecurringCommitment(
          id: '2',
          title: 'Cloud Storage',
          amountPaise: 13000, // ₹130 / mo
          frequency: 'monthly',
          isExpense: true,
          isActive: true,
        ),
        const RecurringCommitment(
          id: '3',
          title: 'Cancelled Gym',
          amountPaise: 500000, // ₹5,000 / mo
          frequency: 'monthly',
          isExpense: true,
          isActive: false, // should be skipped
        ),
        const RecurringCommitment(
          id: '4',
          title: 'Rental Dividend',
          amountPaise: 1000000, // ₹10,000 / mo
          frequency: 'monthly',
          isExpense: false, // Income
          isActive: true,
        ),
      ];

      final totals = RecurringCommitmentsService.calculateMonthlyTotals(commitments);
      expect(totals.monthlyExpensePaise, equals(3013000)); // Rent + Cloud
      expect(totals.monthlyIncomePaise, equals(1000000)); // Rental dividend
      expect(totals.netMonthlyPaise, equals(1000000 - 3013000)); // -₹20,130
    });

    test('getNextDueDate handles calendar day boundary clamping (leap years and 31st day)', () {
      // Test 1: Monthly commitment set to the 31st day, evaluated in February 2026 (non-leap year has 28 days)
      const endOfMonthCommitment = RecurringCommitment(
        id: '1',
        title: 'Month End Bill',
        amountPaise: 50000,
        frequency: 'monthly',
        dayNumber: 31,
      );

      final midFeb2026 = DateTime(2026, 2, 10);
      final nextDueFeb = RecurringCommitmentsService.getNextDueDate(endOfMonthCommitment, referenceNow: midFeb2026);
      expect(nextDueFeb.year, equals(2026));
      expect(nextDueFeb.month, equals(2));
      expect(nextDueFeb.day, equals(28)); // Clamped to 28 for non-leap Feb!

      // Test 2: Monthly commitment set to 31st, evaluated in February 2028 (leap year has 29 days)
      final midFeb2028 = DateTime(2028, 2, 10);
      final nextDueLeap = RecurringCommitmentsService.getNextDueDate(endOfMonthCommitment, referenceNow: midFeb2028);
      expect(nextDueLeap.year, equals(2028));
      expect(nextDueLeap.month, equals(2));
      expect(nextDueLeap.day, equals(29)); // Clamped to 29 for leap year Feb!

      // Test 3: If target day has already passed this month, rolls over to next month
      final lateMarch = DateTime(2026, 3, 20); // 15th has already passed
      const fifteenthCommitment = RecurringCommitment(
        id: '2',
        title: 'Mid Month Bill',
        amountPaise: 10000,
        frequency: 'monthly',
        dayNumber: 15,
      );
      final nextDueApril = RecurringCommitmentsService.getNextDueDate(fifteenthCommitment, referenceNow: lateMarch);
      expect(nextDueApril.year, equals(2026));
      expect(nextDueApril.month, equals(4));
      expect(nextDueApril.day, equals(15));

      // Test 4: December rollover to January next year
      final lateDec = DateTime(2026, 12, 20);
      final nextDueJan = RecurringCommitmentsService.getNextDueDate(fifteenthCommitment, referenceNow: lateDec);
      expect(nextDueJan.year, equals(2027));
      expect(nextDueJan.month, equals(1));
      expect(nextDueJan.day, equals(15));
    });

    test('isDueSoon identifies upcoming commitments within threshold window', () {
      final today = DateTime(2026, 10, 20);
      const commitmentSoon = RecurringCommitment(
        id: '1',
        title: 'Electricity',
        amountPaise: 250000,
        frequency: 'monthly',
        dayNumber: 24, // 4 days ahead
        isActive: true,
      );
      const commitmentFar = RecurringCommitment(
        id: '2',
        title: 'Rent',
        amountPaise: 2500000,
        frequency: 'monthly',
        dayNumber: 5, // 16 days ahead
        isActive: true,
      );

      expect(RecurringCommitmentsService.isDueSoon(commitmentSoon, daysAhead: 7, referenceNow: today), isTrue);
      expect(RecurringCommitmentsService.isDueSoon(commitmentFar, daysAhead: 7, referenceNow: today), isFalse);

      // Inactive is never due soon
      final inactiveSoon = commitmentSoon.copyWith(isActive: false);
      expect(RecurringCommitmentsService.isDueSoon(inactiveSoon, daysAhead: 7, referenceNow: today), isFalse);
    });
  });

  group('Phase 7 - Prior Phases Edge Cases & Database Safeguards', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('createTransfer throws ArgumentError when fromAccountId == toAccountId', () async {
      final accId = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Single Bank Account'), currency: Value('INR')),
      );

      expect(
        () => db.createTransfer(
          fromAccountId: accId,
          toAccountId: accId, // Same account
          amountPaise: 50000,
          date: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Source and destination accounts must be different'),
        )),
      );
    });

    test('createTransfer throws ArgumentError when amountPaise <= 0', () async {
      final acc1 = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Account 1'), currency: Value('INR')),
      );
      final acc2 = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Account 2'), currency: Value('INR')),
      );

      // 0 amount
      expect(
        () => db.createTransfer(
          fromAccountId: acc1,
          toAccountId: acc2,
          amountPaise: 0,
          date: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Transfer amount must be strictly greater than 0'),
        )),
      );

      // Negative amount
      expect(
        () => db.createTransfer(
          fromAccountId: acc1,
          toAccountId: acc2,
          amountPaise: -1000,
          date: DateTime.now(),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Transfer amount must be strictly greater than 0'),
        )),
      );
    });

    test('createTransfer establishes bidirectional peer links and symmetric amounts', () async {
      final acc1 = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Savings'), currency: Value('INR')),
      );
      final acc2 = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Current'), currency: Value('INR')),
      );

      final transferDate = DateTime(2026, 10, 15, 10, 30);
      await db.createTransfer(
        fromAccountId: acc1,
        toAccountId: acc2,
        amountPaise: 750000, // ₹7,500
        comment: 'Fund rebalance',
        date: transferDate,
      );

      final allTxns = await db.select(db.transactions).get();
      expect(allTxns.length, equals(2));

      final debitLeg = allTxns.firstWhere((t) => t.accountId == acc1);
      final creditLeg = allTxns.firstWhere((t) => t.accountId == acc2);

      // Debit leg has negative amount, points to acc2, and transferPeer points to creditLeg
      expect(debitLeg.amount, equals(-750000));
      expect(debitLeg.transferAccount, equals(acc2));
      expect(debitLeg.transferPeer, equals(creditLeg.id));
      expect(debitLeg.comment, equals('Fund rebalance'));

      // Credit leg has positive amount, points to acc1, and transferPeer points to debitLeg
      expect(creditLeg.amount, equals(750000));
      expect(creditLeg.transferAccount, equals(acc1));
      expect(creditLeg.transferPeer, equals(debitLeg.id));
      expect(creditLeg.comment, equals('Fund rebalance'));

      // Deleting one leg cascades and deletes the peer leg atomically
      await db.deleteTransactionById(debitLeg.id);
      final remaining = await db.select(db.transactions).get();
      expect(remaining, isEmpty);
    });

    test('extreme currency amounts handle large 64-bit integer numbers safely', () async {
      final acc = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Treasury'), currency: Value('INR')),
      );

      // 10 billion rupees = 1,000,000,000,000 paise (1 trillion paise)
      const bigAmount = 1000000000000;
      final txId = await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(acc),
          amount: const Value(bigAmount),
          date: Value(DateTime.now()),
          valueDate: Value(DateTime.now()),
          comment: const Value('Large sovereign bond investment'),
        ),
      );

      final loaded = await (db.select(db.transactions)..where((t) => t.id.equals(txId))).getSingle();
      expect(loaded.amount, equals(bigAmount));

      // Calculate totals doesn't overflow
      final totals = await db.getTotals(accountId: acc);
      expect(totals['income'], equals(bigAmount));
    });

    test('deleteAccount cascades and deletes all transactions and transfers associated with it', () async {
      final accA = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Account A'), currency: Value('INR')),
      );
      final accB = await db.into(db.accounts).insert(
        const AccountsCompanion(label: Value('Account B'), currency: Value('INR')),
      );

      // Normal transaction in Account A
      await db.into(db.transactions).insert(
        TransactionsCompanion(
          accountId: Value(accA),
          amount: const Value(-20000),
          date: Value(DateTime.now()),
          valueDate: Value(DateTime.now()),
          comment: const Value('Lunch'),
        ),
      );

      // Transfer from A to B
      await db.createTransfer(
        fromAccountId: accA,
        toAccountId: accB,
        amountPaise: 100000,
        date: DateTime.now(),
      );

      expect((await db.select(db.transactions).get()).length, equals(3));

      // Delete Account A
      await db.deleteAccount(accA);

      // Account A is deleted
      final accounts = await db.getAllAccounts();
      expect(accounts.any((a) => a.id == accA), isFalse);
      expect(accounts.any((a) => a.id == accB), isTrue);

      // All transactions in Account A and transfers to/from Account A are deleted cleanly
      final remainingTxns = await db.select(db.transactions).get();
      expect(remainingTxns, isEmpty);
    });
  });
}
