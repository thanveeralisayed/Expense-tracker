import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'auto_categorize_wizard_sheet.dart';
import 'edit_category_dialog.dart';
import 'widgets/category_icon_helper.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final usageCountsAsync = ref.watch(categoryUsageCountsProvider);
    final uncategorizedCountAsync = ref.watch(uncategorizedCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // Auto-Categorizer Wizard action with badge
          uncategorizedCountAsync.when(
            data: (count) => count > 0
                ? IconButton(
                    tooltip: 'Auto-Categorize ($count uncategorized)',
                    icon: Badge(
                      label: Text('$count'),
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.auto_awesome_rounded),
                    ),
                    onPressed: () => AutoCategorizeWizardSheet.show(context),
                  )
                : IconButton(
                    tooltip: 'Auto-Categorize Wizard',
                    icon: const Icon(Icons.auto_awesome_rounded),
                    onPressed: () => AutoCategorizeWizardSheet.show(context),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          IconButton(
            tooltip: 'Add Category',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => EditCategoryDialog.show(context, defaultType: _tabController.index),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'Expense', icon: Icon(Icons.arrow_downward_rounded, size: 16)),
            Tab(text: 'Income', icon: Icon(Icons.arrow_upward_rounded, size: 16)),
          ],
        ),
      ),
      body: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.category_outlined, size: 64, color: AppColors.primary),
                    const SizedBox(height: 16),
                    const Text(
                      'No Categories Found',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Get started by seeding our curated standard category set or create your own.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(databaseProvider).seedDefaultCategoriesIfEmpty();
                      },
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Add Standard Categories'),
                    ),
                  ],
                ),
              ),
            );
          }

          final usageCounts = usageCountsAsync.value ?? {};
          final uncategorizedCount = uncategorizedCountAsync.value ?? 0;

          return TabBarView(
            controller: _tabController,
            children: [
              _buildCategoryList(
                categories: categories.where((c) => c.type == 0).toList(),
                usageCounts: usageCounts,
                isDark: isDark,
                uncategorizedCount: uncategorizedCount,
                type: 0,
              ),
              _buildCategoryList(
                categories: categories.where((c) => c.type == 1).toList(),
                usageCounts: usageCounts,
                isDark: isDark,
                uncategorizedCount: uncategorizedCount,
                type: 1,
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading categories: $err')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => EditCategoryDialog.show(context, defaultType: _tabController.index),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Category'),
      ),
    );
  }

  Widget _buildCategoryList({
    required List<Category> categories,
    required Map<int, int> usageCounts,
    required bool isDark,
    required int uncategorizedCount,
    required int type,
  }) {
    // Group into root parents (parentId == null) and subcategories
    final rootCategories = categories.where((c) => c.parentId == null).toList();
    final subcategoriesMap = <int, List<Category>>{};

    for (final cat in categories) {
      if (cat.parentId != null) {
        subcategoriesMap.putIfAbsent(cat.parentId!, () => []).add(cat);
      }
    }

    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 84),
      children: [
        // Uncategorized Transactions Banner (only show once on Expense tab if count > 0)
        if (type == 0 && uncategorizedCount > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.primary.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$uncategorizedCount Uncategorized Entries',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text(
                          'Tap to run auto-categorizer on legacy notes',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => AutoCategorizeWizardSheet.show(context),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Scan & Fix'),
                  ),
                ],
              ),
            ),
          ),

        // Categories List
        ...rootCategories.map((parent) {
          final children = subcategoriesMap[parent.id] ?? [];
          final count = usageCounts[parent.id] ?? 0;
          final color = Color(parent.color ?? 0xFF10B981);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: children.isNotEmpty,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(CategoryIconHelper.getIcon(parent.icon), color: color, size: 20),
                ),
                title: Text(
                  parent.label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  children.isNotEmpty
                      ? '${children.length} subcategories • $count transactions'
                      : '$count transactions',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Edit Category',
                      onPressed: () => EditCategoryDialog.show(context, category: parent),
                    ),
                    if (children.isNotEmpty) const Icon(Icons.expand_more_rounded),
                  ],
                ),
                children: children.map((sub) {
                  final subCount = usageCounts[sub.id] ?? 0;
                  final subColor = Color(sub.color ?? parent.color ?? 0xFF10B981);

                  return ListTile(
                    contentPadding: const EdgeInsets.only(left: 48, right: 16),
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: subColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(CategoryIconHelper.getIcon(sub.icon), color: subColor, size: 16),
                    ),
                    title: Text(sub.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '$subCount transactions',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      tooltip: 'Edit Subcategory',
                      onPressed: () => EditCategoryDialog.show(context, category: sub),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }
}
