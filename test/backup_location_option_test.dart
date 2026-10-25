// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:expense_tracker/features/settings/presentation/settings_screen.dart';
import 'package:expense_tracker/core/database/database.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = FakePathProviderPlatform();
  });

  testWidgets('Settings screen: tapping Export Full Backup shows options to save anywhere in phone storage or app data folder', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. Find and tap "Export Full Backup (.zip)"
    final backupTile = find.text('Export Full Backup (.zip)');
    expect(backupTile, findsOneWidget);
    await tester.tap(backupTile);
    await tester.pumpAndSettle();

    // 2. Verify modal bottom sheet presents options to user
    expect(find.text('Export Full Backup'), findsWidgets);
    expect(find.text('Save to Phone Storage (Select Location)'), findsOneWidget);
    expect(find.text('Choose any folder in internal memory (Downloads, Documents, etc.)'), findsOneWidget);
    expect(find.text('Save to App Data Folder'), findsOneWidget);
    expect(find.text('Store inside the app\'s internal documents folder'), findsOneWidget);

    // 3. Tap "Save to App Data Folder"
    await tester.runAsync(() async {
      await tester.tap(find.text('Save to App Data Folder'));
      await Future.delayed(const Duration(milliseconds: 1000));
    });
    await tester.pumpAndSettle();

    // 4. Verify SnackBar confirmation appears
    expect(find.textContaining('Backup archive created in app data folder'), findsOneWidget);

    await mockDb.close();
  });

  testWidgets('Settings screen: tapping Export to CSV shows options to save anywhere in phone storage or app data folder', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. Find and tap "Export to CSV Spreadsheet"
    final csvTile = find.text('Export to CSV Spreadsheet');
    expect(csvTile, findsOneWidget);
    await tester.tap(csvTile);
    await tester.pumpAndSettle();

    // 2. Verify modal bottom sheet presents options to user
    expect(find.text('Export Transactions to CSV'), findsOneWidget);
    expect(find.text('Save to Phone Storage (Select Location)'), findsOneWidget);
    expect(find.text('Choose any folder in internal memory (Downloads, Documents, etc.)'), findsOneWidget);
    expect(find.text('Save to App Data Folder'), findsOneWidget);
    expect(find.text('Store inside the app\'s internal documents folder'), findsOneWidget);

    // 3. Tap "Save to App Data Folder"
    await tester.runAsync(() async {
      await tester.tap(find.text('Save to App Data Folder'));
      await Future.delayed(const Duration(milliseconds: 1000));
    });
    await tester.pumpAndSettle();

    // 4. Verify SnackBar confirmation appears
    expect(find.textContaining('Exported 0 transactions to CSV in app folder'), findsOneWidget);

    await mockDb.close();
  });
}
