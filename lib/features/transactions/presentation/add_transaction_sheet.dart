import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../accounts/presentation/create_account_dialog.dart';
import '../../categories/presentation/edit_category_dialog.dart';
import '../../categories/presentation/widgets/category_icon_helper.dart';
import '../../categories/domain/smart_categorizer_engine.dart';
import 'split_transaction_screen.dart';
import 'widgets/calculator_numpad.dart';

enum TransactionType { expense, income, transfer }

class AddTransactionSheet extends ConsumerStatefulWidget {
  final Transaction? initialTransaction; // null means new, non-null means edit

  const AddTransactionSheet({super.key, this.initialTransaction});

  @override
  ConsumerState<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  TransactionType _type = TransactionType.expense;
  String _amountExpression = '';
  late TextEditingController _noteController;
  late DateTime _selectedDate;
  int? _selectedAccountId;
  int? _transferToAccountId;
  int? _selectedCatId;
  bool _userManuallySelectedCategory = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialTransaction;
    if (init != null) {
      if (init.transferAccount != null || init.transferPeer != null) {
        _type = TransactionType.transfer;
        _transferToAccountId = init.transferAccount;
      } else if (init.amount > 0) {
        _type = TransactionType.income;
      } else {
        _type = TransactionType.expense;
      }
      final double rupees = (init.amount.abs()) / 100.0;
      _amountExpression = rupees == rupees.roundToDouble()
          ? rupees.toInt().toString()
          : rupees.toStringAsFixed(2);
      _noteController = TextEditingController(text: init.comment ?? '');
      _selectedDate = init.date;
      _selectedAccountId = init.accountId;
      _selectedCatId = init.catId;
      _userManuallySelectedCategory = init.catId != null;
    } else {
      _noteController = TextEditingController();
      _selectedDate = DateTime.now();
      _selectedAccountId = ref.read(selectedAccountIdProvider);
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double _getCalculatedRupees() {
    if (_amountExpression.isEmpty) return 0.0;
    try {
      final sanitized = _amountExpression.replaceAll('×', '*').replaceAll('÷', '/');
      // Simple evaluation if operator present
      if (sanitized.contains('+') || sanitized.contains('-') || sanitized.contains('*') || sanitized.contains('/')) {
        // Evaluate simple sum
        final parts = sanitized.split(RegExp(r'(?=[+\-*\/])|(?<=[+\-*\/])'));
        double total = double.tryParse(parts.first) ?? 0.0;
        for (int i = 1; i < parts.length; i += 2) {
          if (i + 1 >= parts.length) break;
          final op = parts[i];
          final val = double.tryParse(parts[i + 1]) ?? 0.0;
          if (op == '+') total += val;
          if (op == '-') total -= val;
          if (op == '*') total *= val;
          if (op == '/' && val != 0) total /= val;
        }
        return total;
      }
      return double.tryParse(_amountExpression) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _save() async {
    final rupees = _getCalculatedRupees();
    if (rupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Please enter an amount greater than 0'),
        ),
      );
      return;
    }

    final db = ref.read(databaseProvider);
    final paise = (rupees * 100).round();
    final note = _noteController.text.trim();

    if (_selectedAccountId == null) {
      final accounts = await db.getAllAccounts();
      if (!mounted) return;
      if (accounts.isNotEmpty) {
        _selectedAccountId = accounts.first.id;
      } else {
        final created = await CreateAccountDialog.show(context);
        if (created != null && mounted) {
          setState(() => _selectedAccountId = created.id);
        }
        return;
      }
    }

    try {
      if (widget.initialTransaction != null) {
        // Update existing transaction
        final existing = widget.initialTransaction!;
        final updatedAmount = _type == TransactionType.expense ? -paise : paise;
        final updated = existing.copyWith(
          amount: updatedAmount,
          comment: drift.Value(note),
          catId: drift.Value(_selectedCatId),
          date: _selectedDate,
          valueDate: _selectedDate,
          accountId: _selectedAccountId!,
        );
        await db.updateTransaction(updated);
      } else {
        // Create new entry
        if (_type == TransactionType.transfer) {
          if (_transferToAccountId == null || _transferToAccountId == _selectedAccountId) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.expense,
                content: Text('Please select a different destination account for transfer.'),
              ),
            );
            return;
          }
          await db.createTransfer(
            fromAccountId: _selectedAccountId!,
            toAccountId: _transferToAccountId!,
            amountPaise: paise,
            date: _selectedDate,
            comment: note.isNotEmpty ? note : 'Transfer',
          );
        } else {
          final amt = _type == TransactionType.expense ? -paise : paise;
          await db.createTransaction(
            TransactionsCompanion.insert(
              amount: amt,
              accountId: _selectedAccountId!,
              date: _selectedDate,
              valueDate: _selectedDate,
              comment: drift.Value(note),
              catId: drift.Value(_selectedCatId),
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.income,
            content: Text(
              widget.initialTransaction != null
                  ? 'Transaction updated'
                  : '${_type.name.toUpperCase()} of ₹${rupees.toStringAsFixed(2)} saved',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Error saving: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? <Account>[];
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final categories = categoriesAsync.value ?? <Category>[];

    if (_selectedAccountId == null && accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }
    if (_type == TransactionType.transfer && _transferToAccountId == null && accounts.length > 1) {
      _transferToAccountId = accounts.firstWhere((a) => a.id != _selectedAccountId).id;
    }

    final Color accentColor = _type == TransactionType.expense
        ? AppColors.expense
        : (_type == TransactionType.income ? AppColors.income : AppColors.transfer);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Transaction Type Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _TypeTab(
                      label: 'Expense',
                      icon: Icons.arrow_downward_rounded,
                      color: AppColors.expense,
                      isSelected: _type == TransactionType.expense,
                      onTap: () {
                        if (_type != TransactionType.expense) {
                          setState(() {
                            _type = TransactionType.expense;
                            _selectedCatId = null;
                            _userManuallySelectedCategory = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _TypeTab(
                      label: 'Income',
                      icon: Icons.arrow_upward_rounded,
                      color: AppColors.income,
                      isSelected: _type == TransactionType.income,
                      onTap: () {
                        if (_type != TransactionType.income) {
                          setState(() {
                            _type = TransactionType.income;
                            _selectedCatId = null;
                            _userManuallySelectedCategory = false;
                          });
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    _TypeTab(
                      label: 'Transfer',
                      icon: Icons.swap_horiz_rounded,
                      color: AppColors.transfer,
                      isSelected: _type == TransactionType.transfer,
                      onTap: () {
                        if (_type != TransactionType.transfer) {
                          setState(() {
                            _type = TransactionType.transfer;
                            _selectedCatId = null;
                            _userManuallySelectedCategory = false;
                          });
                        }
                      },
                    ),
                    if (widget.initialTransaction == null) ...[
                      const SizedBox(width: 8),
                      _TypeTab(
                        label: 'Split',
                        icon: Icons.call_split_rounded,
                        color: const Color(0xFFF59E0B),
                        isSelected: false,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SplitTransactionScreen()),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Prominent Amount Input Display
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _amountExpression.isEmpty ? '0' : _amountExpression,
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: accentColor,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Account & Date Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (_type != TransactionType.transfer) ...[
                      // Single Account Selector
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: accounts.isEmpty
                                ? OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: () async {
                                      final created = await CreateAccountDialog.show(context);
                                      if (created != null && mounted) {
                                        setState(() => _selectedAccountId = created.id);
                                      }
                                    },
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text('Create Account'),
                                  )
                                : DropdownButtonFormField<int>(
                                    value: _selectedAccountId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    items: accounts.map((acc) {
                                      return DropdownMenuItem<int>(
                                        value: acc.id,
                                        child: Text(acc.label, overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => _selectedAccountId = val),
                                  ),
                          ),
                          if (accounts.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.primary),
                              tooltip: 'New Account',
                              onPressed: () async {
                                final created = await CreateAccountDialog.show(context);
                                if (created != null && mounted) {
                                  setState(() => _selectedAccountId = created.id);
                                }
                              },
                            ),
                          ],
                        ],
                      ),

                      // Category Selector (for Expense and Income)
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              value: _selectedCatId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(value: null, child: Text('No Category')),
                                ...categories.where((c) => c.type == (_type == TransactionType.expense ? 0 : 1)).map((cat) {
                                  final color = Color(cat.color ?? 0xFF10B981);
                                  return DropdownMenuItem<int?>(
                                    value: cat.id,
                                    child: Row(
                                      children: [
                                        Icon(CategoryIconHelper.getIcon(cat.icon), size: 18, color: color),
                                        const SizedBox(width: 8),
                                        Text(cat.label, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedCatId = val;
                                  _userManuallySelectedCategory = true;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.primary),
                            tooltip: 'New Category',
                            onPressed: () async {
                              final created = await EditCategoryDialog.show(
                                context,
                                defaultType: _type == TransactionType.expense ? 0 : 1,
                              );
                              if (created != null && mounted) {
                                setState(() {
                                  _selectedCatId = created.id;
                                  _userManuallySelectedCategory = true;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ] else ...[
                      // Transfer Source and Destination
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _selectedAccountId,
                              decoration: InputDecoration(
                                labelText: 'From',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: accounts.map((acc) {
                                return DropdownMenuItem<int>(
                                  value: acc.id,
                                  child: Text(acc.label, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _selectedAccountId = val),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded, size: 20),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _transferToAccountId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'To',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: accounts.map((acc) {
                                return DropdownMenuItem<int>(
                                  value: acc.id,
                                  child: Text(acc.label, overflow: TextOverflow.ellipsis),
                                );
                              }).toList(),
                              onChanged: (val) => setState(() => _transferToAccountId = val),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Note Input and Date Picker Button
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _noteController,
                            onChanged: (text) {
                              if (!_userManuallySelectedCategory && _type != TransactionType.transfer) {
                                final matched = SmartCategorizerEngine.matchCategory(text, categories);
                                if (matched != null && matched.id != _selectedCatId) {
                                  setState(() => _selectedCatId = matched.id);
                                }
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Note (e.g. Groceries)',
                              isDense: true,
                              prefixIcon: const Icon(Icons.edit_note_rounded, size: 22),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _pickDateTime,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.calendar_today_rounded, size: 16),
                          label: Text(
                            DateFormat('dd MMM').format(_selectedDate),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Interactive Calculator Numpad
              CalculatorNumpad(
                currentValue: _amountExpression,
                onChanged: (val) => setState(() => _amountExpression = val),
                onSubmitted: _save,
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      widget.initialTransaction != null ? 'Update Transaction' : 'Save Entry',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
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

class _TypeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
