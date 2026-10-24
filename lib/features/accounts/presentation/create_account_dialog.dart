import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';

class CreateAccountDialog extends ConsumerStatefulWidget {
  final Account? initialAccount; // null = create new, non-null = edit

  const CreateAccountDialog({super.key, this.initialAccount});

  static Future<Account?> show(BuildContext context, {Account? initialAccount}) {
    return showModalBottomSheet<Account?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateAccountDialog(initialAccount: initialAccount),
    );
  }

  @override
  ConsumerState<CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends ConsumerState<CreateAccountDialog> {
  late TextEditingController _nameController;
  late TextEditingController _openingBalanceController;
  late TextEditingController _descController;
  String _selectedCurrency = 'INR';
  int _selectedColor = -16738680; // Default teal

  static const List<int> _colorPalette = [
    -16738680, // Teal
    -14503224, // Blue
    -11912449, // Indigo
    -7661603,  // Purple
    -14120358, // Emerald
    -6697729,  // Amber
    -4056997,  // Rose
    -15106322, // Cyan
  ];

  static const List<String> _quickSuggestions = [
    'Cash',
    'Bank Account',
    'Savings',
    'Credit Card',
    'Self Expense',
    'Home Expense',
  ];

  @override
  void initState() {
    super.initState();
    final init = widget.initialAccount;
    if (init != null) {
      _nameController = TextEditingController(text: init.label);
      final double rupees = init.openingBalance / 100.0;
      _openingBalanceController = TextEditingController(
        text: rupees != 0 ? rupees.toStringAsFixed(2) : '',
      );
      _descController = TextEditingController(text: init.description ?? '');
      _selectedCurrency = init.currency;
      _selectedColor = init.color;
    } else {
      _nameController = TextEditingController();
      _openingBalanceController = TextEditingController();
      _descController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _openingBalanceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Please enter an account name'),
        ),
      );
      return;
    }

    final balanceRupees = double.tryParse(_openingBalanceController.text.trim()) ?? 0.0;
    final openingBalancePaise = (balanceRupees * 100).round();
    final desc = _descController.text.trim();

    final db = ref.read(databaseProvider);

    try {
      if (widget.initialAccount != null) {
        // Edit existing
        final updated = widget.initialAccount!.copyWith(
          label: name,
          currency: _selectedCurrency,
          openingBalance: openingBalancePaise,
          description: drift.Value(desc.isNotEmpty ? desc : null),
          color: _selectedColor,
        );
        await db.updateAccount(updated);
        if (mounted) {
          Navigator.pop(context, updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.income,
              content: Text('Account "$name" updated'),
            ),
          );
        }
      } else {
        // Create new account
        final newId = await db.createAccount(
          AccountsCompanion.insert(
            label: name,
            currency: drift.Value(_selectedCurrency),
            openingBalance: drift.Value(openingBalancePaise),
            description: drift.Value(desc.isNotEmpty ? desc : null),
            color: drift.Value(_selectedColor),
          ),
        );

        // Auto-select the newly created account
        ref.read(selectedAccountIdProvider.notifier).state = newId;

        // If opening balance > 0 or < 0, record initial balance transaction
        if (openingBalancePaise != 0) {
          await db.createTransaction(
            TransactionsCompanion.insert(
              accountId: newId,
              amount: openingBalancePaise,
              date: DateTime.now(),
              valueDate: DateTime.now(),
              comment: const drift.Value('Opening Balance'),
            ),
          );
        }

        final created = Account(
          id: newId,
          label: name,
          openingBalance: openingBalancePaise,
          currency: _selectedCurrency,
          color: _selectedColor,
          grouping: 'MONTH',
          balanceType: 'CURRENT',
          excludeFromTotals: false,
          sealed: false,
          sortKey: 0,
        );

        if (mounted) {
          Navigator.pop(context, created);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.income,
              content: Text('Account "$name" created successfully'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Error saving account: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEdit = widget.initialAccount != null;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag pill
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Edit Account' : 'Create New Account',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Account Name Input
              TextField(
                controller: _nameController,
                autofocus: !isEdit,
                decoration: InputDecoration(
                  labelText: 'Account Name',
                  hintText: 'e.g. Cash, HDFC Bank, Savings',
                  prefixIcon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),

              // Quick suggestions chips
              if (!isEdit) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _quickSuggestions.map((suggestion) {
                    return ActionChip(
                      label: Text(suggestion, style: const TextStyle(fontSize: 12)),
                      backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onPressed: () {
                        setState(() {
                          _nameController.text = suggestion;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
              ],

              // Opening Balance & Currency Row
              Row(
                children: [
                  // Currency Dropdown
                  SizedBox(
                    width: 100,
                    child: DropdownButtonFormField<String>(
                      value: _selectedCurrency,
                      decoration: InputDecoration(
                        labelText: 'Currency',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'INR', child: Text('INR (₹)')),
                        DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                        DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                        DropdownMenuItem(value: 'AED', child: Text('AED')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCurrency = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Initial Opening Balance
                  Expanded(
                    child: TextField(
                      controller: _openingBalanceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Opening Balance',
                        hintText: '0.00',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Description (optional)
              TextField(
                controller: _descController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'e.g. Primary salary account',
                  prefixIcon: const Icon(Icons.notes_rounded, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Color Palette Picker
              const Text(
                'Account Color Accent',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _colorPalette.map((colorVal) {
                  final isColorSelected = _selectedColor == colorVal;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = colorVal),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(colorVal).withOpacity(1.0),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isColorSelected ? Colors.white : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isColorSelected
                            ? [
                                BoxShadow(
                                  color: Color(colorVal).withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: isColorSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Color(_selectedColor).withOpacity(1.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    isEdit ? 'Update Account' : 'Create Account',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
