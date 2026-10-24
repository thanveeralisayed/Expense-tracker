import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/analytics_service.dart';
import 'widgets/cash_flow_summary_card.dart';
import 'widgets/category_donut_chart.dart';
import 'widgets/monthly_trend_bar_chart.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedTimeframe = ref.watch(analyticsTimeframeProvider);
    final transactionsAsync = ref.watch(allTransactionsStreamProvider);
    final categoryMap = ref.watch(categoryMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Financial Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: transactionsAsync.when(
        data: (allTransactions) {
          final filteredTxs = AnalyticsService.filterTransactions(
            allTransactions,
            selectedTimeframe,
          );

          final cashFlow = AnalyticsService.calculateCashFlow(filteredTxs);
          final categoryBreakdown = AnalyticsService.calculateCategorySpending(
            transactions: filteredTxs,
            categoriesMap: categoryMap,
          );
          final monthlyTrends = AnalyticsService.calculateMonthlyTrends(
            transactions: allTransactions,
            monthsCount: 6,
          );

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Timeframe Selector Chips
                _buildTimeframeSelector(context, ref, selectedTimeframe, isDark),
                const SizedBox(height: 8),
                // Cash Flow & Savings Summary
                CashFlowSummaryCard(cashFlow: cashFlow),
                // Category Spending Donut Chart
                CategoryDonutChart(
                  categories: categoryBreakdown,
                  totalExpensePaise: cashFlow.totalOutflowPaise,
                ),
                // 6-Month Inflow/Outflow Trend Bar Chart
                MonthlyTrendBarChart(trends: monthlyTrends),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (err, stack) => Center(
          child: Text('Error loading analytics: $err'),
        ),
      ),
    );
  }

  Widget _buildTimeframeSelector(
    BuildContext context,
    WidgetRef ref,
    AnalyticsTimeframe current,
    bool isDark,
  ) {
    final options = [
      (AnalyticsTimeframe.thisMonth, 'This Month'),
      (AnalyticsTimeframe.last30Days, '30 Days'),
      (AnalyticsTimeframe.thisYear, 'This Year'),
      (AnalyticsTimeframe.allTime, 'All Time'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: options.map((opt) {
          final isSelected = opt.$1 == current;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(opt.$2),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  ref.read(analyticsTimeframeProvider.notifier).state = opt.$1;
                }
              },
              selectedColor: AppColors.primary,
              backgroundColor: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
              ),
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
