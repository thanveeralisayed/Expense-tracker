import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/features/budgets/domain/budget_models.dart';
import 'package:expense_tracker/features/budgets/domain/budget_service.dart';

Transaction _createExpense({
  required int id,
  required int amount,
  required DateTime date,
  int? catId,
  int? transferAccount,
  int? transferPeer,
  int? parentId,
}) {
  return Transaction(
    id: id,
    accountId: 1,
    amount: amount,
    date: date,
    valueDate: date,
    catId: catId,
    transferAccount: transferAccount,
    transferPeer: transferPeer,
    parentId: parentId,
    status: 0,
    crStatus: 'UNRECONCILED',
  );
}

void main() {
  group('BudgetService - Settings Parsing & Date Edge Cases', () {
    test('parseBudgetLimits parses overall and category limits and ignores invalid values', () {
      final settings = [
        const AppSetting(key: 'budget_overall_paise', value: '5000000'), // ₹50,000
        const AppSetting(key: 'budget_cat_1', value: '1500000'), // ₹15,000 for cat 1
        const AppSetting(key: 'budget_cat_2', value: 'invalid'), // Should be ignored
        const AppSetting(key: 'budget_cat_3', value: '0'), // 0 should be ignored
        const AppSetting(key: 'unrelated_key', value: 'some_value'),
      ];

      final limits = BudgetService.parseBudgetLimits(settings);

      expect(limits.overallLimitPaise, equals(5000000));
      expect(limits.categoryLimitsPaise.length, equals(1));
      expect(limits.categoryLimitsPaise[1], equals(1500000));
      expect(limits.categoryLimitsPaise.containsKey(2), isFalse);
      expect(limits.categoryLimitsPaise.containsKey(3), isFalse);
    });

    test('calculateDaysRemaining calculates correctly and is at least 1', () {
      // Oct 24 in a 31-day month: 31 - 24 + 1 = 8 days left
      final days1 = BudgetService.calculateDaysRemaining(referenceNow: DateTime(2026, 10, 24));
      expect(days1, equals(8));

      // Oct 31 (last day): 31 - 31 + 1 = 1 day left
      final days2 = BudgetService.calculateDaysRemaining(referenceNow: DateTime(2026, 10, 31));
      expect(days2, equals(1));

      // Feb 28 in a non-leap year (2025): 28 - 28 + 1 = 1 day left
      final days3 = BudgetService.calculateDaysRemaining(referenceNow: DateTime(2025, 2, 28));
      expect(days3, equals(1));
    });

    test('filterCurrentMonthExpenses excludes income, transfers, split children, and other months', () {
      final refDate = DateTime(2026, 10, 24);
      final txs = [
        _createExpense(id: 1, amount: -1000, date: DateTime(2026, 10, 5)), // Valid
        _createExpense(id: 2, amount: 5000, date: DateTime(2026, 10, 6)), // Income (excluded)
        _createExpense(id: 3, amount: -2000, date: DateTime(2026, 9, 30)), // Prior month (excluded)
        _createExpense(id: 4, amount: -3000, date: DateTime(2026, 11, 1)), // Next month (excluded)
        _createExpense(id: 5, amount: -500, date: DateTime(2026, 10, 10), transferAccount: 2), // Transfer (excluded)
        _createExpense(id: 6, amount: -200, date: DateTime(2026, 10, 12), parentId: 1), // Split child (excluded)
      ];

      final filtered = BudgetService.filterCurrentMonthExpenses(txs, referenceNow: refDate);

      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals(1));
    });
  });

  group('BudgetService - Overall Budget Status & Calculations', () {
    final refDate = DateTime(2026, 10, 24); // 8 days remaining

    test('Zero spent: safe status, 0% progress, full remaining, positive daily budget', () {
      final progress = BudgetService.calculateOverallBudget(
        limitPaise: 800000, // ₹8,000
        currentMonthExpenses: [],
        referenceNow: refDate,
      );

      expect(progress.spentPaise, equals(0));
      expect(progress.remainingPaise, equals(800000));
      expect(progress.percentage, equals(0.0));
      expect(progress.status, equals(BudgetStatus.safe));
      expect(progress.isSafe, isTrue);
      expect(progress.dailyBudgetRemainingPaise, equals(100000)); // ₹8,000 / 8 days = ₹1,000/day
    });

    test('75% threshold transitions status to warning', () {
      final txs = [
        _createExpense(id: 1, amount: -750000, date: DateTime(2026, 10, 5)), // ₹7,500
      ];

      final progress = BudgetService.calculateOverallBudget(
        limitPaise: 1000000, // ₹10,000
        currentMonthExpenses: txs,
        referenceNow: refDate,
      );

      expect(progress.percentage, equals(75.0));
      expect(progress.status, equals(BudgetStatus.warning));
      expect(progress.isWarning, isTrue);
      expect(progress.remainingPaise, equals(250000));
    });

    test('Exceeding budget transitions status to overBudget with negative remaining and 0 daily budget', () {
      final txs = [
        _createExpense(id: 1, amount: -1200000, date: DateTime(2026, 10, 5)), // ₹12,000 spent
      ];

      final progress = BudgetService.calculateOverallBudget(
        limitPaise: 1000000, // ₹10,000 limit
        currentMonthExpenses: txs,
        referenceNow: refDate,
      );

      expect(progress.percentage, equals(120.0));
      expect(progress.status, equals(BudgetStatus.overBudget));
      expect(progress.isOverBudget, isTrue);
      expect(progress.remainingPaise, equals(-200000));
      expect(progress.dailyBudgetRemainingPaise, equals(0));
    });

    test('Zero budget limit edge cases handled without NaN or crash', () {
      final progressZeroSpent = BudgetService.calculateOverallBudget(
        limitPaise: 0,
        currentMonthExpenses: [],
        referenceNow: refDate,
      );
      expect(progressZeroSpent.percentage, equals(0.0));
      expect(progressZeroSpent.status, equals(BudgetStatus.safe));

      final progressWithSpent = BudgetService.calculateOverallBudget(
        limitPaise: 0,
        currentMonthExpenses: [
          _createExpense(id: 1, amount: -5000, date: DateTime(2026, 10, 5)),
        ],
        referenceNow: refDate,
      );
      expect(progressWithSpent.percentage, equals(100.0));
      expect(progressWithSpent.status, equals(BudgetStatus.overBudget));
    });
  });

  group('BudgetService - Category Budget Progress', () {
    final refDate = DateTime(2026, 10, 24);
    final catFood = const Category(id: 10, label: 'Groceries', type: 0, color: 0xFF10B981, icon: 'shopping_cart');
    final catMap = {10: catFood};

    test('Category budget only accumulates expenses for matching catId', () {
      final txs = [
        _createExpense(id: 1, amount: -300000, date: DateTime(2026, 10, 5), catId: 10), // ₹3,000
        _createExpense(id: 2, amount: -200000, date: DateTime(2026, 10, 6), catId: 99), // Other cat
      ];

      final progress = BudgetService.calculateCategoryBudget(
        catId: 10,
        limitPaise: 500000, // ₹5,000
        currentMonthExpenses: txs,
        categoryMap: catMap,
        referenceNow: refDate,
      );

      expect(progress.spentPaise, equals(300000));
      expect(progress.remainingPaise, equals(200000));
      expect(progress.percentage, equals(60.0));
      expect(progress.status, equals(BudgetStatus.safe));
      expect(progress.name, equals('Groceries'));
      expect(progress.category?.id, equals(10));
    });
  });
}
