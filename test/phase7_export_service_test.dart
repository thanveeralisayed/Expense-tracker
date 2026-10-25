import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/services/export_service.dart';
import 'package:expense_tracker/core/services/backup_restore_service.dart';

void main() {
  group('Phase 7 - ExportService CSV Formatting & Escaping Edge Cases', () {
    test('escapeCsvCell handles commas, quotes, newlines, and nulls properly according to RFC 4180', () {
      // 1. Normal alphanumeric string: unchanged without quotes
      expect(ExportService.escapeCsvCell('Groceries'), equals('"Groceries"'));

      // 2. Empty string or null: double quotes
      expect(ExportService.escapeCsvCell(null), equals('""'));
      expect(ExportService.escapeCsvCell(''), equals('""'));
      expect(ExportService.escapeCsvCell('   '), equals('""'));

      // 3. String containing comma: quoted
      expect(ExportService.escapeCsvCell('Milk, Eggs, Bread'), equals('"Milk, Eggs, Bread"'));

      // 4. String containing double quotes: quotes escaped as ""
      expect(ExportService.escapeCsvCell('Store "Fresh" Mart'), equals('"Store ""Fresh"" Mart"'));

      // 5. String containing newline
      expect(ExportService.escapeCsvCell('Line 1\nLine 2'), equals('"Line 1\nLine 2"'));
    });

    test('generateCsvString produces compliant headers and formatted transaction rows', () {
      final now = DateTime(2026, 10, 24, 14, 30, 0);
      final account = const Account(
        id: 1,
        label: 'Checking Account',
        openingBalance: 0,
        currency: 'INR',
        color: 0,
        grouping: 'MONTH',
        balanceType: 'CURRENT',
        excludeFromTotals: false,
        sealed: false,
        sortKey: 0,
      );
      final category = const Category(
        id: 10,
        label: 'Food & Dining',
        type: 0,
        color: 0,
        icon: 'restaurant',
      );
      final payee = const Payee(id: 100, name: 'McDonald\'s, "Downtown"');
      final method = const PaymentMethod(id: 5, label: 'Credit Card', type: 0);

      final txExpense = Transaction(
        id: 1,
        accountId: 1,
        amount: -25050, // -₹250.50
        date: now,
        valueDate: now,
        catId: 10,
        payeeId: 100,
        methodId: 5,
        comment: 'Burger, fries & soda',
        status: 0,
        crStatus: 'RECONCILED',
      );

      final txIncome = Transaction(
        id: 2,
        accountId: 1,
        amount: 1500000, // ₹15,000.00
        date: now,
        valueDate: now,
        catId: null,
        comment: 'Consulting bonus',
        status: 0,
        crStatus: 'CLEARED',
      );

      final txTransfer = Transaction(
        id: 3,
        accountId: 1,
        amount: -50000,
        date: now,
        valueDate: now,
        transferAccount: 2,
        comment: 'Rent share',
        status: 0,
        crStatus: 'RECONCILED',
      );

      final txSplitParent = Transaction(
        id: 4,
        accountId: 1,
        amount: -100000,
        date: now,
        valueDate: now,
        comment: 'Shopping split',
        status: 1, // split parent
        crStatus: 'RECONCILED',
      );

      final csv = ExportService.generateCsvString(
        transactions: [txExpense, txIncome, txTransfer, txSplitParent],
        accountsMap: {1: account},
        categoriesMap: {10: category},
        payeesMap: {100: payee},
        methodsMap: {5: method},
      );

      final lines = csv.trim().split('\n');
      expect(lines.length, equals(5)); // Header + 4 data rows

      // Verify Header
      expect(lines[0], contains('"ID","Date","Time","Account","Type","Category","Amount","Currency","Raw Paise","Payee","Payment Method","Note","Status"'));

      // Verify Expense row
      expect(lines[1], contains('"Checking Account"'));
      expect(lines[1], contains('"Expense"'));
      expect(lines[1], contains('"Food & Dining"'));
      expect(lines[1], contains('"-250.50"'));
      expect(lines[1], contains('"-25050"'));
      expect(lines[1], contains('"McDonald\'s, ""Downtown"""'));
      expect(lines[1], contains('"Credit Card"'));
      expect(lines[1], contains('"Burger, fries & soda"'));

      // Verify Income row
      expect(lines[2], contains('"Income"'));
      expect(lines[2], contains('"15000.00"'));
      expect(lines[2], contains('"Uncategorized"'));

      // Verify Transfer row
      expect(lines[3], contains('"Transfer"'));

      // Verify Split Parent row
      expect(lines[4], contains('"Split Parent"'));
    });
  });

  group('Phase 7 - ExportService Full Backup Archive (.zip) Tests', () {
    late AppDatabase db;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('export_test_');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('createFullBackupZip creates a valid zip containing all serialized entities', () async {
      // 1. Seed accounts, categories, and settings
      final accId = await db.createAccount(
        const AccountsCompanion(label: Value('Main Checking'), currency: Value('INR')),
      );
      final catId = await db.createCategory(
        const CategoriesCompanion(label: Value('Groceries'), type: Value(0)),
      );
      await db.setSetting('budget_monthly_overall', '5000000');

      // 2. Add transaction
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: -50000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          catId: Value(catId),
          comment: const Value('Supermarket'),
        ),
      );

      final exportService = ExportService(db);
      final result = await exportService.createFullBackupZip(targetDirectoryPath: tempDir.path);

      expect(result.success, isTrue);
      expect(result.filePath, isNotNull);
      expect(result.fileSizeBytes, greaterThan(0));
      expect(result.recordCount, equals(1));

      // Verify the generated zip file exists and can be decoded
      final zipFile = File(result.filePath!);
      expect(await zipFile.exists(), isTrue);

      final zipBytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      expect(archive.files.length, equals(1));
      final jsonFile = archive.files.first;
      expect(jsonFile.name, equals('backup_data.json'));

      final jsonString = utf8.decode(jsonFile.content as List<int>);
      final decoded = json.decode(jsonString) as Map<String, dynamic>;

      expect(decoded['version'], equals(1));
      expect(decoded['app'], equals('Expense Tracker'));
      expect((decoded['accounts'] as List).length, equals(1));
      expect((decoded['categories'] as List).length, equals(1));
      expect((decoded['transactions'] as List).length, equals(1));
      expect((decoded['settings'] as List).length, equals(1));
    });

    test('exportTransactionsToCsv creates a valid CSV file on disk', () async {
      final accId = await db.createAccount(
        const AccountsCompanion(label: Value('Wallet'), currency: Value('INR')),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: -12000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const Value('Snacks'),
        ),
      );

      final exportService = ExportService(db);
      final result = await exportService.exportTransactionsToCsv(
        targetDirectoryPath: tempDir.path,
        customFileName: 'test_export.csv',
      );

      expect(result.success, isTrue);
      expect(result.recordCount, equals(1));
      final exportedFile = File(result.filePath!);
      expect(await exportedFile.exists(), isTrue);

      final content = await exportedFile.readAsString();
      expect(content, contains('Wallet'));
      expect(content, contains('-120.00'));
      expect(content, contains('Snacks'));
    });

    test('generateFullBackupZipBytes returns valid in-memory zip bytes', () async {
      final accId = await db.createAccount(
        const AccountsCompanion(label: Value('Savings'), currency: Value('INR')),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          amount: 500000,
          date: DateTime.now(),
          valueDate: DateTime.now(),
        ),
      );

      final exportService = ExportService(db);
      final generated = await exportService.generateFullBackupZipBytes();

      expect(generated.bytes.isNotEmpty, isTrue);
      expect(generated.recordCount, equals(1));

      final archive = ZipDecoder().decodeBytes(generated.bytes);
      expect(archive.files.length, equals(1));
      expect(archive.files.first.name, equals('backup_data.json'));
    });

    test('createFullBackupZip saves directly to targetFilePath', () async {
      final exactPath = '${tempDir.path}/custom_backup_location/my_backup.zip';
      final exportService = ExportService(db);
      final result = await exportService.createFullBackupZip(targetFilePath: exactPath);

      expect(result.success, isTrue);
      expect(result.filePath, equals(exactPath));
      expect(await File(exactPath).exists(), isTrue);
    });

    test('exportFullBackupWithPicker saves backup anywhere user chooses via file picker', () async {
      final chosenSavePath = '${tempDir.path}/phone_storage/Downloads/user_backup.zip';
      final fakePicker = FakeFilePicker()..returnPath = chosenSavePath;

      final exportService = ExportService(db);
      final result = await exportService.exportFullBackupWithPicker(filePicker: fakePicker);

      expect(result.success, isTrue);
      expect(result.isCancelled, isFalse);
      expect(result.filePath, equals(chosenSavePath));
      expect(fakePicker.lastSavedBytes, isNotNull);
      expect(await File(chosenSavePath).exists(), isTrue);
    });

    test('exportFullBackupWithPicker handles user cancellation cleanly', () async {
      final fakePicker = FakeFilePicker()..returnPath = null; // user cancelled

      final exportService = ExportService(db);
      final result = await exportService.exportFullBackupWithPicker(filePicker: fakePicker);

      expect(result.success, isFalse);
      expect(result.isCancelled, isTrue);
      expect(result.errorMessage, contains('cancelled'));
    });

    test('exportCsvWithPicker saves CSV anywhere user chooses via file picker', () async {
      final chosenCsvPath = '${tempDir.path}/phone_storage/Documents/user_transactions.csv';
      final fakePicker = FakeFilePicker()..returnPath = chosenCsvPath;

      final exportService = ExportService(db);
      final result = await exportService.exportCsvWithPicker(filePicker: fakePicker);

      expect(result.success, isTrue);
      expect(result.isCancelled, isFalse);
      expect(result.filePath, equals(chosenCsvPath));
      expect(fakePicker.lastSavedBytes, isNotNull);
      expect(await File(chosenCsvPath).exists(), isTrue);
    });

    test('exportCsvWithPicker handles user cancellation cleanly', () async {
      final fakePicker = FakeFilePicker()..returnPath = null; // user cancelled

      final exportService = ExportService(db);
      final result = await exportService.exportCsvWithPicker(filePicker: fakePicker);

      expect(result.success, isFalse);
      expect(result.isCancelled, isTrue);
      expect(result.errorMessage, contains('cancelled'));
    });

    test('Full Round-Trip: createFullBackupZip archive is restorable by BackupRestoreService', () async {
      // 1. Insert seed data
      final accId = await db.createAccount(
        const AccountsCompanion(label: Value('HDFC Bank'), currency: Value('INR')),
      );
      final catId = await db.createCategory(
        const CategoriesCompanion(label: Value('Utilities'), type: Value(0)),
      );
      final payeeId = await db.createPayee(
        const PayeesCompanion(name: Value('Electricity Board')),
      );
      await db.createTransaction(
        TransactionsCompanion.insert(
          accountId: accId,
          catId: Value(catId),
          payeeId: Value(payeeId),
          amount: -350000, // -₹3,500.00
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const Value('Monthly Power Bill'),
        ),
      );

      // 2. Export full backup zip
      final exportPath = '${tempDir.path}/full_roundtrip_backup.zip';
      final exportService = ExportService(db);
      final exportRes = await exportService.createFullBackupZip(targetFilePath: exportPath);
      expect(exportRes.success, isTrue);

      // 3. Create a fresh clean database and restore from the exported zip
      final freshDb = AppDatabase(NativeDatabase.memory());
      try {
        final restoreService = BackupRestoreService(freshDb);
        final restoreRes = await restoreService.restoreBackup(exportPath);

        expect(restoreRes.success, isTrue);
        expect(restoreRes.accountsCount, equals(1));
        expect(restoreRes.categoriesCount, equals(1));
        expect(restoreRes.payeesCount, equals(1));
        expect(restoreRes.transactionsCount, equals(1));
        expect(restoreRes.totalExpenses, equals(350000));

        // Verify data in freshDb
        final restoredAccounts = await freshDb.getAllAccounts();
        expect(restoredAccounts.first.label, equals('HDFC Bank'));
        final restoredCategories = await freshDb.getAllCategories();
        expect(restoredCategories.first.label, equals('Utilities'));
        final restoredTxs = await freshDb.select(freshDb.transactions).get();
        expect(restoredTxs.first.comment, equals('Monthly Power Bill'));
      } finally {
        await freshDb.close();
      }
    });
  });
}

class FakeFilePicker extends FilePicker {
  String? returnPath;
  String? lastFileName;
  Uint8List? lastSavedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lastFileName = fileName;
    lastSavedBytes = bytes;
    if (returnPath != null && bytes != null) {
      final f = File(returnPath!);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
    }
    return returnPath;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async => null;

  @override
  Future<bool?> clearTemporaryFiles() async => true;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async => null;
}
