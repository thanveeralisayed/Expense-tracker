import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:expense_tracker/main.dart';
import 'package:expense_tracker/core/providers/database_provider.dart';
import 'package:expense_tracker/core/database/database.dart';

import 'package:google_fonts/google_fonts.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App boots cleanly and renders Dashboard', (WidgetTester tester) async {
    final mockDb = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(mockDb),
        ],
        child: const ExpenseTrackerApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify App Bar Title
    expect(find.text('My Expenses'), findsOneWidget);
    // Verify Total Balance Card exists
    expect(find.text('TOTAL NET WORTH'), findsOneWidget);

    await mockDb.close();
  });
}
