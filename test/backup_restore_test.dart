import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:archive/archive_io.dart';
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
    tempDir = await Directory.systemTemp.createTemp('generic_backup_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to create a valid, generic My Expenses SQLite backup file
  Future<File> createMockBackupDb(String dirPath) async {
    final dbFile = File('$dirPath/BACKUP');
    final legacyDb = sqlite.sqlite3.open(dbFile.path);

    legacyDb.execute('''
      CREATE TABLE accounts (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        currency TEXT NOT NULL,
        opening_balance INTEGER DEFAULT 0,
        color INTEGER DEFAULT -16738680,
        grouping TEXT DEFAULT 'MONTH',
        balance_type TEXT DEFAULT 'CURRENT',
        uuid TEXT,
        exclude_from_totals INTEGER DEFAULT 0,
        sealed INTEGER DEFAULT 0,
        sort_key INTEGER DEFAULT 0
      );

      CREATE TABLE categories (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        parent_id INTEGER,
        color INTEGER,
        icon TEXT,
        type INTEGER DEFAULT 0,
        uuid TEXT
      );

      CREATE TABLE payee (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        short_name TEXT,
        iban TEXT,
        bic TEXT
      );

      CREATE TABLE paymentmethods (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT NOT NULL,
        type INTEGER DEFAULT 0,
        icon TEXT
      );

      CREATE TABLE currency (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        symbol TEXT,
        fraction_digits INTEGER DEFAULT 2
      );

      CREATE TABLE transactions (
        _id INTEGER PRIMARY KEY AUTOINCREMENT,
        comment TEXT,
        date INTEGER NOT NULL,
        value_date INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        cat_id INTEGER,
        account_id INTEGER NOT NULL,
        payee_id INTEGER,
        transfer_peer INTEGER,
        transfer_account INTEGER,
        method_id INTEGER,
        parent_id INTEGER,
        status INTEGER DEFAULT 0,
        cr_status TEXT DEFAULT 'RECONCILED',
        number TEXT,
        uuid TEXT,
        debt_id INTEGER
      );
    ''');

    // Insert generic sample data
    legacyDb.execute("INSERT INTO currency (code, symbol, fraction_digits) VALUES ('INR', '₹', 2), ('USD', '\$', 2)");
    legacyDb.execute("INSERT INTO accounts (_id, label, currency) VALUES (1, 'Personal Checking', 'INR'), (2, 'Savings Reserve', 'INR')");
    legacyDb.execute("INSERT INTO categories (_id, label) VALUES (1, 'Food'), (2, 'Transport')");
    legacyDb.execute("INSERT INTO payee (_id, name) VALUES (1, 'Grocery Mart')");
    legacyDb.execute("INSERT INTO paymentmethods (_id, label) VALUES (1, 'Cash'), (2, 'UPI')");

    // Sample transactions
    legacyDb.execute("INSERT INTO transactions (_id, comment, date, value_date, amount, account_id, cat_id) VALUES (1, 'Coffee', 1764592200, 1764592200, -15000, 1, 1)"); // -₹150
    legacyDb.execute("INSERT INTO transactions (_id, comment, date, value_date, amount, account_id, cat_id) VALUES (2, 'Salary', 1764592201, 1764592201, 500000, 2, NULL)"); // +₹5,000

    legacyDb.close();

    // Create optional BACKUP_PREF xml
    final prefFile = File('$dirPath/BACKUP_PREF');
    await prefFile.writeAsString('''
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <string name="last_original_currency">INR</string>
    <string name="group_week_start">1</string>
</map>
''');

    return dbFile;
  }

  test('Generic restore from an unzipped backup directory', () async {
    final subFolder = Directory('${tempDir.path}/sample_backup');
    await subFolder.create();
    await createMockBackupDb(subFolder.path);

    final result = await restoreService.restoreBackup(subFolder.path);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.accountsCount, equals(2));
    expect(result.transactionsCount, equals(2));
    expect(result.totalExpenses, equals(15000)); // ₹150.00
    expect(result.totalIncome, equals(500000));   // ₹5,000.00
    expect(result.netBalance, equals(485000));     // ₹4,850.00

    final accounts = await db.getAllAccounts();
    expect(accounts.length, equals(2));
    expect(accounts.map((a) => a.label), containsAll(['Personal Checking', 'Savings Reserve']));
  });

  test('Generic restore from a zipped backup archive (.zip)', () async {
    final sourceFolder = Directory('${tempDir.path}/raw_data');
    await sourceFolder.create();
    await createMockBackupDb(sourceFolder.path);

    final zipFile = File('${tempDir.path}/generic_backup.zip');
    final encoder = ZipFileEncoder();
    await encoder.zipDirectory(sourceFolder, filename: zipFile.path);

    final result = await restoreService.restoreBackup(zipFile.path);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.accountsCount, equals(2));
    expect(result.transactionsCount, equals(2));
    expect(result.netBalance, equals(485000));
  });

  test('Generic restore directly from a single BACKUP database file', () async {
    final dbFile = await createMockBackupDb(tempDir.path);

    final result = await restoreService.restoreBackup(dbFile.path);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.transactionsCount, equals(2));
    expect(result.accountsCount, equals(2));
  });
}
