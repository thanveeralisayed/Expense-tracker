import '../../../core/database/database.dart';

enum BudgetStatus {
  safe, // <= 75%
  warning, // > 75% and <= 100%
  overBudget, // > 100%
}

class BudgetProgress {
  final String key;
  final String name;
  final Category? category;
  final int limitPaise;
  final int spentPaise;
  final int remainingPaise;
  final double percentage; // e.g. 75.0%
  final BudgetStatus status;
  final int daysRemainingInMonth;
  final int dailyBudgetRemainingPaise;

  const BudgetProgress({
    required this.key,
    required this.name,
    this.category,
    required this.limitPaise,
    required this.spentPaise,
    required this.remainingPaise,
    required this.percentage,
    required this.status,
    required this.daysRemainingInMonth,
    required this.dailyBudgetRemainingPaise,
  });

  bool get isOverBudget => status == BudgetStatus.overBudget;
  bool get isWarning => status == BudgetStatus.warning;
  bool get isSafe => status == BudgetStatus.safe;
}
