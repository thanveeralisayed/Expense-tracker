import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter Tests & Edge Cases', () {
    test('Zero paise formats as ₹0.00', () {
      expect(CurrencyFormatter.formatPaise(0), equals('₹0.00'));
      expect(CurrencyFormatter.formatPaiseAbsolute(0), equals('₹0.00'));
      expect(CurrencyFormatter.formatAmountOnly(0), equals('0.00'));
    });

    test('Negative paise formats with leading minus sign', () {
      expect(CurrencyFormatter.formatPaise(-15000), equals('-₹150.00'));
      expect(CurrencyFormatter.formatPaise(-25050), equals('-₹250.50'));
      expect(CurrencyFormatter.formatPaise(-1), equals('-₹0.01')); // 1 paisa edge case
    });

    test('Positive paise formats with leading plus sign', () {
      expect(CurrencyFormatter.formatPaise(100000), equals('+₹1,000.00'));
      expect(CurrencyFormatter.formatPaise(50), equals('+₹0.50'));
      expect(CurrencyFormatter.formatPaise(1), equals('+₹0.01')); // 1 paisa edge case
    });

    test('formatPaiseAbsolute returns positive number without +/- signs', () {
      expect(CurrencyFormatter.formatPaiseAbsolute(-15000), equals('₹150.00'));
      expect(CurrencyFormatter.formatPaiseAbsolute(15000), equals('₹150.00'));
      expect(CurrencyFormatter.formatPaiseAbsolute(-32699500), equals('₹3,26,995.00'));
    });

    test('formatAmountOnly returns numeric string with Indian comma grouping', () {
      expect(CurrencyFormatter.formatAmountOnly(-15000), equals('150.00'));
      expect(CurrencyFormatter.formatAmountOnly(10000000), equals('1,00,000.00')); // 1 Lakh
      expect(CurrencyFormatter.formatAmountOnly(32699500), equals('3,26,995.00'));
    });

    test('Large monetary sums adhere to Indian numbering system (Lakhs & Crores)', () {
      // 10,00,000 rupees (10 Lakhs) = 100000000 paise
      expect(CurrencyFormatter.formatPaise(100000000), equals('+₹10,00,000.00'));
      // 1,00,00,000 rupees (1 Crore) = 1000000000 paise
      expect(CurrencyFormatter.formatPaise(1000000000), equals('+₹1,00,00,000.00'));
    });

    test('Compact format for large amounts', () {
      expect(CurrencyFormatter.formatPaise(150000, compact: true), equals('+₹1,500'));
      expect(CurrencyFormatter.formatPaise(-500000, compact: true), equals('-₹5,000'));
      // Amounts under 1,000 rupees use standard formatting even when compact=true
      expect(CurrencyFormatter.formatPaise(50000, compact: true), equals('+₹500.00'));
    });
  });
}
