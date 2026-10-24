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
  Stream<List<Transaction>> watchTransactions({int? accountId, int limit = 100}) {
    final query = select(transactions);
    if (accountId != null) {
      query.where((t) => t.accountId.equals(accountId));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]);
    query.limit(limit);
    return query.watch();
  }

  // Get total expense and income stats
  Future<Map<String, int>> getTotals({int? accountId}) async {
    final query = select(transactions);
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

  // Get balance per account
  Future<int> getAccountBalance(int accountId) async {
    final query = select(transactions)..where((t) => t.accountId.equals(accountId));
    final txs = await query.get();
    int balance = 0;
    for (final tx in txs) {
      balance += tx.amount;
    }
    return balance;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
