import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/category_icon_helper.dart';

class EditCategoryDialog extends ConsumerStatefulWidget {
  final Category? category;
  final int defaultType; // 0 = Expense, 1 = Income

  const EditCategoryDialog({
    super.key,
    this.category,
    this.defaultType = 0,
  });

  static Future<Category?> show(BuildContext context, {Category? category, int defaultType = 0}) {
    return showDialog<Category?>(
      context: context,
      builder: (_) => EditCategoryDialog(category: category, defaultType: defaultType),
    );
  }

  @override
  ConsumerState<EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends ConsumerState<EditCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _labelController;
  late int _type; // 0 = Expense, 1 = Income
  int? _parentId;
  late int _color;
  late String _icon;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.category?.label ?? '');
    _type = widget.category?.type ?? widget.defaultType;
    _parentId = widget.category?.parentId;
    _color = widget.category?.color ?? CategoryIconHelper.palette.first;
    _icon = widget.category?.icon ?? 'shopping_cart';
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final icons = CategoryIconHelper.iconMap.entries.toList();

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.85,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Icon',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: icons.length,
                    itemBuilder: (_, index) {
                      final item = icons[index];
                      final isSelected = item.key == _icon;

                      return InkWell(
                        onTap: () {
                          setState(() => _icon = item.key);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(_color).withValues(alpha: 0.25)
                                : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant),
                            border: isSelected ? Border.all(color: Color(_color), width: 2) : null,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            item.value,
                            color: isSelected ? Color(_color) : (isDark ? Colors.white70 : Colors.black87),
                            size: 24,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final db = ref.read(databaseProvider);
    final label = _labelController.text.trim();

    try {
      if (widget.category == null) {
        // Create new
        final id = await db.createCategory(
          CategoriesCompanion.insert(
            label: label,
            type: drift.Value(_type),
            parentId: drift.Value(_parentId),
            color: drift.Value(_color),
            icon: drift.Value(_icon),
          ),
        );
        final created = (await db.getAllCategories()).firstWhere((c) => c.id == id);
        if (mounted) Navigator.pop(context, created);
      } else {
        // Update existing
        final updated = widget.category!.copyWith(
          label: label,
          type: _type,
          parentId: drift.Value(_parentId),
          color: drift.Value(_color),
          icon: drift.Value(_icon),
        );
        await db.updateCategory(updated);
        if (mounted) Navigator.pop(context, updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.expense,
            content: Text('Error saving category: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category?'),
        content: Text(
          'Are you sure you want to delete "${widget.category!.label}"? Any transactions assigned to this category will become uncategorized.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final db = ref.read(databaseProvider);
      await db.deleteCategory(widget.category!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.category != null;
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Color(_color).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(CategoryIconHelper.getIcon(_icon), color: Color(_color), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit Category' : 'New Category',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.expense),
                        tooltip: 'Delete Category',
                        onPressed: _delete,
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Type Toggle (Expense vs Income)
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Expense'), icon: Icon(Icons.arrow_downward_rounded, size: 16)),
                    ButtonSegment(value: 1, label: Text('Income'), icon: Icon(Icons.arrow_upward_rounded, size: 16)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (set) {
                    setState(() {
                      _type = set.first;
                      _parentId = null; // Reset parent if type switches
                    });
                  },
                ),
                const SizedBox(height: 18),

                // Category Name
                TextFormField(
                  controller: _labelController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g. Groceries, Gym, Salary',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Please enter a name';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Parent Category Dropdown (for subcategories)
                categoriesAsync.when(
                  data: (allCategories) {
                    final validParents = allCategories
                        .where((c) => c.type == _type && c.parentId == null && (widget.category == null || c.id != widget.category!.id))
                        .toList();

                    return DropdownButtonFormField<int?>(
                      initialValue: _parentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Parent Category (Optional)',
                        hintText: 'None (Top-Level Category)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('None (Top-Level Category)')),
                        ...validParents.map(
                          (p) => DropdownMenuItem<int?>(
                            value: p.id,
                            child: Row(
                              children: [
                                Icon(CategoryIconHelper.getIcon(p.icon), size: 18, color: p.color != null ? Color(p.color!) : null),
                                const SizedBox(width: 8),
                                Text(p.label),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) => setState(() => _parentId = val),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 18),

                // Icon & Color Selection Row
                Row(
                  children: [
                    // Icon selector button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _showIconPicker,
                      icon: Icon(CategoryIconHelper.getIcon(_icon), size: 20, color: Color(_color)),
                      label: const Text('Change Icon'),
                    ),
                    const SizedBox(width: 14),
                    const Text('Color Palette:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 12),

                // Color Palette Grid
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: CategoryIconHelper.palette.map((c) {
                    final isSelected = c == _color;
                    return InkWell(
                      onTap: () => setState(() => _color = c),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                          boxShadow: isSelected
                              ? [BoxShadow(color: Color(c).withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
                              : null,
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _isLoading ? null : _save,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEditing ? 'Save Changes' : 'Create Category'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
