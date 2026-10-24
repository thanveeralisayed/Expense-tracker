import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';

class TransactionListTile extends StatelessWidget {
  final Transaction transaction;
  final Account? account;
  final VoidCallback? onTap;

  const TransactionListTile({
    super.key,
    required this.transaction,
    this.account,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpense = transaction.amount < 0;
    final isTransfer = transaction.transferAccount != null || transaction.transferPeer != null;

    final Color statusColor = isTransfer
        ? AppColors.transfer
        : (isExpense ? AppColors.expense : AppColors.income);

    final IconData statusIcon = isTransfer
        ? Icons.swap_horiz_rounded
        : (isExpense ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);

    final dateStr = DateFormat('dd MMM, hh:mm a').format(transaction.date);
    final comment = (transaction.comment != null && transaction.comment!.trim().isNotEmpty)
        ? transaction.comment!.trim()
        : (isTransfer ? 'Transfer' : (isExpense ? 'Expense' : 'Income'));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(statusIcon, color: statusColor, size: 20),
            ),
            const SizedBox(width: 14),

            // Comment & Account tag
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (account != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            account!.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Amount
            Text(
              CurrencyFormatter.formatPaise(transaction.amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
