import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:drift/drift.dart';

import '../database/database.dart';

class ExportResult {
  final bool success;
  final String? filePath;
  final int recordCount;
  final int fileSizeBytes;
  final String? errorMessage;

  const ExportResult({
    required this.success,
    this.filePath,
    this.recordCount = 0,
    this.fileSizeBytes = 0,
    this.errorMessage,
  });
}

class ExportService {
  final AppDatabase database;

  const ExportService(this.database);

  /// RFC 4180 Compliant CSV cell escape helper
  static String escapeCsvCell(String? value) {
    if (value == null) return '""';
    final str = value.trim();
    if (str.isEmpty) return '""';

    // If cell contains commas, double-quotes, or newlines, quote the entire field and escape double quotes
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      final escaped = str.replaceAll('"', '""');
      return '"$escaped"';
    }
    return '"$str"';
  }

  /// Generate RFC 4180 CSV string from transactions and lookup maps
  static String generateCsvString({
    required List<Transaction> transactions,
    required Map<int, Account> accountsMap,
    required Map<int, Category> categoriesMap,
    Map<int, Payee> payeesMap = const {},
    Map<int, PaymentMethod> methodsMap = const {},
  }) {
    final buffer = StringBuffer();
    // CSV Header row
    buffer.writeln(
      [
        'ID',
        'Date',
        'Time',
        'Account',
        'Type',
        'Category',
        'Amount',
        'Currency',
        'Raw Paise',
        'Payee',
        'Payment Method',
        'Note',
        'Status',
      ].map(escapeCsvCell).join(','),
    );

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    for (final tx in transactions) {
      final account = accountsMap[tx.accountId];
      final category = tx.catId != null ? categoriesMap[tx.catId!] : null;
      final payee = tx.payeeId != null ? payeesMap[tx.payeeId!] : null;
      final method = tx.methodId != null ? methodsMap[tx.methodId!] : null;

      final isTransfer = tx.transferAccount != null || tx.transferPeer != null;
      final typeLabel = isTransfer
          ? 'Transfer'
          : (tx.amount < 0 ? 'Expense' : 'Income');

      final double amountInRupees = tx.amount / 100.0;
      final amountFormatted = amountInRupees.toStringAsFixed(2);
      final currency = account?.currency ?? 'INR';

      final row = [
        tx.id.toString(),
        dateFormat.format(tx.date),
        timeFormat.format(tx.date),
        account?.label ?? 'Account #${tx.accountId}',
        typeLabel,
        category?.label ?? (isTransfer ? 'Transfer' : 'Uncategorized'),
        amountFormatted,
        currency,
        tx.amount.toString(),
        payee?.name ?? '',
        method?.label ?? '',
        tx.comment ?? '',
        tx.status == 1 ? 'Split Parent' : tx.crStatus,
      ];

      buffer.writeln(row.map(escapeCsvCell).join(','));
    }

    return buffer.toString();
  }

  /// Export transactions to CSV file on local storage
  Future<ExportResult> exportTransactionsToCsv({
    List<Transaction>? transactions,
    String? targetDirectoryPath,
    String? customFileName,
  }) async {
    try {
      final accounts = await database.getAllAccounts();
      final accountsMap = {for (final a in accounts) a.id: a};

      final categories = await database.getAllCategories();
      final categoriesMap = {for (final c in categories) c.id: c};

      final payees = await database.getAllPayees();
      final payeesMap = {for (final p in payees) p.id: p};

      final methods = await database.getAllPaymentMethods();
      final methodsMap = {for (final m in methods) m.id: m};

      final txList = transactions ??
          await (database.select(database.transactions)
                ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
              .get();

      final csvContent = generateCsvString(
        transactions: txList,
        accountsMap: accountsMap,
        categoriesMap: categoriesMap,
        payeesMap: payeesMap,
        methodsMap: methodsMap,
      );

      final dirPath = targetDirectoryPath ?? (await getApplicationDocumentsDirectory()).path;
      final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = customFileName ?? 'expense_tracker_export_$timeStamp.csv';
      final file = File(p.join(dirPath, fileName));

      await file.writeAsString(csvContent, flush: true);
      final fileSize = await file.length();

      return ExportResult(
        success: true,
        filePath: file.path,
        recordCount: txList.length,
        fileSizeBytes: fileSize,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        errorMessage: 'Failed to export CSV: $e',
      );
    }
  }

  /// Create full backup ZIP archive containing all application records as JSON
  Future<ExportResult> createFullBackupZip({String? targetDirectoryPath}) async {
    try {
      final accounts = await database.getAllAccounts();
      final categories = await database.getAllCategories();
      final transactions = await (database.select(database.transactions)
            ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
          .get();
      final payees = await database.getAllPayees();
      final methods = await database.getAllPaymentMethods();
      final settings = await database.watchAllSettings().first;

      final backupData = {
        'version': 1,
        'app': 'Expense Tracker',
        'build': 'Phase 7 Build',
        'exported_at': DateTime.now().toIso8601String(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'categories': categories.map((c) => c.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'payees': payees.map((p) => p.toJson()).toList(),
        'payment_methods': methods.map((m) => m.toJson()).toList(),
        'settings': settings.map((s) => s.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);

      // Create ZIP archive in memory
      final archive = Archive();
      archive.addFile(ArchiveFile('backup_data.json', jsonBytes.length, jsonBytes));

      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);

      final dirPath = targetDirectoryPath ?? (await getApplicationDocumentsDirectory()).path;
      final timeStamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final zipFile = File(p.join(dirPath, 'expense_tracker_backup_$timeStamp.zip'));

      await zipFile.writeAsBytes(zipBytes, flush: true);
      final fileSize = await zipFile.length();

      return ExportResult(
        success: true,
        filePath: zipFile.path,
        recordCount: transactions.length,
        fileSizeBytes: fileSize,
      );
    } catch (e) {
      return ExportResult(
        success: false,
        errorMessage: 'Failed to create backup ZIP: $e',
      );
    }
  }
}
