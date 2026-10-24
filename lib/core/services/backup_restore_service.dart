import 'dart:io';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../database/database.dart';

class RestoreResult {
  final bool success;
  final int accountsCount;
  final int transactionsCount;
  final int categoriesCount;
  final int payeesCount;
  final int totalExpenses; // in cents/paise
  final int totalIncome; // in cents/paise
  final int netBalance; // in cents/paise
  final String? errorMessage;

  const RestoreResult({
    required this.success,
    required this.accountsCount,
    required this.transactionsCount,
    required this.categoriesCount,
    required this.payeesCount,
    required this.totalExpenses,
    required this.totalIncome,
    required this.netBalance,
    this.errorMessage,
  });
}

class BackupRestoreService {
  final AppDatabase database;

  BackupRestoreService(this.database);

  /// Restores from a directory path containing BACKUP and BACKUP_PREF,
  /// or from a .zip backup archive.
  Future<RestoreResult> restoreBackup(String sourcePath) async {
    Directory? tempExtractDir;
    try {
      String backupDirPath;
      final file = File(sourcePath);
      final dir = Directory(sourcePath);

      if (await file.exists() && sourcePath.toLowerCase().endsWith('.zip')) {
        // Extract zip
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        tempExtractDir = await Directory.systemTemp.createTemp('backup_restore_');
        for (final archiveFile in archive) {
          final outPath = p.join(tempExtractDir.path, archiveFile.name);
          if (archiveFile.isFile) {
            final outFile = File(outPath);
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(archiveFile.content as List<int>);
          }
        }
        backupDirPath = tempExtractDir.path;
      } else if (await dir.exists()) {
        backupDirPath = dir.path;
      } else {
        return RestoreResult(
          success: false,
          accountsCount: 0,
          transactionsCount: 0,
          categoriesCount: 0,
          payeesCount: 0,
          totalExpenses: 0,
          totalIncome: 0,
          netBalance: 0,
          errorMessage: 'Source path does not exist: $sourcePath',
        );
      }

      final backupDbFile = File(p.join(backupDirPath, 'BACKUP'));
      if (!await backupDbFile.exists()) {
        return RestoreResult(
          success: false,
          accountsCount: 0,
          transactionsCount: 0,
          categoriesCount: 0,
          payeesCount: 0,
          totalExpenses: 0,
          totalIncome: 0,
          netBalance: 0,
          errorMessage: 'BACKUP SQLite file not found in $backupDirPath',
        );
      }

      // Open legacy SQLite database in read-only mode
      final legacyDb = sqlite.sqlite3.open(backupDbFile.path, mode: sqlite.OpenMode.readOnly);

      int accountsCount = 0;
      int transactionsCount = 0;
      int categoriesCount = 0;
      int payeesCount = 0;
      int totalExpenses = 0;
      int totalIncome = 0;

      // Ingest within an atomic transaction
      await database.transaction(() async {
        // 1. Clear existing records to ensure clean restore
        await database.delete(database.transactions).go();
        await database.delete(database.accounts).go();
        await database.delete(database.categories).go();
        await database.delete(database.payees).go();
        await database.delete(database.paymentMethods).go();
        await database.delete(database.currencies).go();
        await database.delete(database.appSettings).go();

        // 2. Import Currencies
        try {
          final curRows = legacyDb.select('SELECT _id, code, symbol, fraction_digits FROM currency');
          final curEntries = <CurrenciesCompanion>[];
          for (final row in curRows) {
            curEntries.add(CurrenciesCompanion.insert(
              id: Value(row['_id'] as int),
              code: (row['code'] ?? 'INR') as String,
              symbol: Value(row['symbol'] as String?),
              fractionDigits: Value((row['fraction_digits'] as int?) ?? 2),
            ));
          }
          await database.batch((b) => b.insertAll(database.currencies, curEntries));
        } catch (_) {}

        // 3. Import Accounts
        final accRows = legacyDb.select(
          'SELECT _id, label, opening_balance, description, currency, color, grouping, balance_type, uuid, exclude_from_totals, sealed, sort_key FROM accounts'
        );
        final accEntries = <AccountsCompanion>[];
        for (final row in accRows) {
          accEntries.add(AccountsCompanion.insert(
            id: Value(row['_id'] as int),
            label: (row['label'] ?? '') as String,
            openingBalance: Value((row['opening_balance'] as int?) ?? 0),
            description: Value(row['description'] as String?),
            currency: Value((row['currency'] ?? 'INR') as String),
            color: Value((row['color'] as int?) ?? -16738680),
            grouping: Value((row['grouping'] ?? 'MONTH') as String),
            balanceType: Value((row['balance_type'] ?? 'CURRENT') as String),
            uuid: Value(row['uuid'] as String?),
            excludeFromTotals: Value((row['exclude_from_totals'] == 1)),
            sealed: Value((row['sealed'] == 1)),
            sortKey: Value((row['sort_key'] as int?) ?? 0),
          ));
        }
        await database.batch((b) => b.insertAll(database.accounts, accEntries));
        accountsCount = accEntries.length;

        // 4. Import Categories
        try {
          final catRows = legacyDb.select(
            'SELECT _id, label, parent_id, color, icon, type, uuid FROM categories'
          );
          final catEntries = <CategoriesCompanion>[];
          for (final row in catRows) {
            catEntries.add(CategoriesCompanion.insert(
              id: Value(row['_id'] as int),
              label: (row['label'] ?? '') as String,
              parentId: Value(row['parent_id'] as int?),
              color: Value(row['color'] as int?),
              icon: Value(row['icon'] as String?),
              type: Value((row['type'] as int?) ?? 0),
              uuid: Value(row['uuid'] as String?),
            ));
          }
          await database.batch((b) => b.insertAll(database.categories, catEntries));
          categoriesCount = catEntries.length;
        } catch (_) {}

        // 5. Import Payees
        try {
          final payeeRows = legacyDb.select(
            'SELECT _id, name, short_name, iban, bic FROM payee'
          );
          final payeeEntries = <PayeesCompanion>[];
          for (final row in payeeRows) {
            payeeEntries.add(PayeesCompanion.insert(
              id: Value(row['_id'] as int),
              name: (row['name'] ?? '') as String,
              shortName: Value(row['short_name'] as String?),
              iban: Value(row['iban'] as String?),
              bic: Value(row['bic'] as String?),
            ));
          }
          await database.batch((b) => b.insertAll(database.payees, payeeEntries));
          payeesCount = payeeEntries.length;
        } catch (_) {}

        // 6. Import Payment Methods
        try {
          final pmRows = legacyDb.select(
            'SELECT _id, label, type, icon FROM paymentmethods'
          );
          final pmEntries = <PaymentMethodsCompanion>[];
          for (final row in pmRows) {
            pmEntries.add(PaymentMethodsCompanion.insert(
              id: Value(row['_id'] as int),
              label: (row['label'] ?? '') as String,
              type: Value((row['type'] as int?) ?? 0),
              icon: Value(row['icon'] as String?),
            ));
          }
          await database.batch((b) => b.insertAll(database.paymentMethods, pmEntries));
        } catch (_) {}

        // 7. Import Transactions
        final txRows = legacyDb.select(
          'SELECT _id, comment, date, value_date, amount, cat_id, account_id, payee_id, transfer_peer, transfer_account, method_id, parent_id, status, cr_status, number, uuid, debt_id FROM transactions'
        );
        final txEntries = <TransactionsCompanion>[];
        for (final row in txRows) {
          final amt = (row['amount'] as int?) ?? 0;
          if (amt < 0) {
            totalExpenses += -amt;
          } else {
            totalIncome += amt;
          }

          final dateSecs = (row['date'] as int?) ?? 0;
          final valueDateSecs = (row['value_date'] as int?) ?? dateSecs;

          txEntries.add(TransactionsCompanion.insert(
            id: Value(row['_id'] as int),
            comment: Value(row['comment'] as String?),
            date: DateTime.fromMillisecondsSinceEpoch(dateSecs * 1000),
            valueDate: DateTime.fromMillisecondsSinceEpoch(valueDateSecs * 1000),
            amount: amt,
            catId: Value(row['cat_id'] as int?),
            accountId: row['account_id'] as int,
            payeeId: Value(row['payee_id'] as int?),
            transferPeer: Value(row['transfer_peer'] as int?),
            transferAccount: Value(row['transfer_account'] as int?),
            methodId: Value(row['method_id'] as int?),
            parentId: Value(row['parent_id'] as int?),
            status: Value((row['status'] as int?) ?? 0),
            crStatus: Value((row['cr_status'] as String?) ?? 'RECONCILED'),
            number: Value(row['number'] as String?),
            uuid: Value(row['uuid'] as String?),
            debtId: Value(row['debt_id'] as int?),
          ));
        }
        await database.batch((b) => b.insertAll(database.transactions, txEntries));
        transactionsCount = txEntries.length;

        // 8. Ingest BACKUP_PREF XML if exists
        final prefFile = File(p.join(backupDirPath, 'BACKUP_PREF'));
        if (await prefFile.exists()) {
          try {
            final xmlString = await prefFile.readAsString();
            final doc = XmlDocument.parse(xmlString);
            final settingsEntries = <AppSettingsCompanion>[];
            for (final el in doc.rootElement.children.whereType<XmlElement>()) {
              final key = el.getAttribute('name');
              final val = el.getAttribute('value') ?? el.innerText;
              if (key != null) {
                settingsEntries.add(AppSettingsCompanion.insert(
                  key: key,
                  value: Value(val),
                ));
              }
            }
            await database.batch((b) => b.insertAll(
              database.appSettings,
              settingsEntries,
              mode: InsertMode.insertOrReplace,
            ));
          } catch (_) {}
        }
      });

      legacyDb.dispose();

      return RestoreResult(
        success: true,
        accountsCount: accountsCount,
        transactionsCount: transactionsCount,
        categoriesCount: categoriesCount,
        payeesCount: payeesCount,
        totalExpenses: totalExpenses,
        totalIncome: totalIncome,
        netBalance: totalIncome - totalExpenses,
      );
    } catch (e, stack) {
      return RestoreResult(
        success: false,
        accountsCount: 0,
        transactionsCount: 0,
        categoriesCount: 0,
        payeesCount: 0,
        totalExpenses: 0,
        totalIncome: 0,
        netBalance: 0,
        errorMessage: 'Error during restore: $e\n$stack',
      );
    } finally {
      if (tempExtractDir != null && await tempExtractDir.exists()) {
        try {
          await tempExtractDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
