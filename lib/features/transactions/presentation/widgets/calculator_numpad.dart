import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class CalculatorNumpad extends StatelessWidget {
  final String currentValue;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  const CalculatorNumpad({
    super.key,
    required this.currentValue,
    required this.onChanged,
    required this.onSubmitted,
  });

  void _onKeyPress(String key) {
    if (key == '⌫') {
      if (currentValue.isNotEmpty) {
        onChanged(currentValue.substring(0, currentValue.length - 1));
      }
      return;
    }

    if (key == 'C') {
      onChanged('');
      return;
    }

    if (key == '=') {
      _evaluateMath();
      return;
    }

    if (key == '.') {
      if (currentValue.isEmpty) {
        onChanged('0.');
        return;
      }
      final parts = currentValue.split(RegExp(r'[\+\-\×\÷\*/]'));
      if (!parts.last.contains('.')) {
        onChanged('$currentValue.');
      }
      return;
    }

    if (['+', '-', '×', '÷'].contains(key)) {
      if (currentValue.isEmpty) return;
      final lastChar = currentValue[currentValue.length - 1];
      if (['+', '-', '×', '÷'].contains(lastChar)) {
        onChanged('${currentValue.substring(0, currentValue.length - 1)}$key');
      } else {
        onChanged('$currentValue$key');
      }
      return;
    }

    // Number key
    if (currentValue == '0') {
      onChanged(key);
    } else {
      onChanged('$currentValue$key');
    }
  }

  void _evaluateMath() {
    try {
      final sanitized = currentValue.replaceAll('×', '*').replaceAll('÷', '/');
      final result = _simpleEvaluate(sanitized);
      if (result != null) {
        // Format to max 2 decimal places
        if (result == result.roundToDouble()) {
          onChanged(result.toInt().toString());
        } else {
          onChanged(result.toStringAsFixed(2));
        }
      }
    } catch (_) {}
  }

  double? _simpleEvaluate(String expr) {
    final tokens = <String>[];
    String currentNum = '';

    for (int i = 0; i < expr.length; i++) {
      final char = expr[i];
      if (['+', '-', '*', '/'].contains(char)) {
        if (currentNum.isNotEmpty) {
          tokens.add(currentNum);
          currentNum = '';
        }
        tokens.add(char);
      } else {
        currentNum += char;
      }
    }
    if (currentNum.isNotEmpty) tokens.add(currentNum);
    if (tokens.isEmpty) return null;

    double total = double.tryParse(tokens[0]) ?? 0;
    for (int i = 1; i < tokens.length; i += 2) {
      if (i + 1 >= tokens.length) break;
      final op = tokens[i];
      final nextNum = double.tryParse(tokens[i + 1]) ?? 0;
      if (op == '+') total += nextNum;
      if (op == '-') total -= nextNum;
      if (op == '*') total *= nextNum;
      if (op == '/') {
        if (nextNum != 0) total /= nextNum;
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final keys = [
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '-'],
      ['.', '0', '⌫', '+'],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in keys)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  for (final key in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _KeyButton(
                          label: key,
                          isOperator: ['+', '-', '×', '÷', '='].contains(key),
                          isDark: isDark,
                          onTap: () => _onKeyPress(key),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final bool isOperator;
  final bool isDark;
  final VoidCallback onTap;

  const _KeyButton({
    required this.label,
    required this.isOperator,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isOperator
        ? AppColors.primary.withOpacity(isDark ? 0.2 : 0.12)
        : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant);

    final textColor = isOperator
        ? AppColors.primaryLight
        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
