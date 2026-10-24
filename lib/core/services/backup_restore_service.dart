import 'dart:io';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';

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

  /// Generically restores from any:
  /// 1. .zip backup archive (regardless of nested folder structure)
  /// 2. Raw SQLite database file (e.g. BACKUP, *.sqlite, *.db)
  /// 3. Unzipped directory containing backup files
  Future<RestoreResult> restoreBackup(String sourcePath) async {
    Directory? tempExtractDir;
    try {
      String searchDirPath;
      final file = File(sourcePath);
      final dir = Directory(sourcePath);

      if (await file.exists()) {
        final lowerPath = sourcePath.toLowerCase();
        if (lowerPath.endsWith('.zip')) {
          // Extract .zip archive to a temp directory
          tempExtractDir = await Directory.systemTemp.createTemp('backup_restore_');
          await extractFileToDisk(sourcePath, tempExtractDir.path);
          searchDirPath = tempExtractDir.path;
        } else {
          // Direct file passed (e.g. BACKUP or a .sqlite / .db file)
          searchDirPath = file.parent.path;
        }
      } else if (await dir.exists()) {
        searchDirPath = dir.path;
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
          errorMessage: 'Selected path does not exist: $sourcePath',
        );
      }

      // Discover SQLite database file
      final backupDbFile = _findSqliteDatabase(searchDirPath, directPath: sourcePath);
      if (backupDbFile == null || !await backupDbFile.exists()) {
        return const RestoreResult(
          success: false,
          accountsCount: 0,
          transactionsCount: 0,
          categoriesCount: 0,
          payeesCount: 0,
          totalExpenses: 0,
          totalIncome: 0,
          netBalance: 0,
          errorMessage: 'No valid SQLite database (BACKUP or .db file) found in the selected file or folder.',
        );
      }

      // Open SQLite database in read-only mode
      final legacyDb = sqlite.sqlite3.open(backupDbFile.path, mode: sqlite.OpenMode.readOnly);

      // Inspect available tables
      final tableNames = legacyDb
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => (r['name'] as String).toLowerCase())
          .toSet();

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

        // 2. Import Currencies (if currency table exists)
        if (tableNames.contains('currency')) {
          try {
            final curRows = legacyDb.select('SELECT * FROM currency');
            final curEntries = <CurrenciesCompanion>[];
            for (final row in curRows) {
              final id = (row['_id'] ?? row['id']) as int?;
              final code = (row['code'] as String?) ?? 'INR';
              final symbol = row['symbol'] as String?;
              final frac = (row['fraction_digits'] as int?) ?? 2;

              curEntries.add(CurrenciesCompanion.insert(
                id: id != null ? Value(id) : const Value.absent(),
                code: code,
                symbol: Value(symbol),
                fractionDigits: Value(frac),
              ));
            }
            if (curEntries.isNotEmpty) {
              await database.batch((b) => b.insertAll(database.currencies, curEntries));
            }
          } catch (_) {}
        }

        // 3. Import Accounts (if accounts table exists)
        if (tableNames.contains('accounts')) {
          final accRows = legacyDb.select('SELECT * FROM accounts');
          final accEntries = <AccountsCompanion>[];
          for (final row in accRows) {
            final id = (row['_id'] ?? row['id']) as int;
            final label = (row['label'] ?? row['name'] ?? 'Account $id') as String;
            final openingBal = (row['opening_balance'] as int?) ?? 0;
            final desc = row['description'] as String?;
            final cur = (row['currency'] as String?) ?? 'INR';
            final color = (row['color'] as int?) ?? -16738680;
            final grouping = (row['grouping'] as String?) ?? 'MONTH';
            final balType = (row['balance_type'] as String?) ?? 'CURRENT';
            final uuid = row['uuid'] as String?;
            final exclude = row['exclude_from_totals'] == 1;
            final sealed = row['sealed'] == 1;
            final sortKey = (row['sort_key'] as int?) ?? 0;

            accEntries.add(AccountsCompanion.insert(
              id: Value(id),
              label: label,
              openingBalance: Value(openingBal),
              description: Value(desc),
              currency: Value(cur),
              color: Value(color),
              grouping: Value(grouping),
              balanceType: Value(balType),
              uuid: Value(uuid),
              excludeFromTotals: Value(exclude),
              sealed: Value(sealed),
              sortKey: Value(sortKey),
            ));
          }
          if (accEntries.isNotEmpty) {
            await database.batch((b) => b.insertAll(database.accounts, accEntries));
            accountsCount = accEntries.length;
          }
        }

        // 4. Import Categories (if categories table exists)
        if (tableNames.contains('categories')) {
          try {
            final catRows = legacyDb.select('SELECT * FROM categories');
            final catEntries = <CategoriesCompanion>[];
            for (final row in catRows) {
              final id = (row['_id'] ?? row['id']) as int;
              final label = (row['label'] ?? row['name'] ?? '') as String;
              final parentId = row['parent_id'] as int?;
              final color = row['color'] as int?;
              final icon = row['icon'] as String?;
              final type = (row['type'] as int?) ?? 0;
              final uuid = row['uuid'] as String?;

              catEntries.add(CategoriesCompanion.insert(
                id: Value(id),
                label: label,
                parentId: Value(parentId),
                color: Value(color),
                icon: Value(icon),
                type: Value(type),
                uuid: Value(uuid),
              ));
            }
            if (catEntries.isNotEmpty) {
              await database.batch((b) => b.insertAll(database.categories, catEntries));
              categoriesCount = catEntries.length;
            }
          } catch (_) {}
        }

        // 5. Import Payees (if payee table exists)
        if (tableNames.contains('payee')) {
          try {
            final payeeRows = legacyDb.select('SELECT * FROM payee');
            final payeeEntries = <PayeesCompanion>[];
            for (final row in payeeRows) {
              final id = (row['_id'] ?? row['id']) as int;
              final name = (row['name'] ?? '') as String;
              final shortName = row['short_name'] as String?;
              final iban = row['iban'] as String?;
              final bic = row['bic'] as String?;

              payeeEntries.add(PayeesCompanion.insert(
                id: Value(id),
                name: name,
                shortName: Value(shortName),
                iban: Value(iban),
                bic: Value(bic),
              ));
            }
            if (payeeEntries.isNotEmpty) {
              await database.batch((b) => b.insertAll(database.payees, payeeEntries));
              payeesCount = payeeEntries.length;
            }
          } catch (_) {}
        }

        // 6. Import Payment Methods (if paymentmethods table exists)
        if (tableNames.contains('paymentmethods')) {
          try {
            final pmRows = legacyDb.select('SELECT * FROM paymentmethods');
            final pmEntries = <PaymentMethodsCompanion>[];
            for (final row in pmRows) {
              final id = (row['_id'] ?? row['id']) as int;
              final label = (row['label'] ?? '') as String;
              final type = (row['type'] as int?) ?? 0;
              final icon = row['icon'] as String?;

              pmEntries.add(PaymentMethodsCompanion.insert(
                id: Value(id),
                label: label,
                type: Value(type),
                icon: Value(icon),
              ));
            }
            if (pmEntries.isNotEmpty) {
              await database.batch((b) => b.insertAll(database.paymentMethods, pmEntries));
            }
          } catch (_) {}
        }

        // 7. Import Transactions (if transactions table exists)
        if (tableNames.contains('transactions')) {
          final txRows = legacyDb.select('SELECT * FROM transactions');
          final txEntries = <TransactionsCompanion>[];
          for (final row in txRows) {
            final id = (row['_id'] ?? row['id']) as int;
            final amt = (row['amount'] as int?) ?? 0;
            if (amt < 0) {
              totalExpenses += -amt;
            } else {
              totalIncome += amt;
            }

            final dateSecs = (row['date'] as int?) ?? 0;
            final valueDateSecs = (row['value_date'] as int?) ?? dateSecs;

            txEntries.add(TransactionsCompanion.insert(
              id: Value(id),
              comment: Value(row['comment'] as String?),
              date: DateTime.fromMillisecondsSinceEpoch(dateSecs * 1000),
              valueDate: DateTime.fromMillisecondsSinceEpoch(valueDateSecs * 1000),
              amount: amt,
              catId: Value(row['cat_id'] as int?),
              accountId: (row['account_id'] as int?) ?? 1,
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
          if (txEntries.isNotEmpty) {
            await database.batch((b) => b.insertAll(database.transactions, txEntries));
            transactionsCount = txEntries.length;
          }
        }

        // 8. Ingest preferences XML if present
        final prefFile = _findPreferencesFile(searchDirPath);
        if (prefFile != null && await prefFile.exists()) {
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
            if (settingsEntries.isNotEmpty) {
              await database.batch((b) => b.insertAll(
                database.appSettings,
                settingsEntries,
                mode: InsertMode.insertOrReplace,
              ));
            }
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

  /// Recursively discovers any SQLite database file in a folder
  File? _findSqliteDatabase(String dirPath, {String? directPath}) {
    if (directPath != null) {
      final f = File(directPath);
      if (f.existsSync() && _isSqliteHeader(f)) {
        return f;
      }
    }

    final directBackup = File(p.join(dirPath, 'BACKUP'));
    if (directBackup.existsSync()) return directBackup;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    final entities = dir.listSync(recursive: true);

    // 1. Check for filename BACKUP or *.db or *.sqlite
    for (final entity in entities) {
      if (entity is File) {
        final name = p.basename(entity.path).toLowerCase();
        if (name == 'backup' || name.endsWith('.db') || name.endsWith('.sqlite')) {
          if (_isSqliteHeader(entity)) {
            return entity;
          }
        }
      }
    }

    // 2. Fallback: check any file for SQLite magic header
    for (final entity in entities) {
      if (entity is File && entity.lengthSync() >= 16) {
        if (_isSqliteHeader(entity)) {
          return entity;
        }
      }
    }

    return null;
  }

  bool _isSqliteHeader(File file) {
    try {
      if (file.lengthSync() < 16) return false;
      final raf = file.openSync(mode: FileMode.read);
      final bytes = raf.readSync(16);
      raf.closeSync();
      return String.fromCharCodes(bytes.take(15)) == 'SQLite format 3';
    } catch (_) {
      return false;
    }
  }

  /// Discovers preferences XML file
  File? _findPreferencesFile(String dirPath) {
    final direct = File(p.join(dirPath, 'BACKUP_PREF'));
    if (direct.existsSync()) return direct;

    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final name = p.basename(entity.path).toLowerCase();
        if (name == 'backup_pref' || name.endsWith('_pref') || name.endsWith('.xml')) {
          return entity;
        }
      }
    }
    return null;
  }
}
