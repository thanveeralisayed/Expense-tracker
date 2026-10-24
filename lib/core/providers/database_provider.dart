import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../services/backup_restore_service.dart';

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

// Stream of transactions for currently selected account
final transactionsStreamProvider = StreamProvider<List<Transaction>>((ref) {
  final db = ref.watch(databaseProvider);
  final selectedAccountId = ref.watch(selectedAccountIdProvider);
  return db.watchTransactions(accountId: selectedAccountId);
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
