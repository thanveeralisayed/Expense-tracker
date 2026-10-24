import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/budget_service.dart';

class SetBudgetDialog extends ConsumerStatefulWidget {
  final int? catId;
  final String? categoryName;
  final int? currentLimitPaise;

  const SetBudgetDialog({
    super.key,
    this.catId,
    this.categoryName,
    this.currentLimitPaise,
  });

  static Future<void> show(
    BuildContext context, {
    int? catId,
    String? categoryName,
    int? currentLimitPaise,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SetBudgetDialog(
        catId: catId,
        categoryName: categoryName,
        currentLimitPaise: currentLimitPaise,
      ),
    );
  }

  @override
  ConsumerState<SetBudgetDialog> createState() => _SetBudgetDialogState();
}

class _SetBudgetDialogState extends ConsumerState<SetBudgetDialog> {
  late final TextEditingController _amountController;
  int? _selectedCatId;

  @override
  void initState() {
    super.initState();
    _selectedCatId = widget.catId;
    final initialRupees = widget.currentLimitPaise != null
        ? (widget.currentLimitPaise! / 100).toStringAsFixed(0)
        : '';
    _amountController = TextEditingController(text: initialRupees);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String get _settingKey {
    if (_selectedCatId == null) {
      return BudgetService.overallBudgetKey;
    }
    return '${BudgetService.categoryBudgetPrefix}$_selectedCatId';
  }

  Future<void> _save() async {
    final text = _amountController.text.trim();
    final amountRupees = double.tryParse(text);
    if (amountRupees == null || amountRupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive budget amount.')),
      );
      return;
    }

    final paise = (amountRupees * 100).round();
    final db = ref.read(databaseProvider);
    await db.setSetting(_settingKey, paise.toString());

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedCatId == null
              ? 'Monthly overall budget updated!'
              : 'Category budget updated!'),
          backgroundColor: AppColors.incomeGreen,
        ),
      );
    }
  }

  Future<void> _remove() async {
    final db = ref.read(databaseProvider);
    await db.deleteSetting(_settingKey);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Budget target removed.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.currentLimitPaise != null ? 'Edit Budget' : 'Set New Budget',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.currentLimitPaise != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.expense),
                      tooltip: 'Delete Budget',
                      onPressed: _remove,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Select category if not pre-bound
              if (widget.catId == null && widget.categoryName == null) ...[
                const Text(
                  'Budget Type',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                categoriesAsync.when(
                  data: (categories) {
                    return DropdownButtonFormField<int?>(
                      value: _selectedCatId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          ),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Row(
                            children: [
                              Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.primary),
                              SizedBox(width: 8),
                              Flexible(child: Text('Total Monthly Budget (Overall)', overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                        ...categories.map(
                          (cat) => DropdownMenuItem<int?>(
                            value: cat.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Color(cat.color ?? 0xFF0D9488),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(child: Text(cat.label, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCatId = val;
                        });
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Text(
                  'Target: ${widget.categoryName ?? 'Total Monthly'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Amount Input
              const Text(
                'Monthly Limit (₹)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: false),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  hintText: '25,000',
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save Budget',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
