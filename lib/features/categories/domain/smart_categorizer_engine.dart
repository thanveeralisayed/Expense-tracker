import '../../../core/database/database.dart';

class CategorizeSuggestion {
  final Transaction transaction;
  final Category matchedCategory;
  final String matchedKeyword;
  final double confidence;
  bool isSelected;

  CategorizeSuggestion({
    required this.transaction,
    required this.matchedCategory,
    required this.matchedKeyword,
    required this.confidence,
    this.isSelected = true,
  });
}

class SmartCategorizerEngine {
  static const Map<String, List<String>> _defaultRules = {
    'Groceries': [
      'milk', 'veg', 'vegetable', 'vegetables', 'supermarket', 'grocery', 'groceries',
      'provision', 'provisions', 'egg', 'eggs', 'rice', 'bread', 'butter', 'fruits',
      'apple', 'banana', 'meat', 'chicken', 'fish', 'oil', 'sugar', 'atta', 'dawa'
    ],
    'Food & Dining': [
      'dinner', 'lunch', 'breakfast', 'tea', 'coffee', 'hotel', 'restaurant', 'bakery',
      'snack', 'snacks', 'swiggy', 'zomato', 'burger', 'pizza', 'biriyani', 'biryani',
      'shawarma', 'juice', 'shake', 'ice cream', 'cafe', 'mcdonalds', 'kfc', 'parotta'
    ],
    'Fuel & Transport': [
      'petrol', 'diesel', 'fuel', 'gas', 'cng', 'hp petrol', 'indian oil', 'bharat petroleum',
      'shell', 'fuel pump'
    ],
    'Home & Capital': [
      'roofing', 'cement', 'sand', 'paint', 'painting', 'construction', 'plumbing',
      'hardware', 'tiles', 'brick', 'bricks', 'wire', 'wiring', 'electrical', 'timber',
      'plywood', 'renovation', 'repair', 'ac', 'furniture', 'interior', 'curtains'
    ],
    'Health & Medical': [
      'lakeshore', 'doctor', 'medicine', 'pharmacy', 'clinic', 'hospital', 'medical',
      'dental', 'tablet', 'tablets', 'syrup', 'lab', 'blood test', 'scan', 'mri', 'consultation'
    ],
    'Utilities & Bills': [
      'recharge', 'airtel', 'jio', 'vi', 'electricity', 'kseb', 'water bill', 'wifi',
      'broadband', 'cylinder', 'gas cylinder', 'subscription', 'netflix', 'spotify', 'prime'
    ],
    'Shopping': [
      'dress', 'shirt', 'pant', 'clothes', 'clothing', 'amazon', 'flipkart', 'myntra',
      'shoes', 'footwear', 'watch', 'electronics', 'gadget', 't-shirt', 'jeans'
    ],
    'Family Support': [
      'vapa', 'umma', 'family', 'home expense', 'gift', 'pocket money', 'allowance', 'mom', 'dad'
    ],
    'Education': [
      'school', 'college', 'fee', 'fees', 'tuition', 'exam', 'books', 'stationery',
      'course', 'udemy', 'coaching', 'pen', 'notebook'
    ],
    'Entertainment': [
      'movie', 'cinema', 'theatre', 'game', 'gaming', 'concert', 'outing', 'park', 'pvr'
    ],
    'Salary': [
      'salary', 'wages', 'stipend', 'bonus', 'payroll'
    ],
    'Business Profit': [
      'profit', 'sales', 'client', 'project', 'freelance', 'consulting', 'commission'
    ],
    'Investment': [
      'mutual fund', 'sip', 'stock', 'shares', 'dividend', 'interest', 'fd', 'fixed deposit'
    ],
  };

  /// Find best category match for a single transaction note/comment
  static Category? matchCategory(String? text, List<Category> availableCategories, {int? amount}) {
    if (text == null || text.trim().isEmpty) return null;
    final normalized = text.toLowerCase();

    // 1. Direct label check if user typed category name itself
    for (final cat in availableCategories) {
      if (normalized.contains(cat.label.toLowerCase())) {
        return cat;
      }
    }

    // 2. Rule keyword matching
    for (final entry in _defaultRules.entries) {
      final categoryLabel = entry.key;
      final keywords = entry.value;

      for (final kw in keywords) {
        // Match word boundaries: e.g. "milk" in "bought milk 2L"
        final pattern = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(normalized)) {
          // Find matching Category in availableCategories
          final matched = _findCategoryByNameOrFallback(categoryLabel, availableCategories);
          if (matched != null) {
            return matched;
          }
        }
      }
    }

    return null;
  }

  /// Batch categorize a list of transactions with confidence and keyword details
  static List<CategorizeSuggestion> generateBatchSuggestions({
    required List<Transaction> transactions,
    required List<Category> availableCategories,
  }) {
    final suggestions = <CategorizeSuggestion>[];

    for (final tx in transactions) {
      if (tx.comment == null || tx.comment!.trim().isEmpty) continue;
      final normalized = tx.comment!.toLowerCase();

      bool found = false;

      // 1. Direct category label match
      for (final cat in availableCategories) {
        if (cat.label.trim().isNotEmpty &&
            normalized.contains(cat.label.toLowerCase())) {
          suggestions.add(
            CategorizeSuggestion(
              transaction: tx,
              matchedCategory: cat,
              matchedKeyword: cat.label,
              confidence: 0.99,
              isSelected: true,
            ),
          );
          found = true;
          break;
        }
      }
      if (found) continue;

      // 2. Rule keyword matching
      for (final entry in _defaultRules.entries) {
        if (found) break;
        final categoryLabel = entry.key;
        final keywords = entry.value;

        for (final kw in keywords) {
          final pattern = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false);
          if (pattern.hasMatch(normalized)) {
            final targetCat = _findCategoryByNameOrFallback(categoryLabel, availableCategories);
            if (targetCat != null) {
              suggestions.add(
                CategorizeSuggestion(
                  transaction: tx,
                  matchedCategory: targetCat,
                  matchedKeyword: kw,
                  confidence: 0.95,
                  isSelected: true,
                ),
              );
              found = true;
              break;
            }
          }
        }
      }
    }

    return suggestions;
  }

  static Category? _findCategoryByNameOrFallback(String name, List<Category> categories) {
    // Exact match
    for (final cat in categories) {
      if (cat.label.toLowerCase() == name.toLowerCase()) {
        return cat;
      }
    }
    // Partial match (e.g. "Groceries" inside "Groceries & Daily")
    for (final cat in categories) {
      if (cat.label.toLowerCase().contains(name.toLowerCase()) ||
          name.toLowerCase().contains(cat.label.toLowerCase())) {
        return cat;
      }
    }
    return null;
  }
}
