import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';

import 'package:expense_tracker/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Category Lifecycle, Taxonomy Hierarchy & Safeguards', () {
    test('seedDefaultCategoriesIfEmpty seeds standard set on fresh database', () async {
      final initial = await db.getAllCategories();
      expect(initial, isEmpty);

      await db.seedDefaultCategoriesIfEmpty();
      final seeded = await db.getAllCategories();
      expect(seeded.length, greaterThanOrEqualTo(15));

      // Verify Expense and Income both present
      final expenseCats = seeded.where((c) => c.type == 0).toList();
      final incomeCats = seeded.where((c) => c.type == 1).toList();
      expect(expenseCats, isNotEmpty);
      expect(incomeCats, isNotEmpty);

      // Verify idempotent: running again does not duplicate
      await db.seedDefaultCategoriesIfEmpty();
      final reseeded = await db.getAllCategories();
      expect(reseeded.length, equals(seeded.length));
    });

    test('Create custom parent category and nested subcategory', () async {
      final parentId = await db.createCategory(
        const CategoriesCompanion(
          label: drift.Value('Vehicle Expenses'),
          type: drift.Value(0),
          color: drift.Value(0xFFEF4444),
          icon: drift.Value('directions_car'),
        ),
      );

      final childId = await db.createCategory(
        CategoriesCompanion(
          label: const drift.Value('Toll & Parking'),
          type: const drift.Value(0),
          parentId: drift.Value(parentId),
          color: const drift.Value(0xFFDC2626),
          icon: const drift.Value('local_parking'),
        ),
      );

      final all = await db.getAllCategories();
      final child = all.firstWhere((c) => c.id == childId);
      expect(child.parentId, equals(parentId));
      expect(child.label, equals('Toll & Parking'));
    });

    test('Update existing category properties', () async {
      final id = await db.createCategory(
        const CategoriesCompanion(
          label: drift.Value('Gym & Health'),
          type: drift.Value(0),
          color: drift.Value(0xFF10B981),
          icon: drift.Value('fitness_center'),
        ),
      );

      final created = (await db.getAllCategories()).firstWhere((c) => c.id == id);
      final updated = created.copyWith(
        label: 'Fitness & Sports',
        color: const drift.Value(0xFF059669),
        icon: const drift.Value('sports_gymnastics'),
      );

      final success = await db.updateCategory(updated);
      expect(success, isTrue);

      final fetched = (await db.getAllCategories()).firstWhere((c) => c.id == id);
      expect(fetched.label, equals('Fitness & Sports'));
      expect(fetched.color, equals(0xFF059669));
    });

    test('Cascade safeguard on parent deletion: subcategories unlinked, not deleted', () async {
      final parentId = await db.createCategory(
        const CategoriesCompanion(
          label: drift.Value('Parent Category'),
          type: drift.Value(0),
        ),
      );

      final childId = await db.createCategory(
        CategoriesCompanion(
          label: const drift.Value('Child Subcategory'),
          type: const drift.Value(0),
          parentId: drift.Value(parentId),
        ),
      );

      // Delete parent
      await db.deleteCategory(parentId);

      final all = await db.getAllCategories();
      // Parent is deleted
      expect(all.any((c) => c.id == parentId), isFalse);
      // Child still exists, but parentId is now null
      final child = all.firstWhere((c) => c.id == childId);
      expect(child.parentId, isNull);
    });

    test('Cascade safeguard on category deletion: transactions unlinked, not deleted', () async {
      // 1. Create account & category
      final accId = await db.createAccount(
        const AccountsCompanion(label: drift.Value('Wallet')),
      );
      final catId = await db.createCategory(
        const CategoriesCompanion(label: drift.Value('Groceries')),
      );

      // 2. Insert transaction with catId
      final txId = await db.createTransaction(
        TransactionsCompanion.insert(
          amount: -50000,
          accountId: accId,
          date: DateTime.now(),
          valueDate: DateTime.now(),
          comment: const drift.Value('Weekly vegetables'),
          catId: drift.Value(catId),
        ),
      );

      // 3. Delete category
      await db.deleteCategory(catId);

      // 4. Verify transaction still exists with catId unlinked to null
      final txList = await db.watchTransactions().first;
      final tx = txList.firstWhere((t) => t.id == txId);
      expect(tx, isNotNull);
      expect(tx.catId, isNull);
      expect(tx.amount, equals(-50000));
    });

    test('Usage count tracking and batch categorization', () async {
      final accId = await db.createAccount(
        const AccountsCompanion(label: drift.Value('Main Bank')),
      );
      final catId1 = await db.createCategory(
        const CategoriesCompanion(label: drift.Value('Groceries')),
      );
      final catId2 = await db.createCategory(
        const CategoriesCompanion(label: drift.Value('Fuel')),
      );

      // Create 3 uncategorized transactions
      final now = DateTime.now();
      final txId1 = await db.createTransaction(
        TransactionsCompanion.insert(
          amount: -25000,
          accountId: accId,
          date: now,
          valueDate: now,
          comment: const drift.Value('Milk'),
        ),
      );
      final txId2 = await db.createTransaction(
        TransactionsCompanion.insert(
          amount: -100000,
          accountId: accId,
          date: now,
          valueDate: now,
          comment: const drift.Value('Petrol'),
        ),
      );
      final txId3 = await db.createTransaction(
        TransactionsCompanion.insert(
          amount: -30000,
          accountId: accId,
          date: now,
          valueDate: now,
          comment: const drift.Value('Bread & Butter'),
        ),
      );

      // Verify all 3 are uncategorized
      final uncategorizedBefore = await db.getUncategorizedTransactions();
      expect(uncategorizedBefore.length, equals(3));

      // Batch categorize tx1 -> Groceries, tx2 -> Fuel, tx3 -> Groceries
      await db.batchUpdateTransactionCategories({
        txId1: catId1,
        txId2: catId2,
        txId3: catId1,
      });

      // Verify uncategorized list is now empty
      final uncategorizedAfter = await db.getUncategorizedTransactions();
      expect(uncategorizedAfter, isEmpty);

      // Verify usage counts: Groceries = 2, Fuel = 1
      final counts = await db.getCategoryUsageCounts();
      expect(counts[catId1], equals(2));
      expect(counts[catId2], equals(1));
    });
  });
}
