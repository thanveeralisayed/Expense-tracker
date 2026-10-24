import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/services/backup_restore_service.dart';

void main() {
  late AppDatabase db;
  late BackupRestoreService restoreService;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    restoreService = BackupRestoreService(db);
    tempDir = await Directory.systemTemp.createTemp('restore_edge_cases_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupRestoreService Edge Cases & Fault Tolerance', () {
    test('Non-existent file path safely returns failure without throwing uncaught exception', () async {
      final res = await restoreService.restoreBackup('/path/to/non/existent/file.zip');
      expect(res.success, isFalse);
      expect(res.errorMessage, isNotNull);
    });

    test('Corrupted/random binary file safely returns failure without crashing', () async {
      final junkFile = File('${tempDir.path}/corrupted.zip');
      await junkFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]);

      final res = await restoreService.restoreBackup(junkFile.path);
      expect(res.success, isFalse);
      expect(res.errorMessage, isNotNull);
    });

    test('SQLite backup missing optional tables (categories, payee) restores core accounts & transactions', () async {
      final dbFile = File('${tempDir.path}/BACKUP');
      final legacyDb = sqlite.sqlite3.open(dbFile.path);

      // Create only accounts and transactions tables (no categories, payee, paymentmethods)
      legacyDb.execute('''
        CREATE TABLE accounts (
          _id INTEGER PRIMARY KEY,
          label TEXT NOT NULL,
          currency TEXT DEFAULT 'INR'
        );
        CREATE TABLE transactions (
          _id INTEGER PRIMARY KEY,
          comment TEXT,
          date INTEGER NOT NULL,
          value_date INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          account_id INTEGER NOT NULL
        );
      ''');

      legacyDb.execute("INSERT INTO accounts (_id, label, currency) VALUES (1, 'Wallet', 'INR')");
      legacyDb.execute("INSERT INTO transactions (_id, comment, date, value_date, amount, account_id) VALUES (1, 'Tea', 1700000000, 1700000000, -2000, 1)");
      legacyDb.close();

      final res = await restoreService.restoreBackup(tempDir.path);
      expect(res.success, isTrue);
      expect(res.accountsCount, equals(1));
      expect(res.transactionsCount, equals(1));

      final accounts = await db.getAllAccounts();
      expect(accounts.length, equals(1));
      expect(accounts.first.label, equals('Wallet'));

      final balance = await db.getAccountBalance(accounts.first.id);
      expect(balance, equals(-2000));
    });

    test('SQLite backup with different column naming patterns handles dynamic extraction', () async {
      final dbFile = File('${tempDir.path}/BACKUP');
      final legacyDb = sqlite.sqlite3.open(dbFile.path);

      // Uses 'id' instead of '_id', 'name' instead of 'label'
      legacyDb.execute('''
        CREATE TABLE accounts (
          id INTEGER PRIMARY KEY,
          label TEXT,
          currency TEXT DEFAULT 'USD'
        );
        CREATE TABLE transactions (
          id INTEGER PRIMARY KEY,
          comment TEXT,
          date INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          account_id INTEGER NOT NULL
        );
      ''');

      legacyDb.execute("INSERT INTO accounts (id, label, currency) VALUES (1, 'Emergency Bank', 'USD')");
      legacyDb.execute("INSERT INTO transactions (id, comment, date, amount, account_id) VALUES (10, 'Interest', 1700000000, 5000, 1)");
      legacyDb.close();

      final res = await restoreService.restoreBackup(tempDir.path);
      expect(res.success, isTrue);
      expect(res.accountsCount, equals(1));
      expect(res.transactionsCount, equals(1));

      final balance = await db.getAccountBalance(1);
      expect(balance, equals(5000));
    });
  });
}
