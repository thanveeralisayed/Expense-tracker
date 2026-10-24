import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/features/analytics/domain/analytics_service.dart';

Transaction _createTx({
  required int id,
  required int accountId,
  required int amount,
  required DateTime date,
  int? catId,
  int? transferAccount,
  int? transferPeer,
  int? parentId,
  String? comment,
}) {
  return Transaction(
    id: id,
    accountId: accountId,
    amount: amount,
    date: date,
    valueDate: date,
    catId: catId,
    transferAccount: transferAccount,
    transferPeer: transferPeer,
    parentId: parentId,
    comment: comment,
    status: 0,
    crStatus: 'UNRECONCILED',
  );
}

void main() {
  group('AnalyticsService - Cash Flow Edge Cases', () {
    test('Empty transaction list returns zero values and zero savings rate without division by zero', () {
      final summary = AnalyticsService.calculateCashFlow([]);

      expect(summary.totalInflowPaise, equals(0));
      expect(summary.totalOutflowPaise, equals(0));
      expect(summary.netSavingsPaise, equals(0));
      expect(summary.savingsRate, equals(0.0));
      expect(summary.savingsRate.isNaN, isFalse);
    });

    test('100% expense with zero income returns -100% savings rate', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: -50000, date: DateTime(2026, 10, 10)),
      ];

      final summary = AnalyticsService.calculateCashFlow(txs);

      expect(summary.totalInflowPaise, equals(0));
      expect(summary.totalOutflowPaise, equals(50000));
      expect(summary.netSavingsPaise, equals(-50000));
      expect(summary.savingsRate, equals(-100.0));
    });

    test('100% income with zero expense returns 100% savings rate', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: 100000, date: DateTime(2026, 10, 10)),
      ];

      final summary = AnalyticsService.calculateCashFlow(txs);

      expect(summary.totalInflowPaise, equals(100000));
      expect(summary.totalOutflowPaise, equals(0));
      expect(summary.netSavingsPaise, equals(100000));
      expect(summary.savingsRate, equals(100.0));
    });

    test('Mixed inflow and outflow calculates net and savings rate correctly', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: 100000, date: DateTime(2026, 10, 1)), // ₹1000 in
        _createTx(id: 2, accountId: 1, amount: -25000, date: DateTime(2026, 10, 5)), // ₹250 out
      ];

      final summary = AnalyticsService.calculateCashFlow(txs);

      expect(summary.totalInflowPaise, equals(100000));
      expect(summary.totalOutflowPaise, equals(25000));
      expect(summary.netSavingsPaise, equals(75000));
      expect(summary.savingsRate, closeTo(75.0, 0.01));
    });

    test('Transfers and split children are excluded from cash flow calculations', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: 50000, date: DateTime(2026, 10, 1)),
        _createTx(id: 2, accountId: 1, amount: -10000, date: DateTime(2026, 10, 2)),
        // Transfer out
        _createTx(id: 3, accountId: 1, amount: -20000, date: DateTime(2026, 10, 3), transferAccount: 2),
        // Transfer in peer
        _createTx(id: 4, accountId: 2, amount: 20000, date: DateTime(2026, 10, 3), transferPeer: 3),
        // Split child (parent tx already has the full amount)
        _createTx(id: 5, accountId: 1, amount: -5000, date: DateTime(2026, 10, 4), parentId: 2),
      ];

      final summary = AnalyticsService.calculateCashFlow(txs);

      // Only tx 1 (50000) and tx 2 (-10000) should count
      expect(summary.totalInflowPaise, equals(50000));
      expect(summary.totalOutflowPaise, equals(10000));
      expect(summary.netSavingsPaise, equals(40000));
      expect(summary.savingsRate, closeTo(80.0, 0.01));
    });
  });

  group('AnalyticsService - Category Spending Edge Cases', () {
    final catFood = const Category(id: 1, label: 'Food', type: 0, color: 0xFFEF4444, icon: 'restaurant');
    final catRent = const Category(id: 2, label: 'Rent', type: 0, color: 0xFF3B82F6, icon: 'home');
    final categoryMap = {1: catFood, 2: catRent};

    test('Empty transactions returns empty category spending list', () {
      final result = AnalyticsService.calculateCategorySpending(
        transactions: [],
        categoriesMap: categoryMap,
      );
      expect(result, isEmpty);
    });

    test('Only income transactions returns empty category spending list', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: 50000, date: DateTime(2026, 10, 1)),
      ];
      final result = AnalyticsService.calculateCategorySpending(
        transactions: txs,
        categoriesMap: categoryMap,
      );
      expect(result, isEmpty);
    });

    test('100% single category allocation has exact 100.0% percentage', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: -15000, date: DateTime(2026, 10, 1), catId: 1),
        _createTx(id: 2, accountId: 1, amount: -25000, date: DateTime(2026, 10, 2), catId: 1),
      ];
      final result = AnalyticsService.calculateCategorySpending(
        transactions: txs,
        categoriesMap: categoryMap,
      );

      expect(result.length, equals(1));
      expect(result.first.category.label, equals('Food'));
      expect(result.first.totalPaise, equals(40000));
      expect(result.first.percentage, equals(100.0));
      expect(result.first.transactionCount, equals(2));
    });

    test('Uncategorized spending (catId == null) is grouped under Uncategorized', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: -30000, date: DateTime(2026, 10, 1), catId: null),
        _createTx(id: 2, accountId: 1, amount: -70000, date: DateTime(2026, 10, 2), catId: 1),
      ];
      final result = AnalyticsService.calculateCategorySpending(
        transactions: txs,
        categoriesMap: categoryMap,
      );

      expect(result.length, equals(2));
      // First is Food (70%)
      expect(result[0].category.label, equals('Food'));
      expect(result[0].percentage, equals(70.0));
      // Second is Uncategorized (30%)
      expect(result[1].category.label, equals('Uncategorized'));
      expect(result[1].totalPaise, equals(30000));
      expect(result[1].percentage, equals(30.0));
    });

    test('Categories sorted descending by total expenditure', () {
      final txs = [
        _createTx(id: 1, accountId: 1, amount: -2000, date: DateTime(2026, 10, 1), catId: 1),
        _createTx(id: 2, accountId: 1, amount: -8000, date: DateTime(2026, 10, 2), catId: 2),
      ];
      final result = AnalyticsService.calculateCategorySpending(
        transactions: txs,
        categoriesMap: categoryMap,
      );

      expect(result.first.category.label, equals('Rent'));
      expect(result.first.totalPaise, equals(8000));
      expect(result.last.category.label, equals('Food'));
      expect(result.last.totalPaise, equals(2000));
    });
  });

  group('AnalyticsService - Monthly Trends & Timeframe Filtering', () {
    test('calculateMonthlyTrends returns specified number of months in chronological order', () {
      final refDate = DateTime(2026, 10, 24);
      final trends = AnalyticsService.calculateMonthlyTrends(
        transactions: [],
        monthsCount: 6,
        referenceNow: refDate,
      );

      expect(trends.length, equals(6));
      expect(trends.last.shortMonth, equals('Oct'));
      expect(trends.first.shortMonth, equals('May'));
      for (final t in trends) {
        expect(t.totalIncomePaise, equals(0));
        expect(t.totalExpensePaise, equals(0));
        expect(t.netSavingsPaise, equals(0));
      }
    });

    test('filterTransactions applies thisMonth boundary correctly', () {
      final refDate = DateTime(2026, 10, 24);
      final txs = [
        _createTx(id: 1, accountId: 1, amount: -100, date: DateTime(2026, 9, 30)), // past month
        _createTx(id: 2, accountId: 1, amount: -200, date: DateTime(2026, 10, 1)), // this month
        _createTx(id: 3, accountId: 1, amount: -300, date: DateTime(2026, 10, 24)), // this month
      ];

      final filtered = AnalyticsService.filterTransactions(
        txs,
        AnalyticsTimeframe.thisMonth,
        referenceNow: refDate,
      );

      expect(filtered.length, equals(2));
      expect(filtered.map((t) => t.id), containsAll([2, 3]));
      expect(filtered.map((t) => t.id), isNot(contains(1)));
    });
  });
}
