import 'package:intl/intl.dart';
import '../../../core/database/database.dart';

enum AnalyticsTimeframe {
  thisMonth,
  last30Days,
  thisYear,
  allTime,
}

class CategorySpending {
  final Category category;
  final int totalPaise;
  final double percentage;
  final int transactionCount;

  CategorySpending({
    required this.category,
    required this.totalPaise,
    required this.percentage,
    required this.transactionCount,
  });
}

class MonthlyTrend {
  final String monthKey;
  final String shortMonth;
  final DateTime date;
  final int totalIncomePaise;
  final int totalExpensePaise;
  final int netSavingsPaise;

  MonthlyTrend({
    required this.monthKey,
    required this.shortMonth,
    required this.date,
    required this.totalIncomePaise,
    required this.totalExpensePaise,
    required this.netSavingsPaise,
  });
}

class CashFlowSummary {
  final int totalInflowPaise;
  final int totalOutflowPaise;
  final int netSavingsPaise;
  final double savingsRate; // Percentage e.g. 25.5%

  CashFlowSummary({
    required this.totalInflowPaise,
    required this.totalOutflowPaise,
    required this.netSavingsPaise,
    required this.savingsRate,
  });
}

class AnalyticsService {
  /// Filter transactions according to selected timeframe (excluding transfer peers and parent split duplicates)
  static List<Transaction> filterTransactions(
    List<Transaction> transactions,
    AnalyticsTimeframe timeframe, {
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    DateTime? startDate;

    switch (timeframe) {
      case AnalyticsTimeframe.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case AnalyticsTimeframe.last30Days:
        startDate = now.subtract(const Duration(days: 30));
        break;
      case AnalyticsTimeframe.thisYear:
        startDate = DateTime(now.year, 1, 1);
        break;
      case AnalyticsTimeframe.allTime:
        startDate = null;
        break;
    }

    return transactions.where((t) {
      // Exclude split children (if queried with all txs) or transfer destination duplicates if needed
      // If parentId is not null, it's a split child; parent has total amount
      if (t.parentId != null) return false;
      if (startDate != null && t.date.isBefore(startDate)) return false;
      return true;
    }).toList();
  }

  /// Calculate category-wise spending breakdown
  static List<CategorySpending> calculateCategorySpending({
    required List<Transaction> transactions,
    required Map<int, Category> categoriesMap,
  }) {
    // Only consider expenses (amount < 0) and not transfers
    final expenseTxs = transactions.where((t) {
      final isTransfer = t.transferAccount != null || t.transferPeer != null;
      return t.amount < 0 && !isTransfer;
    }).toList();

    if (expenseTxs.isEmpty) return [];

    final categoryTotals = <int, int>{};
    final categoryCounts = <int, int>{};
    int grandTotalPaise = 0;

    for (final tx in expenseTxs) {
      final catId = tx.catId ?? -1; // -1 for Uncategorized
      final amt = -tx.amount; // convert to positive
      categoryTotals[catId] = (categoryTotals[catId] ?? 0) + amt;
      categoryCounts[catId] = (categoryCounts[catId] ?? 0) + 1;
      grandTotalPaise += amt;
    }

    final result = <CategorySpending>[];
    for (final entry in categoryTotals.entries) {
      final catId = entry.key;
      final total = entry.value;
      final count = categoryCounts[catId] ?? 0;
      final pct = grandTotalPaise > 0 ? (total / grandTotalPaise) * 100.0 : 0.0;

      final category = catId == -1
          ? const Category(
              id: -1,
              label: 'Uncategorized',
              type: 0,
              color: 0xFF64748B,
              icon: 'help_outline',
            )
          : categoriesMap[catId] ??
              Category(
                id: catId,
                label: 'Category #$catId',
                type: 0,
                color: 0xFF64748B,
                icon: 'category',
              );

      result.add(
        CategorySpending(
          category: category,
          totalPaise: total,
          percentage: pct,
          transactionCount: count,
        ),
      );
    }

    // Sort descending by total spent
    result.sort((a, b) => b.totalPaise.compareTo(a.totalPaise));
    return result;
  }

  /// Calculate monthly inflow, outflow, and net savings trends
  static List<MonthlyTrend> calculateMonthlyTrends({
    required List<Transaction> transactions,
    int monthsCount = 6,
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final months = <MonthlyTrend>[];

    // Generate month slots in chronological order
    for (int i = monthsCount - 1; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MMMM yyyy').format(d);
      final shortMonth = DateFormat('MMM').format(d);

      // Find transactions in this calendar month
      final monthStart = DateTime(d.year, d.month, 1);
      final monthEnd = DateTime(d.year, d.month + 1, 0, 23, 59, 59);

      int inflow = 0;
      int outflow = 0;

      for (final tx in transactions) {
        if (tx.parentId != null) continue;
        final isTransfer = tx.transferAccount != null || tx.transferPeer != null;
        if (isTransfer) continue;

        if (tx.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) &&
            tx.date.isBefore(monthEnd.add(const Duration(seconds: 1)))) {
          if (tx.amount < 0) {
            outflow += -tx.amount;
          } else {
            inflow += tx.amount;
          }
        }
      }

      months.add(
        MonthlyTrend(
          monthKey: monthKey,
          shortMonth: shortMonth,
          date: d,
          totalIncomePaise: inflow,
          totalExpensePaise: outflow,
          netSavingsPaise: inflow - outflow,
        ),
      );
    }

    return months;
  }

  /// Calculate cash flow statement
  static CashFlowSummary calculateCashFlow(List<Transaction> transactions) {
    int inflow = 0;
    int outflow = 0;

    for (final tx in transactions) {
      if (tx.parentId != null) continue;
      final isTransfer = tx.transferAccount != null || tx.transferPeer != null;
      if (isTransfer) continue;

      if (tx.amount < 0) {
        outflow += -tx.amount;
      } else {
        inflow += tx.amount;
      }
    }

    final net = inflow - outflow;
    final rate = inflow > 0 ? ((net / inflow) * 100.0).clamp(-100.0, 100.0) : (outflow > 0 ? -100.0 : 0.0);

    return CashFlowSummary(
      totalInflowPaise: inflow,
      totalOutflowPaise: outflow,
      netSavingsPaise: net,
      savingsRate: rate,
    );
  }
}
