import '../../../core/database/database.dart';
import 'budget_models.dart';

class BudgetService {
  static const String overallBudgetKey = 'budget_overall_paise';
  static const String categoryBudgetPrefix = 'budget_cat_';

  /// Calculate days remaining in the current month, including today (min 1)
  static int calculateDaysRemaining({DateTime? referenceNow}) {
    final now = referenceNow ?? DateTime.now();
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0).day;
    final remaining = lastDayOfMonth - now.day + 1;
    return remaining < 1 ? 1 : remaining;
  }

  /// Extracts overall budget limit and category limits from AppSettings
  static ({int? overallLimitPaise, Map<int, int> categoryLimitsPaise}) parseBudgetLimits(
    List<AppSetting> settings,
  ) {
    int? overall;
    final catLimits = <int, int>{};

    for (final setting in settings) {
      final val = setting.value;
      if (val == null) continue;

      if (setting.key == overallBudgetKey) {
        overall = int.tryParse(val);
      } else if (setting.key.startsWith(categoryBudgetPrefix)) {
        final catIdStr = setting.key.substring(categoryBudgetPrefix.length);
        final catId = int.tryParse(catIdStr);
        final limit = int.tryParse(val);
        if (catId != null && limit != null && limit > 0) {
          catLimits[catId] = limit;
        }
      }
    }

    return (overallLimitPaise: overall, categoryLimitsPaise: catLimits);
  }

  /// Filter transactions for current month expenses (excluding transfers & split children)
  static List<Transaction> filterCurrentMonthExpenses(
    List<Transaction> transactions, {
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth = DateTime(now.year, now.month + 1, 1);

    return transactions.where((t) {
      if (t.parentId != null) return false;
      final isTransfer = t.transferAccount != null || t.transferPeer != null;
      if (isTransfer) return false;
      if (t.amount >= 0) return false; // expenses only
      if (t.date.isBefore(startOfMonth) || !t.date.isBefore(startOfNextMonth)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Calculate overall monthly budget progress
  static BudgetProgress calculateOverallBudget({
    required int limitPaise,
    required List<Transaction> currentMonthExpenses,
    DateTime? referenceNow,
  }) {
    int totalSpent = 0;
    for (final tx in currentMonthExpenses) {
      totalSpent += -tx.amount;
    }

    final daysRemaining = calculateDaysRemaining(referenceNow: referenceNow);
    final remainingPaise = limitPaise - totalSpent;
    final double percentage = limitPaise > 0
        ? (totalSpent / limitPaise) * 100.0
        : (totalSpent > 0 ? 100.0 : 0.0);

    BudgetStatus status;
    if (remainingPaise < 0 || (limitPaise == 0 && totalSpent > 0)) {
      status = BudgetStatus.overBudget;
    } else if (percentage >= 75.0) {
      status = BudgetStatus.warning;
    } else {
      status = BudgetStatus.safe;
    }

    final dailyBudget = (remainingPaise > 0 && daysRemaining > 0)
        ? (remainingPaise ~/ daysRemaining)
        : 0;

    return BudgetProgress(
      key: overallBudgetKey,
      name: 'Total Monthly Budget',
      category: null,
      limitPaise: limitPaise,
      spentPaise: totalSpent,
      remainingPaise: remainingPaise,
      percentage: percentage,
      status: status,
      daysRemainingInMonth: daysRemaining,
      dailyBudgetRemainingPaise: dailyBudget,
    );
  }

  /// Calculate budget progress for a specific category
  static BudgetProgress calculateCategoryBudget({
    required int catId,
    required int limitPaise,
    required List<Transaction> currentMonthExpenses,
    required Map<int, Category> categoryMap,
    DateTime? referenceNow,
  }) {
    int spent = 0;
    for (final tx in currentMonthExpenses) {
      if (tx.catId == catId) {
        spent += -tx.amount;
      }
    }

    final daysRemaining = calculateDaysRemaining(referenceNow: referenceNow);
    final remainingPaise = limitPaise - spent;
    final double percentage = limitPaise > 0
        ? (spent / limitPaise) * 100.0
        : (spent > 0 ? 100.0 : 0.0);

    BudgetStatus status;
    if (remainingPaise < 0 || (limitPaise == 0 && spent > 0)) {
      status = BudgetStatus.overBudget;
    } else if (percentage >= 75.0) {
      status = BudgetStatus.warning;
    } else {
      status = BudgetStatus.safe;
    }

    final dailyBudget = (remainingPaise > 0 && daysRemaining > 0)
        ? (remainingPaise ~/ daysRemaining)
        : 0;

    final cat = categoryMap[catId] ??
        Category(
          id: catId,
          label: 'Category #$catId',
          type: 0,
          color: 0xFF64748B,
          icon: 'category',
        );

    return BudgetProgress(
      key: '$categoryBudgetPrefix$catId',
      name: cat.label,
      category: cat,
      limitPaise: limitPaise,
      spentPaise: spent,
      remainingPaise: remainingPaise,
      percentage: percentage,
      status: status,
      daysRemainingInMonth: daysRemaining,
      dailyBudgetRemainingPaise: dailyBudget,
    );
  }
}
