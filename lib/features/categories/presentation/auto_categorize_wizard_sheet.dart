import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

    if (mounted) {
      setState(() {
        _totalUncategorized = uncategorized.length;
        _suggestions = matches;
        _isLoading = false;
      });
    }
  }

  Future<void> _applyBatch() async {
    final selected = _suggestions.where((s) => s.isSelected).toList();
    if (selected.isEmpty) return;

    setState(() => _isApplying = true);
    final db = ref.read(databaseProvider);

    final map = <int, int>{};
    for (final item in selected) {
      map[item.transaction.id] = item.matchedCategory.id;
    }

    try {
      await db.batchUpdateTransactionCategories(map);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.income,
            content: Text('Successfully categorized ${selected.length} transactions!'),
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
    final selectedCount = _suggestions.where((s) => s.isSelected).length;

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
                        _isLoading
                            ? 'Scanning transaction notes...'
                            : 'Found ${_suggestions.length} matches across $_totalUncategorized uncategorized entries',
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
                    onPressed: () => _toggleAll(selectedCount != _suggestions.length),
                    child: Text(selectedCount == _suggestions.length ? 'Deselect All' : 'Select All'),
                  ),
              ],
            ),
          ),
          const Divider(),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _suggestions.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 56,
                                color: _totalUncategorized == 0 ? AppColors.income : AppColors.primary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _totalUncategorized == 0
                                    ? 'All transactions categorized!'
                                    : 'No automatic matches found',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _totalUncategorized == 0
                                    ? 'Every single transaction already has an assigned category.'
                                    : 'You can assign categories directly from transaction details or create custom rules.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final item = _suggestions[index];
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
                                    tx.comment ?? 'No note',
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
                        },
                      ),
          ),

          // Bottom Action Bar
          if (!_isLoading && _suggestions.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: selectedCount > 0 && !_isApplying ? _applyBatch : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isApplying
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text('Apply to $selectedCount Transactions'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
