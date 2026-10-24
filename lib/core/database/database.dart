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

  // Create new account
  Future<int> createAccount(AccountsCompanion account) {
    return into(accounts).insert(account);
  }

  // Update existing account
  Future<bool> updateAccount(Account account) {
    return update(accounts).replace(account);
  }

  // Delete account by ID
  Future<int> deleteAccount(int accountId) {
    return (delete(accounts)..where((a) => a.id.equals(accountId))).go();
  }

  // --- Category Methods ---

  // Stream all categories
  Stream<List<Category>> watchAllCategories() {
    return (select(categories)..orderBy([(t) => OrderingTerm(expression: t.label)])).watch();
  }

  // Get all categories once
  Future<List<Category>> getAllCategories() {
    return (select(categories)..orderBy([(t) => OrderingTerm(expression: t.label)])).get();
  }

  // Create category
  Future<int> createCategory(CategoriesCompanion entry) {
    return into(categories).insert(entry);
  }

  // Update category
  Future<bool> updateCategory(Category entry) {
    return update(categories).replace(entry);
  }

  // Delete category with cascade safeguard (unlinks child categories and transactions)
  Future<void> deleteCategory(int categoryId) async {
    await transaction(() async {
      // 1. Unlink child categories (set parentId = null)
      await (update(categories)..where((c) => c.parentId.equals(categoryId))).write(
        const CategoriesCompanion(parentId: Value(null)),
      );
      // 2. Unlink transactions (set catId = null)
      await (update(transactions)..where((t) => t.catId.equals(categoryId))).write(
        const TransactionsCompanion(catId: Value(null)),
      );
      // 3. Delete category itself
      await (delete(categories)..where((c) => c.id.equals(categoryId))).go();
    });
  }

  // Get category usage counts: map of categoryId -> count of transactions
  Future<Map<int, int>> getCategoryUsageCounts() async {
    final all = await (select(transactions)..where((t) => t.catId.isNotNull())).get();
    final counts = <int, int>{};
    for (final tx in all) {
      if (tx.catId != null) {
        counts[tx.catId!] = (counts[tx.catId!] ?? 0) + 1;
      }
    }
    return counts;
  }

  // Get uncategorized transactions (excluding transfers, split parents, and opening balance entries)
  Future<List<Transaction>> getUncategorizedTransactions() {
    return (select(transactions)
          ..where((t) =>
              t.catId.isNull() &
              t.parentId.isNull() &
              t.transferAccount.isNull() &
              t.transferPeer.isNull() &
              t.status.equals(0) &
              (t.comment.isNull() |
                  (t.comment.like('Opening Balance%').not() &
                      t.comment.like('opening balance%').not())))
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc)]))
        .get();
  }

  // Batch update transaction categories in a single atomic transaction
  Future<void> batchUpdateTransactionCategories(Map<int, int> txIdToCatId) async {
    await transaction(() async {
      for (final entry in txIdToCatId.entries) {
        await (update(transactions)..where((t) => t.id.equals(entry.key))).write(
          TransactionsCompanion(catId: Value(entry.value)),
        );
      }
    });
  }

  // Seed default categories if none exist
  Future<void> seedDefaultCategoriesIfEmpty() async {
    final existing = await (select(categories)..limit(1)).get();
    if (existing.isNotEmpty) return;

    final defaultList = [
      // Expense Categories (type: 0)
      const CategoriesCompanion(label: Value('Groceries'), icon: Value('shopping_cart'), color: Value(0xFF10B981), type: Value(0)),
      const CategoriesCompanion(label: Value('Food & Dining'), icon: Value('restaurant'), color: Value(0xFFF59E0B), type: Value(0)),
      const CategoriesCompanion(label: Value('Fuel & Transport'), icon: Value('local_gas_station'), color: Value(0xFFEF4444), type: Value(0)),
      const CategoriesCompanion(label: Value('Home & Capital'), icon: Value('home_repair_service'), color: Value(0xFF8B5CF6), type: Value(0)),
      const CategoriesCompanion(label: Value('Health & Medical'), icon: Value('medical_services'), color: Value(0xFFEC4899), type: Value(0)),
      const CategoriesCompanion(label: Value('Utilities & Bills'), icon: Value('bolt'), color: Value(0xFF3B82F6), type: Value(0)),
      const CategoriesCompanion(label: Value('Shopping'), icon: Value('shopping_bag'), color: Value(0xFF06B6D4), type: Value(0)),
      const CategoriesCompanion(label: Value('Family Support'), icon: Value('family_restroom'), color: Value(0xFFF97316), type: Value(0)),
      const CategoriesCompanion(label: Value('Entertainment'), icon: Value('movie'), color: Value(0xFF6366F1), type: Value(0)),
      const CategoriesCompanion(label: Value('Education'), icon: Value('school'), color: Value(0xFF14B8A6), type: Value(0)),
      const CategoriesCompanion(label: Value('Other Expense'), icon: Value('more_horiz'), color: Value(0xFF64748B), type: Value(0)),

      // Income Categories (type: 1)
      const CategoriesCompanion(label: Value('Salary'), icon: Value('payments'), color: Value(0xFF10B981), type: Value(1)),
      const CategoriesCompanion(label: Value('Business Profit'), icon: Value('trending_up'), color: Value(0xFF3B82F6), type: Value(1)),
      const CategoriesCompanion(label: Value('Gifts & Support'), icon: Value('card_giftcard'), color: Value(0xFFEC4899), type: Value(1)),
      const CategoriesCompanion(label: Value('Investment'), icon: Value('savings'), color: Value(0xFFF59E0B), type: Value(1)),
      const CategoriesCompanion(label: Value('Other Income'), icon: Value('account_balance_wallet'), color: Value(0xFF64748B), type: Value(1)),
    ];

    await batch((b) {
      b.insertAll(categories, defaultList);
    });
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

  // --- App Settings & Budgets ---
  Future<String?> getSetting(String key) async {
    final entry = await (select(appSettings)..where((s) => s.key.equals(key))).getSingleOrNull();
    return entry?.value;
  }

  Future<void> setSetting(String key, String? value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  Future<void> deleteSetting(String key) async {
    await (delete(appSettings)..where((s) => s.key.equals(key))).go();
  }

  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((s) => s?.value);
  }

  Stream<List<AppSetting>> watchAllSettings() {
    return select(appSettings).watch();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
