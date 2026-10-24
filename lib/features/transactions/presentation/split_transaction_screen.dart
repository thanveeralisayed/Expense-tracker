import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../accounts/presentation/create_account_dialog.dart';

class SplitItemData {
  final TextEditingController noteController;
  final TextEditingController amountController;
  int? categoryId;

  SplitItemData({String note = '', String amount = '', this.categoryId})
      : noteController = TextEditingController(text: note),
        amountController = TextEditingController(text: amount);

  void dispose() {
    noteController.dispose();
    amountController.dispose();
  }

  double get amount => double.tryParse(amountController.text.trim()) ?? 0.0;
}

class SplitTransactionScreen extends ConsumerStatefulWidget {
  const SplitTransactionScreen({super.key});

  @override
  ConsumerState<SplitTransactionScreen> createState() => _SplitTransactionScreenState();
}

class _SplitTransactionScreenState extends ConsumerState<SplitTransactionScreen> {
  final TextEditingController _parentNoteController = TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController();
  late DateTime _selectedDate;
  int? _selectedAccountId;
  bool _autoCalculateTotal = true;

  final List<SplitItemData> _splitItems = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedAccountId = ref.read(selectedAccountIdProvider);

    // Initial two split items
    _splitItems.add(SplitItemData(note: 'Item 1'));
    _splitItems.add(SplitItemData(note: 'Item 2'));
  }

  @override
  void dispose() {
    _parentNoteController.dispose();
    _totalAmountController.dispose();
    for (final item in _splitItems) {
      item.dispose();
    }
    super.dispose();
  }

  double get _totalSplitsSum {
    return _splitItems.fold(0.0, (sum, item) => sum + item.amount);
  }

  double get _parentTotalAmount {
    if (_autoCalculateTotal) {
      return _totalSplitsSum;
    }
    return double.tryParse(_totalAmountController.text.trim()) ?? 0.0;
  }

  double get _remainingDifference {
    return _parentTotalAmount - _totalSplitsSum;
  }

  void _addSplitItem({double? defaultAmount}) {
    setState(() {
      final initialAmt = defaultAmount != null && defaultAmount > 0
          ? (defaultAmount == defaultAmount.roundToDouble()
              ? defaultAmount.toInt().toString()
              : defaultAmount.toStringAsFixed(2))
          : '';
      _splitItems.add(
        SplitItemData(
          note: 'Item ${_splitItems.length + 1}',
          amount: initialAmt,
        ),
      );
    });
  }

  void _removeSplitItem(int index) {
    if (_splitItems.length <= 1) return;
    setState(() {
      final removed = _splitItems.removeAt(index);
      removed.dispose();
    });
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
    final parentRupees = _parentTotalAmount;
    if (parentRupees <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Total amount must be greater than 0'),
        ),
      );
      return;
    }

    if (_splitItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.expense,
          content: Text('Please add at least one split item'),
        ),
      );
      return;
    }

    // Check each split has valid amount
    for (int i = 0; i < _splitItems.length; i++) {
      if (_splitItems[i].amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Split item #${i + 1} must have an amount > 0'),
          ),
        );
        return;
      }
    }

    // Check balance
    final diff = (_remainingDifference * 100).round();
    if (diff.abs() > 1) {
      // Allow minor rounding difference of <= 1 paise
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.expense,
          content: Text(
            'Splits do not equal total. Discrepancy of ₹${(_remainingDifference.abs()).toStringAsFixed(2)}',
          ),
        ),
      );
      return;
    }

    final db = ref.read(databaseProvider);
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

    final parentPaise = (parentRupees * 100).round();
    final parentNote = _parentNoteController.text.trim();

    try {
      final parentCompanion = TransactionsCompanion.insert(
        amount: -parentPaise.abs(),
        accountId: _selectedAccountId!,
        date: _selectedDate,
        valueDate: _selectedDate,
        comment: drift.Value(parentNote.isNotEmpty ? parentNote : 'Split Transaction'),
        status: const drift.Value(1), // 1 indicates split parent
      );

      final splitCompanions = _splitItems.map((item) {
        final splitPaise = (item.amount * 100).round();
        final splitNote = item.noteController.text.trim();
        return TransactionsCompanion.insert(
          amount: -splitPaise.abs(),
          accountId: _selectedAccountId!,
          date: _selectedDate,
          valueDate: _selectedDate,
          comment: drift.Value(splitNote.isNotEmpty ? splitNote : 'Split Item'),
          catId: drift.Value(item.categoryId),
        );
      }).toList();

      await db.createSplitTransaction(
        parent: parentCompanion,
        splits: splitCompanions,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.income,
            content: Text('Saved split transaction of ₹${parentRupees.toStringAsFixed(2)} with ${_splitItems.length} items'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Error saving split transaction: $e'),
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

    if (_selectedAccountId == null && accounts.isNotEmpty) {
      _selectedAccountId = accounts.first.id;
    }

    final diff = _remainingDifference;
    final isBalanced = (diff.abs() * 100).round() == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Split Transaction', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check_rounded),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account & Date Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Account selector
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 20),
                        const SizedBox(width: 12),
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
                                  decoration: InputDecoration(
                                    labelText: 'Account',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: accounts.map((acc) {
                                    return DropdownMenuItem<int>(
                                      value: acc.id,
                                      child: Text(acc.label),
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
                    const SizedBox(height: 12),

                    // Date & Note
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _parentNoteController,
                            decoration: InputDecoration(
                              labelText: 'Overall Description',
                              hintText: 'e.g. Supermarket Bill, Dinner Party',
                              prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _pickDateTime,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
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
            ),

            const SizedBox(height: 16),

            // Summary & Balancing Card
            Card(
              elevation: 0,
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isBalanced
                      ? AppColors.income.withOpacity(0.4)
                      : AppColors.expense.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL AMOUNT',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${_parentTotalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.expense,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('Auto Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Switch(
                              value: _autoCalculateTotal,
                              onChanged: (val) {
                                setState(() {
                                  _autoCalculateTotal = val;
                                  if (!val) {
                                    _totalAmountController.text = _totalSplitsSum.toStringAsFixed(2);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    if (!_autoCalculateTotal) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _totalAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Target Total Bill (₹)',
                          prefixText: '₹ ',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Allocated: ₹${_totalSplitsSum.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isBalanced ? AppColors.income.withOpacity(0.12) : AppColors.expense.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isBalanced
                                  ? '✓ Balanced'
                                  : (diff > 0
                                      ? '₹${diff.toStringAsFixed(2)} Remaining'
                                      : '₹${(-diff).toStringAsFixed(2)} Over-allocated'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isBalanced ? AppColors.income : AppColors.expense,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Split items list header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Split Allocations (${_splitItems.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  onPressed: () {
                    final remainder = _autoCalculateTotal ? null : (_remainingDifference > 0 ? _remainingDifference : null);
                    _addSplitItem(defaultAmount: remainder);
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Split'),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // List of Split Items
            ..._splitItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // Split Index badge
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primary.withOpacity(0.12),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Sub-item note
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: item.noteController,
                          decoration: InputDecoration(
                            hintText: 'Item / Category note',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Sub-item amount
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: item.amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            hintText: '0.00',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),

                      // Delete button
                      if (_splitItems.length > 1) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.expense, size: 20),
                          onPressed: () => _removeSplitItem(index),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.expense,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  'Save Split (${CurrencyFormatter.formatPaiseAbsolute((_parentTotalAmount * 100).round())})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
