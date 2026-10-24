import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/analytics_service.dart';

class CashFlowSummaryCard extends StatelessWidget {
  final CashFlowSummary cashFlow;

  const CashFlowSummaryCard({
    super.key,
    required this.cashFlow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNetPositive = cashFlow.netSavingsPaise >= 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
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
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cash Flow & Savings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (cashFlow.savingsRate >= 20
                            ? AppColors.incomeGreen
                            : (cashFlow.savingsRate > 0
                                ? AppColors.accentWarning
                                : AppColors.expenseRed))
                        .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cashFlow.savingsRate >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 14,
                        color: cashFlow.savingsRate >= 20
                            ? AppColors.incomeGreen
                            : (cashFlow.savingsRate > 0
                                ? AppColors.accentWarning
                                : AppColors.expenseRed),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${cashFlow.savingsRate.toStringAsFixed(1)}% Saved',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cashFlow.savingsRate >= 20
                              ? AppColors.incomeGreen
                              : (cashFlow.savingsRate > 0
                                  ? AppColors.accentWarning
                                  : AppColors.expenseRed),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Inflow & Outflow columns
            Row(
              children: [
                Expanded(
                  child: _buildMetricItem(
                    context,
                    label: 'Total Inflow',
                    amountPaise: cashFlow.totalInflowPaise,
                    color: AppColors.incomeGreen,
                    icon: Icons.south_west_rounded,
                  ),
                ),
                Container(
                  height: 48,
                  width: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  child: _buildMetricItem(
                    context,
                    label: 'Total Outflow',
                    amountPaise: cashFlow.totalOutflowPaise,
                    color: AppColors.expenseRed,
                    icon: Icons.north_east_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              height: 1,
            ),
            const SizedBox(height: 16),
            // Net savings row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Net Surplus',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${isNetPositive ? '+' : '-'}${CurrencyFormatter.formatPaiseAbsolute(cashFlow.netSavingsPaise)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isNetPositive ? AppColors.incomeGreen : AppColors.expenseRed,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Visual savings rate progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (cashFlow.savingsRate > 0)
                    ? (cashFlow.savingsRate.clamp(0.0, 100.0) / 100.0)
                    : 0.0,
                backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(
                  cashFlow.savingsRate >= 20
                      ? AppColors.incomeGreen
                      : (cashFlow.savingsRate > 0
                          ? AppColors.accentWarning
                          : AppColors.expenseRed),
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(
    BuildContext context, {
    required String label,
    required int amountPaise,
    required Color color,
    required IconData icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            CurrencyFormatter.formatPaiseAbsolute(amountPaise),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
