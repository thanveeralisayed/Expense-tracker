import 'dart:convert';

class RecurringCommitment {
  final String id;
  final String title;
  final int amountPaise;
  final bool isExpense;
  final int? accountId;
  final int? categoryId;
  final String frequency; // 'monthly', 'weekly', 'yearly'
  final int dayNumber; // 1-31 for monthly/yearly, 1-7 (Mon-Sun) for weekly
  final bool isActive;

  const RecurringCommitment({
    required this.id,
    required this.title,
    required this.amountPaise,
    this.isExpense = true,
    this.accountId,
    this.categoryId,
    this.frequency = 'monthly',
    this.dayNumber = 1,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amountPaise': amountPaise,
        'isExpense': isExpense,
        'accountId': accountId,
        'categoryId': categoryId,
        'frequency': frequency,
        'dayNumber': dayNumber,
        'isActive': isActive,
      };

  factory RecurringCommitment.fromJson(Map<String, dynamic> json) => RecurringCommitment(
        id: json['id'] as String,
        title: json['title'] as String,
        amountPaise: json['amountPaise'] as int,
        isExpense: json['isExpense'] as bool? ?? true,
        accountId: json['accountId'] as int?,
        categoryId: json['categoryId'] as int?,
        frequency: json['frequency'] as String? ?? 'monthly',
        dayNumber: json['dayNumber'] as int? ?? 1,
        isActive: json['isActive'] as bool? ?? true,
      );

  RecurringCommitment copyWith({
    String? id,
    String? title,
    int? amountPaise,
    bool? isExpense,
    int? accountId,
    int? categoryId,
    String? frequency,
    int? dayNumber,
    bool? isActive,
  }) {
    return RecurringCommitment(
      id: id ?? this.id,
      title: title ?? this.title,
      amountPaise: amountPaise ?? this.amountPaise,
      isExpense: isExpense ?? this.isExpense,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      frequency: frequency ?? this.frequency,
      dayNumber: dayNumber ?? this.dayNumber,
      isActive: isActive ?? this.isActive,
    );
  }
}

class RecurringCommitmentsService {
  static const String settingsKey = 'recurring_commitments_data';

  /// Parse list of recurring commitments from JSON string stored in appSettings
  static List<RecurringCommitment> parseCommitments(String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty) return [];
    try {
      final decoded = json.decode(jsonString);
      if (decoded is List) {
        return decoded
            .map((e) => RecurringCommitment.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Serialize list of recurring commitments to JSON string for appSettings
  static String serializeCommitments(List<RecurringCommitment> commitments) {
    final list = commitments.map((c) => c.toJson()).toList();
    return json.encode(list);
  }

  /// Calculate monthly equivalent amount for a commitment in paise
  static int calculateMonthlyEquivalentPaise(RecurringCommitment c) {
    if (!c.isActive) return 0;
    switch (c.frequency) {
      case 'weekly':
        // 52 weeks / 12 months = 4.333
        return (c.amountPaise * 52 / 12).round();
      case 'yearly':
        return (c.amountPaise / 12).round();
      case 'monthly':
      default:
        return c.amountPaise;
    }
  }

  /// Calculate total monthly commitments (expenses and income separated)
  static ({int monthlyExpensePaise, int monthlyIncomePaise, int netMonthlyPaise})
      calculateMonthlyTotals(List<RecurringCommitment> commitments) {
    int expenseTotal = 0;
    int incomeTotal = 0;

    for (final c in commitments) {
      if (!c.isActive) continue;
      final monthlyEquivalent = calculateMonthlyEquivalentPaise(c);
      if (c.isExpense) {
        expenseTotal += monthlyEquivalent;
      } else {
        incomeTotal += monthlyEquivalent;
      }
    }

    return (
      monthlyExpensePaise: expenseTotal,
      monthlyIncomePaise: incomeTotal,
      netMonthlyPaise: incomeTotal - expenseTotal,
    );
  }

  /// Determine the next scheduled due date for a commitment with date boundary clamps
  static DateTime getNextDueDate(RecurringCommitment c, {DateTime? referenceNow}) {
    final now = referenceNow ?? DateTime.now();

    if (c.frequency == 'weekly') {
      // dayNumber 1 = Monday ... 7 = Sunday
      int daysAhead = (c.dayNumber - now.weekday + 7) % 7;
      if (daysAhead == 0 && now.hour >= 23 && now.minute >= 59) {
        daysAhead = 7;
      }
      final target = now.add(Duration(days: daysAhead));
      return DateTime(target.year, target.month, target.day);
    }

    if (c.frequency == 'yearly') {
      int year = now.year;
      int month = now.month;
      int daysInMonth = DateTime(year, month + 1, 0).day;
      int clampedDay = c.dayNumber.clamp(1, daysInMonth);

      var candidate = DateTime(year, month, clampedDay);
      if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
        candidate = DateTime(year + 1, month, clampedDay);
      }
      return candidate;
    }

    // Monthly frequency:
    int year = now.year;
    int month = now.month;
    int daysInCurrentMonth = DateTime(year, month + 1, 0).day;
    int clampedDay = c.dayNumber.clamp(1, daysInCurrentMonth);

    var candidate = DateTime(year, month, clampedDay);
    if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
      // Move to next calendar month
      final nextMonth = month == 12 ? 1 : month + 1;
      final nextYear = month == 12 ? year + 1 : year;
      final daysInNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
      candidate = DateTime(nextYear, nextMonth, c.dayNumber.clamp(1, daysInNextMonth));
    }
    return candidate;
  }

  /// Check whether commitment is due within given days
  static bool isDueSoon(RecurringCommitment c, {int daysAhead = 7, DateTime? referenceNow}) {
    if (!c.isActive) return false;
    final now = referenceNow ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nextDue = getNextDueDate(c, referenceNow: now);
    final diff = nextDue.difference(today).inDays;
    return diff >= 0 && diff <= daysAhead;
  }
}
