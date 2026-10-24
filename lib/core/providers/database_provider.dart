import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../services/backup_restore_service.dart';
import '../../features/analytics/domain/analytics_service.dart';
import '../../features/budgets/domain/budget_models.dart';
import '../../features/budgets/domain/budget_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final backupRestoreServiceProvider = Provider<BackupRestoreService>((ref) {
  final db = ref.watch(databaseProvider);
  return BackupRestoreService(db);
});

// Stream of all accounts
final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllAccounts();
});

// Currently selected account ID (null means all accounts)
final selectedAccountIdProvider = StateProvider<int?>((ref) => null);

// Stream of transactions for currently selected account (excluding split children for list display)
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  final selectedAccountId = ref.watch(selectedAccountIdProvider);
  return db.watchTransactions(accountId: selectedAccountId);
});

// Stream of all transactions including split allocations (used by budgets and analytics)
final allTransactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  final selectedAccountId = ref.watch(selectedAccountIdProvider);
  return db.watchTransactions(accountId: selectedAccountId, limit: 1000, includeSplits: true);
});

// Balances for all accounts mapped by account ID
final accountBalancesProvider = FutureProvider<Map<int, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(transactionsStreamProvider); // invalidate when transactions change
  final accounts = await db.getAllAccounts();
  final map = <int, int>{};
  for (final acc in accounts) {
    map[acc.id] = await db.getAccountBalance(acc.id);
  }
  return map;
});

// Aggregate financial statistics
final financialTotalsProvider = FutureProvider<Map<String, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  final selectedAccountId = ref.watch(selectedAccountIdProvider);
  ref.watch(transactionsStreamProvider); // invalidate when transactions change
  return db.getTotals(accountId: selectedAccountId);
});

// Stream of all categories
final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllCategories();
});

// Categories lookup map (id -> Category)
final categoryMapProvider = Provider<Map<int, Category>>((ref) {
  final asyncCategories = ref.watch(categoriesStreamProvider);
  return asyncCategories.when(
    data: (categories) => {for (final cat in categories) cat.id: cat},
    loading: () => {},
    error: (_, _) => {},
  );
});

// Stream of all payees
final payeesStreamProvider = StreamProvider<List<Payee>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllPayees();
});

// Payees lookup map (id -> Payee)
final payeesMapProvider = Provider<Map<int, Payee>>((ref) {
  final asyncPayees = ref.watch(payeesStreamProvider);
  return asyncPayees.when(
    data: (payees) => {for (final p in payees) p.id: p},
    loading: () => {},
    error: (_, _) => {},
  );
});

// Stream of all payment methods
final paymentMethodsStreamProvider = StreamProvider<List<PaymentMethod>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllPaymentMethods();
});

// Payment methods lookup map (id -> PaymentMethod)
final paymentMethodsMapProvider = Provider<Map<int, PaymentMethod>>((ref) {
  final asyncMethods = ref.watch(paymentMethodsStreamProvider);
  return asyncMethods.when(
    data: (methods) => {for (final m in methods) m.id: m},
    loading: () => {},
    error: (_, _) => {},
  );
});

// Category transaction usage counts
final categoryUsageCountsProvider = FutureProvider<Map<int, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(transactionsStreamProvider); // invalidate when transactions change
  return db.getCategoryUsageCounts();
});

// Uncategorized transactions count
final uncategorizedCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  ref.watch(transactionsStreamProvider);
  final uncategorized = await db.getUncategorizedTransactions();
  return uncategorized.length;
});

// Settings stream
final settingsStreamProvider = StreamProvider<List<AppSetting>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllSettings();
});

// Parsed budget limits
final budgetLimitsProvider = Provider<({int? overallLimitPaise, Map<int, int> categoryLimitsPaise})>((ref) {
  final asyncSettings = ref.watch(settingsStreamProvider);
  return asyncSettings.when(
    data: (settings) => BudgetService.parseBudgetLimits(settings),
    loading: () => (overallLimitPaise: null, categoryLimitsPaise: <int, int>{}),
    error: (_, _) => (overallLimitPaise: null, categoryLimitsPaise: <int, int>{}),
  );
});

// Overall monthly budget progress
final overallBudgetProgressProvider = Provider<BudgetProgress?>((ref) {
  final limits = ref.watch(budgetLimitsProvider);
  if (limits.overallLimitPaise == null) return null;

  final asyncTxs = ref.watch(transactionsStreamProvider);
  return asyncTxs.when(
    data: (txs) {
      final monthExpenses = BudgetService.filterCurrentMonthExpenses(txs);
      return BudgetService.calculateOverallBudget(
        limitPaise: limits.overallLimitPaise!,
        currentMonthExpenses: monthExpenses,
      );
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

// Category monthly budgets progress list
final categoryBudgetsProgressProvider = Provider<List<BudgetProgress>>((ref) {
  final limits = ref.watch(budgetLimitsProvider);
  if (limits.categoryLimitsPaise.isEmpty) return [];

  final asyncTxs = ref.watch(allTransactionsStreamProvider);
  final catMap = ref.watch(categoryMapProvider);

  return asyncTxs.when(
    data: (txs) {
      final monthExpenses = BudgetService.filterCurrentMonthExpenses(txs, includeSplits: true);
      final list = <BudgetProgress>[];
      for (final entry in limits.categoryLimitsPaise.entries) {
        list.add(
          BudgetService.calculateCategoryBudget(
            catId: entry.key,
            limitPaise: entry.value,
            currentMonthExpenses: monthExpenses,
            categoryMap: catMap,
          ),
        );
      }
      list.sort((a, b) => b.percentage.compareTo(a.percentage));
      return list;
    },
    loading: () => [],
    error: (_, _) => [],
  );
});

// Analytics timeframe provider
final analyticsTimeframeProvider = StateProvider<AnalyticsTimeframe>((ref) => AnalyticsTimeframe.thisMonth);

// Theme mode provider (system, dark, light)
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

