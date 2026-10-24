import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../categories/presentation/widgets/category_icon_helper.dart';
import 'add_transaction_sheet.dart';

class TransactionDetailSheet extends ConsumerWidget {
  final Transaction transaction;
  final Account? account;
  final Category? category;
  final Account? transferAccount;

  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    this.account,
    this.category,
    this.transferAccount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpense = transaction.amount < 0;
    final isTransfer = transaction.transferAccount != null || transaction.transferPeer != null;

    final Color statusColor = isTransfer
        ? AppColors.transfer
        : (isExpense ? AppColors.expense : AppColors.income);

    final String typeTitle = isTransfer
        ? 'Account Transfer'
        : (isExpense ? 'Expense' : 'Income');

    final dateStr = DateFormat('EEEE, dd MMMM yyyy, hh:mm a').format(transaction.date);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Center drag indicator
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Type badge & Amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      typeTitle.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        CurrencyFormatter.formatPaise(transaction.amount),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Note / Comment
            if (transaction.comment != null && transaction.comment!.isNotEmpty) ...[
              Text(
                transaction.comment!,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
            ],

            const Divider(),
            const SizedBox(height: 8),

            // Details List
            _DetailRow(
              icon: Icons.calendar_today_rounded,
              title: 'Date & Time',
              value: dateStr,
              isDark: isDark,
            ),
            const SizedBox(height: 12),

            _DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              title: isTransfer ? 'From Account' : 'Account',
              value: account?.label ?? 'Account #${transaction.accountId}',
              isDark: isDark,
            ),

            if (!isTransfer) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: CategoryIconHelper.getIcon(category?.icon),
                title: 'Category',
                value: category?.label ?? 'Uncategorized',
                isDark: isDark,
              ),
            ],

            if (isTransfer && transferAccount != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.arrow_forward_rounded,
                title: 'To Account',
                value: transferAccount!.label,
                isDark: isDark,
              ),
            ],

            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.verified_rounded,
              title: 'Status',
              value: transaction.crStatus,
              isDark: isDark,
            ),

            // FutureBuilder for Split items if any
            FutureBuilder<List<Transaction>>(
              future: ref.read(databaseProvider).getSplitsForParent(transaction.id),
              builder: (context, snapshot) {
                final splits = snapshot.data ?? [];
                if (splits.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Split Allocations (${splits.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: splits.map((s) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  s.comment ?? 'Split item',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.formatPaiseAbsolute(s.amount),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.expense,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // Edit, Duplicate & Delete Actions
            Row(
              children: [
                // Edit button
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => AddTransactionSheet(initialTransaction: transaction),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 8),

                // Duplicate button
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _duplicate(context, ref),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Duplicate'),
                  ),
                ),
                const SizedBox(width: 8),

                // Delete button
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.expense,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _confirmDelete(context, ref),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

  void _duplicate(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);
    final db = ref.read(databaseProvider);
    final isTransfer = transaction.transferAccount != null || transaction.transferPeer != null;

    try {
      if (isTransfer && transaction.transferAccount != null) {
        await db.createTransfer(
          fromAccountId: transaction.accountId,
          toAccountId: transaction.transferAccount!,
          amountPaise: transaction.amount.abs(),
          date: DateTime.now(),
          comment: transaction.comment != null ? '${transaction.comment!} (Copy)' : 'Transfer (Copy)',
        );
      } else {
        await db.createTransaction(
          TransactionsCompanion.insert(
            amount: transaction.amount,
            accountId: transaction.accountId,
            date: DateTime.now(),
            valueDate: DateTime.now(),
            comment: drift.Value(transaction.comment != null ? '${transaction.comment!} (Copy)' : 'Copy'),
            catId: drift.Value(transaction.catId),
            payeeId: drift.Value(transaction.payeeId),
            methodId: drift.Value(transaction.methodId),
          ),
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.income,
            content: Text('Transaction duplicated'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Error duplicating: $e'),
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text('Are you sure you want to delete this transaction? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close sheet
              await ref.read(databaseProvider).deleteTransactionById(transaction.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool isDark;

  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
        const SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
