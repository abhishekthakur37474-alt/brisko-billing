import 'package:flutter/widgets.dart';

import '../core/data/local/sqlite/sqlite_database.dart';
import '../core/data/local/sqlite/sqlite_outbox_store.dart';
import '../features/customers/data/repositories/sqlite_customer_repository.dart';
import '../features/customers/domain/repositories/customer_repository.dart';
import '../features/inventory/data/repositories/sqlite_inventory_repository.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/kot/data/repositories/sqlite_kot_repository.dart';
import '../features/kot/domain/repositories/kot_repository.dart';
import '../features/menu/data/repositories/sqlite_menu_repository.dart';
import '../features/menu/domain/repositories/menu_repository.dart';
import '../features/orders/data/repositories/sqlite_order_repository.dart';
import '../features/orders/domain/repositories/order_repository.dart';
import '../features/payments/data/repositories/sqlite_payment_repository.dart';
import '../features/payments/domain/repositories/payment_repository.dart';
import '../features/settings/data/repositories/sqlite_settings_repository.dart';
import '../features/settings/domain/repositories/settings_repository.dart';

/// Everything the application needs, constructed once at start-up.
///
/// Repositories are exposed through their abstract types, so nothing downstream can
/// reach the SQLite implementations even by accident.
class AppDependencies {
  const AppDependencies({
    required this.database,
    required this.outbox,
    required this.menuRepository,
    required this.orderRepository,
    required this.customerRepository,
    required this.paymentRepository,
    required this.inventoryRepository,
    required this.kotRepository,
    required this.settingsRepository,
  });

  final SqliteDatabase database;

  /// Durable upload queue. Implemented and available, but not yet attached to the
  /// stores, because nothing drains it until a backend exists.
  final SqliteOutboxStore outbox;

  final MenuRepository menuRepository;
  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;
  final PaymentRepository paymentRepository;
  final InventoryRepository inventoryRepository;
  final KotRepository kotRepository;
  final SettingsRepository settingsRepository;

  Future<void> dispose() async {
    await outbox.dispose();
    await database.close();
  }
}

/// Opens the database, runs migrations and builds the dependency graph.
///
/// Start-up is explicit and ordered rather than lazy: the database must be open and
/// migrated before any repository is constructed, and a failure here should surface
/// at launch rather than halfway through a bill.
///
/// Pass [databasePath] to point at a different file, which is what tests use.
Future<AppDependencies> bootstrap({String? databasePath}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final SqliteDatabase database = SqliteDatabase();
  await database.open(path: databasePath);

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
