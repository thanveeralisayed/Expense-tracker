import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:archive/archive_io.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/services/backup_restore_service.dart';

void main() {
  late AppDatabase db;
  late BackupRestoreService restoreService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    restoreService = BackupRestoreService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Successfully restore legacy backup with 100% accuracy', () async {
    const backupPath = 'myexpenses-backup-20261006-094710';
    final result = await restoreService.restoreBackup(backupPath);

    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.accountsCount, equals(4));
    expect(result.transactionsCount, equals(470));
    expect(result.totalExpenses, equals(32699500)); // ₹3,26,995.00
    expect(result.totalIncome, equals(65900));      // ₹659.00
    expect(result.netBalance, equals(-32633600));   // -₹3,26,336.00

    // Verify Accounts in DB
    final accounts = await db.getAllAccounts();
    expect(accounts.length, equals(4));
    final accountLabels = accounts.map((a) => a.label).toSet();
    expect(accountLabels, containsAll([
      'Home Expense',
      'Self Expense',
      'Extras',
      'Hospital Expenses',
    ]));

    // Verify Account Balances
    final homeAcc = accounts.firstWhere((a) => a.label == 'Home Expense');
    final selfAcc = accounts.firstWhere((a) => a.label == 'Self Expense');
    final extrasAcc = accounts.firstWhere((a) => a.label == 'Extras');
    final hospAcc = accounts.firstWhere((a) => a.label == 'Hospital Expenses');

    final homeBalance = await db.getAccountBalance(homeAcc.id);
    final selfBalance = await db.getAccountBalance(selfAcc.id);
    final extrasBalance = await db.getAccountBalance(extrasAcc.id);
    final hospBalance = await db.getAccountBalance(hospAcc.id);

    expect(homeBalance, equals(-11286800)); // -₹1,12,868.00
    expect(selfBalance, equals(-7838800));  // -₹78,388.00
    expect(extrasBalance, equals(-12133000)); // -₹1,21,330.00
    expect(hospBalance, equals(-1375000));  // -₹13,750.00

    // Verify Preferences / Settings
    final settings = await db.select(db.appSettings).get();
    expect(settings.isNotEmpty, isTrue);
    final currencySetting = settings.firstWhere((s) => s.key == 'last_original_currency');
    expect(currencySetting.value, equals('INR'));
  });

  test('Successfully restore from a zipped backup archive (.zip)', () async {
    // Create a temporary zip file
    final tempDir = await Directory.systemTemp.createTemp('zip_test_');
    final zipFile = File('${tempDir.path}/test_backup.zip');

    final encoder = ZipFileEncoder();
    await encoder.zipDirectory(Directory('myexpenses-backup-20261006-094710'), filename: zipFile.path);

    // Restore from the created zip file
    final result = await restoreService.restoreBackup(zipFile.path);
    expect(result.success, isTrue, reason: result.errorMessage);
    expect(result.transactionsCount, equals(470));
    expect(result.accountsCount, equals(4));
    expect(result.netBalance, equals(-32633600));

    await tempDir.delete(recursive: true);
  });
}
