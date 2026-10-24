import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/database/database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'widgets/total_balance_card.dart';
import 'widgets/account_card_carousel.dart';
import '../../transactions/presentation/widgets/transaction_list_tile.dart';
import '../../transactions/presentation/widgets/sticky_date_header.dart';
import '../../transactions/presentation/add_transaction_sheet.dart';
import '../../transactions/presentation/transaction_detail_screen.dart';
import '../../transactions/presentation/transaction_search_delegate.dart';
import '../../accounts/presentation/create_account_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isRestoring = false;

  Future<void> _restoreFromPath(String path) async {
    setState(() => _isRestoring = true);
    final restoreService = ref.read(backupRestoreServiceProvider);

    try {
      final res = await restoreService.restoreBackup(path);
      if (!mounted) return;

      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.income,
            duration: const Duration(seconds: 4),
            content: Text(
              'Successfully restored ${res.transactionsCount} transactions across ${res.accountsCount} accounts!',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            duration: const Duration(seconds: 5),
            content: Text(res.errorMessage ?? 'Restore failed'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Error: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _pickAndRestoreFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: 'Select My Expenses Backup (.zip)',
      );
      if (result != null && result.files.single.path != null) {
        await _restoreFromPath(result.files.single.path!);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('File picker error: $e'),
        ),
      );
    }
  }

  Future<void> _pickAndRestoreFolder() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select My Expenses Backup Folder',
      );
      if (selectedDirectory != null) {
        await _restoreFromPath(selectedDirectory);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Folder picker error: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsStreamProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accountsMap = <int, Account>{};
    for (final acc in accountsAsync.value ?? <Account>[]) {
      accountsMap[acc.id] = acc;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Expenses'),
        actions: [
          IconButton(
            tooltip: 'Search Transactions',
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              showSearch(
                context: context,
                delegate: TransactionSearchDelegate(ref),
              );
            },
          ),
          IconButton(
            tooltip: 'Add Account',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => CreateAccountDialog.show(context),
          ),
          IconButton(
            tooltip: 'Restore Backup',
            icon: _isRestoring
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_backup_restore_rounded),
            onPressed: _isRestoring ? null : () => _showRestoreDialog(),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Total Balance Card
          const SliverToBoxAdapter(child: TotalBalanceCard()),

          // Horizontal Accounts Carousel
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const AccountCardCarousel(),
            ),
          ),

          // Transactions Stream
          transactionsAsync.when(
            data: (txList) {
              if (txList.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.account_balance_wallet_outlined,
                              size: 56,
                              color: AppColors.primaryLight,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Transactions Yet',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start by creating an account (e.g. Cash, Bank) or restore an existing backup file.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => CreateAccountDialog.show(context),
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                label: const Text('Create New Account'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isRestoring ? null : _pickAndRestoreFile,
                                icon: const Icon(Icons.file_open_rounded),
                                label: const Text('Restore Backup File (.zip)'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isRestoring ? null : _pickAndRestoreFolder,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Select Backup Folder'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              // Group transactions by month
              final groups = <String, List<Transaction>>{};
              final groupMonthSums = <String, int>{};

              for (final tx in txList) {
                final key = DateFormat('MMMM yyyy').format(tx.date);
                groups.putIfAbsent(key, () => []).add(tx);
                groupMonthSums[key] = (groupMonthSums[key] ?? 0) + tx.amount;
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final monthKey = groups.keys.elementAt(index);
                    final monthTxs = groups[monthKey]!;
                    final monthSum = groupMonthSums[monthKey] ?? 0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MonthSectionHeader(
                          title: monthKey,
                          count: monthTxs.length,
                          monthTotalPaise: monthSum,
                        ),
                        ...monthTxs.map(
                          (tx) => TransactionListTile(
                            transaction: tx,
                            account: accountsMap[tx.accountId],
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => TransactionDetailSheet(
                                  transaction: tx,
                                  account: accountsMap[tx.accountId],
                                  transferAccount: tx.transferAccount != null ? accountsMap[tx.transferAccount] : null,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                  childCount: groups.keys.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(child: Text('Error loading transactions: $err')),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const AddTransactionSheet(),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Entry'),
      ),
    );
  }

  void _showRestoreDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restore Backup',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Import your data from any My Expenses backup archive (.zip) or folder.',
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.archive_rounded, color: Colors.white),
                ),
                title: const Text('Browse Backup Archive (.zip)'),
                subtitle: const Text('Select a .zip backup from Downloads or Drive'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndRestoreFile();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.transfer,
                  child: Icon(Icons.folder_open_rounded, color: Colors.white),
                ),
                title: const Text('Select Backup Folder'),
                subtitle: const Text('Browse for an unzipped backup directory'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndRestoreFolder();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
