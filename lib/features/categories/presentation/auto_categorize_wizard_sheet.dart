import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../domain/smart_categorizer_engine.dart';
import 'widgets/category_icon_helper.dart';

class AutoCategorizeWizardSheet extends ConsumerStatefulWidget {
  const AutoCategorizeWizardSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AutoCategorizeWizardSheet(),
    );
  }

  @override
  ConsumerState<AutoCategorizeWizardSheet> createState() => _AutoCategorizeWizardSheetState();
}

class _AutoCategorizeWizardSheetState extends ConsumerState<AutoCategorizeWizardSheet> {
  bool _isLoading = true;
  bool _isApplying = false;
  List<CategorizeSuggestion> _suggestions = [];
  List<Transaction> _unmatched = [];
  List<Category> _categories = [];
  final Map<int, int?> _unmatchedCategories = {};
  int _totalUncategorized = 0;

  @override
  void initState() {
    super.initState();
    _scanUncategorized();
  }

  Future<void> _scanUncategorized() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseProvider);
    final uncategorized = await db.getUncategorizedTransactions();
    final categories = await db.getAllCategories();

    final matches = SmartCategorizerEngine.generateBatchSuggestions(
      transactions: uncategorized,
      availableCategories: categories,
    );

    final matchedTxIds = matches.map((m) => m.transaction.id).toSet();
    final unmatched = uncategorized.where((tx) => !matchedTxIds.contains(tx.id)).toList();

    if (mounted) {
      setState(() {
        _totalUncategorized = uncategorized.length;
        _suggestions = matches;
        _unmatched = unmatched;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  Future<void> _applyBatch() async {
    final map = <int, int>{};
    for (final item in _suggestions) {
      if (item.isSelected) {
        map[item.transaction.id] = item.matchedCategory.id;
      }
    }
    for (final entry in _unmatchedCategories.entries) {
      if (entry.value != null) {
        map[entry.key] = entry.value!;
      }
    }
    if (map.isEmpty) return;

    setState(() => _isApplying = true);
    final db = ref.read(databaseProvider);

    try {
      await db.batchUpdateTransactionCategories(map);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.income,
            content: Text('Successfully categorized ${map.length} transactions!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.expense, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _toggleAll(bool select) {
    setState(() {
      for (final s in _suggestions) {
        s.isSelected = select;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedMatchesCount = _suggestions.where((s) => s.isSelected).length;
    final manualSelectedCount = _unmatchedCategories.values.where((c) => c != null).length;
    final totalToApply = selectedMatchesCount + manualSelectedCount;

    String subtitleText;
    if (_isLoading) {
      subtitleText = 'Scanning transaction notes...';
    } else if (_totalUncategorized == 0) {
      subtitleText = 'All transactions categorized';
    } else if (_suggestions.isNotEmpty && _unmatched.isEmpty) {
      subtitleText = 'Found ${_suggestions.length} automatic ${_suggestions.length == 1 ? 'match' : 'matches'}';
    } else if (_suggestions.isNotEmpty && _unmatched.isNotEmpty) {
      subtitleText = 'Found ${_suggestions.length} ${_suggestions.length == 1 ? 'match' : 'matches'} (${_unmatched.length} manual review)';
    } else {
      subtitleText = '$_totalUncategorized uncategorized ${_totalUncategorized == 1 ? 'entry' : 'entries'} found';
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          // Drag Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Smart Auto-Categorizer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitleText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLoading && _suggestions.isNotEmpty)
                  TextButton(
                    onPressed: () => _toggleAll(selectedMatchesCount != _suggestions.length),
                    child: Text(selectedMatchesCount == _suggestions.length ? 'Deselect All' : 'Select All'),
                  ),
              ],
            ),
          ),
          const Divider(),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _totalUncategorized == 0
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 56,
                                color: AppColors.income,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'All transactions categorized!',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Every single transaction already has an assigned category.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        children: [
                          if (_suggestions.isNotEmpty) ...[
                            if (_unmatched.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8, bottom: 8, top: 4),
                                child: Text(
                                  'SUGGESTED MATCHES (${_suggestions.length})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ..._suggestions.map((item) {
                              final cat = item.matchedCategory;
                              final tx = item.transaction;
                              final dateStr = DateFormat('dd MMM yyyy').format(tx.date);

                              return CheckboxListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                value: item.isSelected,
                                onChanged: (val) {
                                  setState(() => item.isSelected = val ?? false);
                                },
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tx.comment?.trim().isNotEmpty == true ? tx.comment!.trim() : 'No note',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      CurrencyFormatter.formatPaise(tx.amount),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: tx.amount < 0 ? AppColors.expense : AppColors.income,
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 12),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Color(cat.color ?? 0xFF10B981).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CategoryIconHelper.getIcon(cat.icon),
                                              size: 13,
                                              color: Color(cat.color ?? 0xFF10B981),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              cat.label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(cat.color ?? 0xFF10B981),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],

                          if (_unmatched.isNotEmpty) ...[
                            Padding(
                              padding: EdgeInsets.only(
                                left: 8,
                                top: _suggestions.isNotEmpty ? 16 : 4,
                                bottom: 8,
                              ),
                              child: Text(
                                'UNMATCHED ENTRIES (${_unmatched.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ),
                            ..._unmatched.map((tx) {
                              final dateStr = DateFormat('dd MMM yyyy').format(tx.date);
                              final expectedType = tx.amount < 0 ? 0 : 1;
                              final typeCategories = _categories.where((c) => c.type == expectedType).toList();
                              final selectedCatId = _unmatchedCategories[tx.id];

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selectedCatId != null
                                        ? AppColors.primary.withValues(alpha: 0.5)
                                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tx.comment?.trim().isNotEmpty == true ? tx.comment!.trim() : 'Uncategorized Entry',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          CurrencyFormatter.formatPaise(tx.amount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: tx.amount < 0 ? AppColors.expense : AppColors.income,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                          ),
                                        ),
                                        const Spacer(),
                                        DropdownButton<int>(
                                          value: selectedCatId,
                                          hint: const Text('Choose Category', style: TextStyle(fontSize: 12)),
                                          underline: const SizedBox.shrink(),
                                          isDense: true,
                                          items: typeCategories.map((cat) {
                                            final color = Color(cat.color ?? 0xFF10B981);
                                            return DropdownMenuItem<int>(
                                              value: cat.id,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(CategoryIconHelper.getIcon(cat.icon), size: 14, color: color),
                                                  const SizedBox(width: 6),
                                                  Text(cat.label, style: const TextStyle(fontSize: 12)),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            setState(() => _unmatchedCategories[tx.id] = val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
          ),

          // Bottom Action Bar
          if (!_isLoading && totalToApply > 0)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: !_isApplying ? _applyBatch : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isApplying
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text('Apply to $totalToApply ${totalToApply == 1 ? 'Transaction' : 'Transactions'}'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
