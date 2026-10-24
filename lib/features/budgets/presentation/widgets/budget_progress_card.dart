import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/budget_models.dart';
import 'set_budget_dialog.dart';

class BudgetProgressCard extends StatelessWidget {
  final BudgetProgress progress;
  final bool isHero;

  const BudgetProgressCard({
    super.key,
    required this.progress,
    this.isHero = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (progress.status) {
      case BudgetStatus.safe:
        statusColor = AppColors.incomeGreen;
        statusLabel = 'On Track';
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case BudgetStatus.warning:
        statusColor = AppColors.accentWarning;
        statusLabel = 'Warning';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case BudgetStatus.overBudget:
        statusColor = AppColors.expenseRed;
        statusLabel = 'Over Budget';
        statusIcon = Icons.error_outline_rounded;
        break;
    }

    final categoryColor = progress.category != null
        ? Color(progress.category!.color ?? 0xFF0D9488)
        : AppColors.primary;

    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isHero ? 10 : 6,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isHero ? 24 : 18),
        side: BorderSide(
          color: progress.isOverBudget
              ? AppColors.expenseRed.withOpacity(0.4)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: progress.isOverBudget ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(isHero ? 24 : 18),
        onTap: () {
          SetBudgetDialog.show(
            context,
            catId: progress.category?.id,
            categoryName: progress.name,
            currentLimitPaise: progress.limitPaise,
          );
        },
        child: Container(
          padding: EdgeInsets.all(isHero ? 20 : 16),
          decoration: isHero
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xFF1E293B),
                            const Color(0xFF0F172A),
                          ]
                        : [
                            Colors.white,
                            const Color(0xFFF8FAFC),
                          ],
                  ),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: isHero ? 42 : 36,
                    height: isHero ? 42 : 36,
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      progress.category == null
                          ? Icons.savings_rounded
                          : Icons.category_rounded,
                      color: categoryColor,
                      size: isHero ? 22 : 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progress.name,
                          style: TextStyle(
                            fontSize: isHero ? 16 : 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          progress.isOverBudget
                              ? '${CurrencyFormatter.formatPaiseAbsolute(progress.remainingPaise.abs())} exceeded'
                              : '${CurrencyFormatter.formatPaiseAbsolute(progress.remainingPaise)} left (${progress.daysRemainingInMonth}d left)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: progress.isOverBudget
                                ? AppColors.expenseRed
                                : (isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Percentage badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          '$statusLabel · ${progress.percentage.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Linear Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (progress.percentage / 100.0).clamp(0.0, 1.0),
                  backgroundColor: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  minHeight: isHero ? 8 : 6,
                ),
              ),
              const SizedBox(height: 12),
              // Footnote: Spent vs Total + Daily budget remaining
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Spent: ${CurrencyFormatter.formatPaiseAbsolute(progress.spentPaise)} of ${CurrencyFormatter.formatPaiseAbsolute(progress.limitPaise)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (!progress.isOverBudget && progress.dailyBudgetRemainingPaise > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '₹${(progress.dailyBudgetRemainingPaise / 100).toStringAsFixed(0)}/day',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
