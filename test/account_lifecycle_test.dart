import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;

import 'package:expense_tracker/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Account Lifecycle & Edge Cases', () {
    test('Create account with zero opening balance', () async {
      final id = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Cash Wallet'),
          currency: drift.Value('INR'),
          openingBalance: drift.Value(0),
        ),
      );

      expect(id, isPositive);
      final accounts = await db.getAllAccounts();
      expect(accounts.length, equals(1));
      expect(accounts.first.label, equals('Cash Wallet'));
      expect(accounts.first.currency, equals('INR'));
      expect(accounts.first.openingBalance, equals(0));

      final balance = await db.getAccountBalance(id);
      expect(balance, equals(0));
    });

    test('Create account with positive opening balance records initial transaction', () async {
      // 5,000 INR = 500000 paise
      final id = await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('HDFC Salary Account'),
          currency: drift.Value('INR'),
          openingBalance: drift.Value(500000),
        ),
      );

      // Record opening balance transaction
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: id,
          amount: 500000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Opening Balance'),
        ),
      );

      final balance = await db.getAccountBalance(id);
      expect(balance, equals(500000)); // +₹5,000.00

      final totals = await db.getTotals();
      expect(totals['income'], equals(500000));
      expect(totals['expenses'], equals(0));
      expect(totals['net'], equals(500000));
    });

    test('Update existing account properties (label, color, currency)', () async {
      await db.createAccount(
        const AccountsCompanion(
          label: drift.Value('Old Account'),
          currency: drift.Value('INR'),
          color: drift.Value(-16738680),
        ),
      );

      final created = (await db.getAllAccounts()).first;
      final updated = created.copyWith(
        label: 'Renamed Vault',
        currency: 'USD',
        color: -14503224,
        description: const drift.Value('Emergency rainy day funds'),
      );

      final success = await db.updateAccount(updated);
      expect(success, isTrue);

      final fetched = (await db.getAllAccounts()).first;
      expect(fetched.label, equals('Renamed Vault'));
      expect(fetched.currency, equals('USD'));
      expect(fetched.color, equals(-14503224));
      expect(fetched.description, equals('Emergency rainy day funds'));
    });

    test('Delete account by ID removes it from database', () async {
      final id1 = await db.createAccount(
        const AccountsCompanion(label: drift.Value('Account 1')),
      );
      final id2 = await db.createAccount(
        const AccountsCompanion(label: drift.Value('Account 2')),
      );

      var accounts = await db.getAllAccounts();
      expect(accounts.length, equals(2));

      await db.deleteAccount(id1);

      accounts = await db.getAllAccounts();
      expect(accounts.length, equals(1));
      expect(accounts.first.id, equals(id2));
    });

    test('Accounts sort by sortKey ascending order', () async {
      await db.createAccount(
        const AccountsCompanion(label: drift.Value('Account Z'), sortKey: drift.Value(10)),
      );
      await db.createAccount(
        const AccountsCompanion(label: drift.Value('Account A'), sortKey: drift.Value(1)),
      );
      await db.createAccount(
        const AccountsCompanion(label: drift.Value('Account M'), sortKey: drift.Value(5)),
      );

      final accounts = await db.getAllAccounts();
      expect(accounts.length, equals(3));
      expect(accounts[0].label, equals('Account A'));
      expect(accounts[1].label, equals('Account M'));
      expect(accounts[2].label, equals('Account Z'));
    });

    test('Empty accounts database emits empty list in stream without error', () async {
      final streamResult = await db.watchAllAccounts().first;
      expect(streamResult, isEmpty);
    });
  });
}
