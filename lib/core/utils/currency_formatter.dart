import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _inrFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final NumberFormat _inrCompactFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Converts an amount in cents/paise (e.g. -14500) to formatted currency string (e.g. "-₹145.00")
  static String formatPaise(int paise, {bool compact = false}) {
    final double rupees = paise / 100.0;
    if (compact && rupees.abs() >= 1000) {
      final formatted = _inrCompactFormat.format(rupees.abs());
      return rupees < 0 ? '-$formatted' : '+$formatted';
    }
    final formatted = _inrFormat.format(rupees.abs());
    return rupees < 0 ? '-$formatted' : (rupees > 0 ? '+$formatted' : '₹0.00');
  }

  /// Converts paise to plain positive formatted string without leading +/-
  static String formatPaiseAbsolute(int paise) {
    final double rupees = (paise.abs()) / 100.0;
    return _inrFormat.format(rupees);
  }

  /// Returns just the number with 2 decimals
  static String formatAmountOnly(int paise) {
    final double rupees = (paise.abs()) / 100.0;
    return NumberFormat('#,##,##0.00', 'en_IN').format(rupees);
  }
}
