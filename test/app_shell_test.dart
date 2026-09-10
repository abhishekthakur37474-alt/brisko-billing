import 'package:brisko_billing/app/bootstrap.dart';
import 'package:brisko_billing/app/brisko_app.dart';
import 'package:brisko_billing/app/shell/pos_section.dart';
import 'package:brisko_billing/core/data/local/sqlite/sqlite_database.dart';
import 'package:brisko_billing/core/data/local/sqlite/sqlite_outbox_store.dart';
import 'package:brisko_billing/features/customers/data/repositories/sqlite_customer_repository.dart';
import 'package:brisko_billing/features/inventory/data/repositories/sqlite_inventory_repository.dart';
import 'package:brisko_billing/features/kot/data/repositories/sqlite_kot_repository.dart';
import 'package:brisko_billing/features/menu/data/repositories/sqlite_menu_repository.dart';
import 'package:brisko_billing/features/orders/data/repositories/sqlite_order_repository.dart';
import 'package:brisko_billing/features/payments/data/repositories/sqlite_payment_repository.dart';
import 'package:brisko_billing/features/settings/data/repositories/sqlite_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

/// Builds the dependency graph against an in-memory database.
///
/// The widget tests drive the real repositories rather than fakes, because the
/// shell has to be able to construct them. Nothing here writes to a real database
/// file.
Future<AppDependencies> _testDependencies() async {
  final SqliteDatabase database = await TestDatabase.openInMemory();

  return AppDependencies(
    database: database,
    outbox: SqliteOutboxStore(database: database),
    menuRepository: SqliteMenuRepository(database: database),
    orderRepository: SqliteOrderRepository(database: database),
    customerRepository: SqliteCustomerRepository(database: database),
    paymentRepository: SqlitePaymentRepository(database: database),
    inventoryRepository: SqliteInventoryRepository(database: database),
    kotRepository: SqliteKotRepository(database: database),
    settingsRepository: SqliteSettingsRepository(database: database),
  );
}

void main() {
  setUpAll(TestDatabase.register);

  late AppDependencies dependencies;

  setUp(() async {
    dependencies = await _testDependencies();
  });

  tearDown(() async {
    await dependencies.dispose();
  });

  group('PosShell', () {
    testWidgets('starts on the dashboard section', (WidgetTester tester) async {
      await tester.pumpWidget(BriskoApp(dependencies: dependencies));

      // Title in the app bar, plus the heading rendered by the placeholder.
      expect(find.text(PosSection.dashboard.label), findsWidgets);
    });

    testWidgets('navigating the rail swaps the active section', (
      WidgetTester tester,
    ) async {
      // Wide enough to render the navigation rail rather than the bottom bar.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(BriskoApp(dependencies: dependencies));

      expect(find.byType(NavigationRail), findsOneWidget);

      await tester.tap(find.text(PosSection.reports.label));
      await tester.pumpAndSettle();

      expect(find.text(PosSection.reports.label), findsWidgets);
      expect(find.text(PosSection.dashboard.label), findsOneWidget);
    });
  });
}
