import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/analytics_service.dart';

class MonthlyTrendBarChart extends StatelessWidget {
  final List<MonthlyTrend> trends;

  const MonthlyTrendBarChart({
    super.key,
    required this.trends,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (trends.isEmpty) {
      return const SizedBox.shrink();
    }

    // Determine max value for Y-axis scaling
    double maxRupees = 1000.0;
    for (final t in trends) {
      final inc = t.totalIncomePaise / 100.0;
      final exp = t.totalExpensePaise / 100.0;
      maxRupees = max(maxRupees, max(inc, exp));
    }
    // Add 20% headroom
    final maxY = (maxRupees * 1.2).ceilToDouble();

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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '6-Month Cash Flow Trend',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                ),
                // Legend
                Row(
                  children: [
                    _buildLegendItem(AppColors.incomeGreen, 'Inflow'),
                    const SizedBox(width: 12),
                    _buildLegendItem(AppColors.expenseRed, 'Outflow'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) =>
                          isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final trend = trends[groupIndex];
                        final isIncome = rodIndex == 0;
                        final label = isIncome ? 'Inflow' : 'Outflow';
                        final paise = isIncome
                            ? trend.totalIncomePaise
                            : trend.totalExpensePaise;
                        return BarTooltipItem(
                          '${trend.shortMonth}\n$label: ${CurrencyFormatter.formatPaiseAbsolute(paise)}',
                          TextStyle(
                            color: isIncome ? AppColors.incomeGreen : const Color(0xFFF87171),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          if (value == 0 || value == maxY) {
                            return const SizedBox.shrink();
                          }
                          String text;
                          if (value >= 100000) {
                            text = '₹${(value / 100000).toStringAsFixed(1)}L';
                          } else if (value >= 1000) {
                            text = '₹${(value / 1000).toStringAsFixed(0)}k';
                          } else {
                            text = '₹${value.toInt()}';
                          }
                          return Text(
                            text,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= trends.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              trends[index].shortMonth,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 3,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(trends.length, (i) {
                    final t = trends[i];
                    final incRupees = t.totalIncomePaise / 100.0;
                    final expRupees = t.totalExpensePaise / 100.0;

                    return BarChartGroupData(
                      x: i,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(
                          toY: incRupees,
                          color: AppColors.incomeGreen,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                        BarChartRodData(
                          toY: expRupees,
                          color: AppColors.expenseRed,
                          width: 10,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
