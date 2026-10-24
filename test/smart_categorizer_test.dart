import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/features/categories/domain/smart_categorizer_engine.dart';

void main() {
  group('SmartCategorizerEngine Unit & Edge Case Tests', () {
    final List<Category> sampleCategories = [
      const Category(id: 1, label: 'Groceries', type: 0, color: 0xFF10B981, icon: 'shopping_cart'),
      const Category(id: 2, label: 'Food & Dining', type: 0, color: 0xFFF59E0B, icon: 'restaurant'),
      const Category(id: 3, label: 'Fuel & Transport', type: 0, color: 0xFFEF4444, icon: 'local_gas_station'),
      const Category(id: 4, label: 'Home & Capital', type: 0, color: 0xFF8B5CF6, icon: 'home_repair_service'),
      const Category(id: 5, label: 'Health & Medical', type: 0, color: 0xFFEC4899, icon: 'medical_services'),
      const Category(id: 6, label: 'Utilities & Bills', type: 0, color: 0xFF3B82F6, icon: 'bolt'),
      const Category(id: 7, label: 'Salary', type: 1, color: 0xFF10B981, icon: 'payments'),
    ];

    test('Direct category label match', () {
      final match = SmartCategorizerEngine.matchCategory('Groceries shopping', sampleCategories);
      expect(match, isNotNull);
      expect(match!.id, equals(1));
    });

    test('Keyword matching: Fuel / Petrol', () {
      final match1 = SmartCategorizerEngine.matchCategory('Filled petrol at HP bunk', sampleCategories);
      expect(match1?.label, equals('Fuel & Transport'));

      final match2 = SmartCategorizerEngine.matchCategory('Diesel 20 liters', sampleCategories);
      expect(match2?.label, equals('Fuel & Transport'));
    });

    test('Keyword matching: Food vs Groceries', () {
      final match1 = SmartCategorizerEngine.matchCategory('Bought 2 packets of milk', sampleCategories);
      expect(match1?.label, equals('Groceries'));

      final match2 = SmartCategorizerEngine.matchCategory('Dinner with colleagues at bakery', sampleCategories);
      expect(match2?.label, equals('Food & Dining'));
    });

    test('Keyword matching: Capital & Construction', () {
      final match1 = SmartCategorizerEngine.matchCategory('Roofing sheets payment', sampleCategories);
      expect(match1?.label, equals('Home & Capital'));

      final match2 = SmartCategorizerEngine.matchCategory('Cement and sand for flooring', sampleCategories);
      expect(match2?.label, equals('Home & Capital'));
    });

    test('Keyword matching: Medical / Healthcare', () {
      final match1 = SmartCategorizerEngine.matchCategory('Lakeshore hospital consultation', sampleCategories);
      expect(match1?.label, equals('Health & Medical'));

      final match2 = SmartCategorizerEngine.matchCategory('Pharmacy medicine tablets', sampleCategories);
      expect(match2?.label, equals('Health & Medical'));
    });

    test('Word boundary test: partial word substrings should not match', () {
      // "milk" should not match inside "milkyway"
      final match1 = SmartCategorizerEngine.matchCategory('Galaxy milkyway chocolate bar', sampleCategories);
      expect(match1?.id, isNot(equals(1)));

      // "petrol" should not match "petrology"
      final match2 = SmartCategorizerEngine.matchCategory('Studying petrology textbook', sampleCategories);
      expect(match2?.id, isNot(equals(3)));
    });

    test('Case insensitivity and punctuation resilience', () {
      final match = SmartCategorizerEngine.matchCategory('***PETROL*** (₹500)!!', sampleCategories);
      expect(match?.label, equals('Fuel & Transport'));
    });

    test('Edge case: null, empty, whitespace strings return null', () {
      expect(SmartCategorizerEngine.matchCategory(null, sampleCategories), isNull);
      expect(SmartCategorizerEngine.matchCategory('', sampleCategories), isNull);
      expect(SmartCategorizerEngine.matchCategory('   ', sampleCategories), isNull);
      expect(SmartCategorizerEngine.matchCategory('random unlisted note xyz', sampleCategories), isNull);
    });

    test('Batch generation correctly matches transactions and skips non-matching', () {
      final now = DateTime.now();
      final txs = [
        Transaction(id: 101, amount: -50000, accountId: 1, date: now, valueDate: now, comment: 'Milk & Bread', status: 0, crStatus: 'CLEARED'),
        Transaction(id: 102, amount: -120000, accountId: 1, date: now, valueDate: now, comment: 'Petrol fuel pump', status: 0, crStatus: 'CLEARED'),
        Transaction(id: 103, amount: -80000, accountId: 1, date: now, valueDate: now, comment: 'Misc unclassifiable expense', status: 0, crStatus: 'CLEARED'),
        Transaction(id: 104, amount: 2500000, accountId: 1, date: now, valueDate: now, comment: 'Monthly Salary payroll', status: 0, crStatus: 'CLEARED'),
        Transaction(id: 105, amount: -15000, accountId: 1, date: now, valueDate: now, comment: null, status: 0, crStatus: 'CLEARED'),
      ];

      final suggestions = SmartCategorizerEngine.generateBatchSuggestions(
        transactions: txs,
        availableCategories: sampleCategories,
      );

      expect(suggestions.length, equals(3));
      expect(suggestions[0].transaction.id, equals(101));
      expect(suggestions[0].matchedCategory.label, equals('Groceries'));
      expect(suggestions[0].matchedKeyword, equals('milk'));

      expect(suggestions[1].transaction.id, equals(102));
      expect(suggestions[1].matchedCategory.label, equals('Fuel & Transport'));

      expect(suggestions[2].transaction.id, equals(104));
      expect(suggestions[2].matchedCategory.label, equals('Salary'));
    });
  });
}
