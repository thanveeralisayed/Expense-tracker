import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Accounts,
  Categories,
  Payees,
  PaymentMethods,
  Transactions,
  Currencies,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // Stream all accounts
  Stream<List<Account>> watchAllAccounts() {
    return (select(accounts)..orderBy([(t) => OrderingTerm(expression: t.sortKey)])).watch();
  }

  // Get all accounts once
  Future<List<Account>> getAllAccounts() {
    return (select(accounts)..orderBy([(t) => OrderingTerm(expression: t.sortKey)])).get();
  }

  // Stream transactions for an account (or all accounts if null)
  Stream<List<Transaction>> watchTransactions({int? accountId, int limit = 200, bool includeSplits = false}) {
    final query = select(transactions);
    if (!includeSplits) {
      query.where((t) => t.parentId.isNull());
    }
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    query.limit(limit);
    return query.watch();
  }

  // Search transactions with multi-filters
  Stream<List<Transaction>> searchTransactionsStream({
    String? queryText,
    int? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? minPaise,
    int? maxPaise,
    bool includeSplits = false,
  }) {
    final query = select(transactions);

    if (!includeSplits) {
      query.where((t) => t.parentId.isNull());
    }
    if (queryText != null && queryText.trim().isNotEmpty) {
      query.where((t) => t.comment.like('%${queryText.trim()}%'));
    }
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    if (startDate != null) {
      query.where((t) => t.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.date.isSmallerOrEqualValue(endDate));
    }
    if (minPaise != null) {
      query.where((t) => t.amount.abs().isBiggerOrEqualValue(minPaise));
    }
    if (maxPaise != null) {
      query.where((t) => t.amount.abs().isSmallerOrEqualValue(maxPaise));
    }

    query.orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    return query.watch();
  }

  // Get total expense and income stats (excluding split children to avoid double-counting)
  Future<Map<String, int>> getTotals({int? accountId}) async {
    final query = select(transactions)..where((t) => t.parentId.isNull());
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    final all = await query.get();
    int expenses = 0;
    int income = 0;
    for (final tx in all) {
      if (tx.amount < 0) {
        expenses += -tx.amount;
      } else {
        income += tx.amount;
      }
    }
    return {
      'expenses': expenses,
      'income': income,
      'net': income - expenses,
      'count': all.length,
    };
  }

  // Get balance per account (excluding split children to avoid double-counting)
  Future<int> getAccountBalance(int accountId) async {
    final query = select(transactions)
      ..where((t) => t.accountId.equals(accountId))
      ..where((t) => t.parentId.isNull());
    final txs = await query.get();
    int balance = 0;
    for (final tx in txs) {
      balance += tx.amount;
    }
    return balance;
  }

  // Get all split children for a parent transaction
  Future<List<Transaction>> getSplitsForParent(int parentId) {
    return (select(transactions)..where((t) => t.parentId.equals(parentId))).get();
  }

  // Create single transaction (Expense or Income)
  Future<int> createTransaction(TransactionsCompanion entry) {
    return into(transactions).insert(entry);
  }

  // Update existing transaction
  Future<bool> updateTransaction(Transaction entry) {
    return update(transactions).replace(entry);
  }

  // Delete transaction and cascade peer/split children if present
  Future<void> deleteTransactionById(int id) async {
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (tx != null) {
        // If transfer peer exists, delete it too
        if (tx.transferPeer != null) {
          await (delete(transactions)..where((t) => t.id.equals(tx.transferPeer!))).go();
        }
        // If split parent, delete children
        await (delete(transactions)..where((t) => t.parentId.equals(id))).go();
        // Delete transaction itself
        await (delete(transactions)..where((t) => t.id.equals(id))).go();
      }
    });
  }

  // Execute inter-account fund transfer
  Future<void> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountPaise,
    required DateTime date,
    String? comment,
  }) async {
    await transaction(() async {
      // 1. Debit transaction from source account
      final fromId = await into(transactions).insert(
        TransactionsCompanion.insert(
          amount: -amountPaise.abs(),
          accountId: fromAccountId,
          date: date,
          valueDate: date,
          comment: Value(comment),
          transferAccount: Value(toAccountId),
        ),
      );

      // 2. Credit transaction to destination account
      final toId = await into(transactions).insert(
        TransactionsCompanion.insert(
          amount: amountPaise.abs(),
          accountId: toAccountId,
          date: date,
          valueDate: date,
          comment: Value(comment),
          transferAccount: Value(fromAccountId),
          transferPeer: Value(fromId),
        ),
      );

      // Link back the peer on the from transaction
      await (update(transactions)..where((t) => t.id.equals(fromId))).write(
        TransactionsCompanion(transferPeer: Value(toId)),
      );
    });
  }

  // Create split transaction (parent with child item allocations)
  Future<int> createSplitTransaction({
    required TransactionsCompanion parent,
    required List<TransactionsCompanion> splits,
  }) async {
    return await transaction(() async {
      final parentId = await into(transactions).insert(parent);
      for (final split in splits) {
        await into(transactions).insert(
          split.copyWith(parentId: Value(parentId)),
        );
      }
      return parentId;
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
