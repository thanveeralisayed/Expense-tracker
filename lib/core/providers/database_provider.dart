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

// Aggregate financial statistics
final financialTotalsProvider = FutureProvider<Map<String, int>>((ref) {
  final db = ref.watch(databaseProvider);
  final selectedAccountId = ref.watch(selectedAccountIdProvider);
  // Re-run whenever transactions change
  ref.watch(transactionsStreamProvider);
  return db.getTotals(accountId: selectedAccountId);
});
