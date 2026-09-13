import 'package:flutter/widgets.dart';

import '../core/data/local/sqlite/sqlite_database.dart';
import '../core/data/local/sqlite/sqlite_outbox_store.dart';
import '../features/billing/data/repositories/sqlite_checkout_repository.dart';
import '../features/billing/data/repositories/sqlite_held_bill_repository.dart';
import '../features/billing/domain/repositories/checkout_repository.dart';
import '../features/billing/domain/repositories/held_bill_repository.dart';
import '../features/customers/data/repositories/sqlite_customer_repository.dart';
import '../features/customers/domain/repositories/customer_repository.dart';
import '../features/inventory/data/repositories/sqlite_inventory_deduction_repository.dart';
import '../features/inventory/data/repositories/sqlite_inventory_repository.dart';
import '../features/inventory/data/repositories/sqlite_recipe_repository.dart';
import '../features/inventory/domain/repositories/inventory_deduction_repository.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/domain/repositories/recipe_repository.dart';
import '../features/kot/data/repositories/sqlite_kot_repository.dart';
import '../features/kot/domain/repositories/kot_repository.dart';
import '../features/menu/data/repositories/sqlite_menu_repository.dart';
import '../features/menu/domain/repositories/menu_repository.dart';
import '../features/orders/data/repositories/sqlite_order_repository.dart';
import '../features/orders/domain/repositories/order_repository.dart';
import '../features/payments/data/repositories/sqlite_payment_repository.dart';
import '../features/payments/data/repositories/sqlite_refund_repository.dart';
import '../features/payments/domain/repositories/payment_repository.dart';
import '../features/payments/domain/repositories/refund_repository.dart';
import '../features/printing/data/default_print_service.dart';
import '../features/printing/data/escpos/configurable_escpos_encoder.dart';
import '../features/printing/data/printers/unconfigured_thermal_printer.dart';
import '../features/printing/data/repository_sale_print_document_source.dart';
import '../features/printing/data/settings_business_identity_source.dart';
import '../features/printing/domain/models/print_settings.dart';
import '../features/printing/domain/printers/thermal_printer.dart';
import '../features/printing/domain/services/active_print_profile.dart';
import '../features/printing/domain/services/print_job_factory.dart';
import '../features/printing/domain/services/print_service.dart';
import '../features/reports/data/repositories/sqlite_sales_report_repository.dart';
import '../features/reports/domain/repositories/sales_report_repository.dart';
import '../features/settings/data/repositories/sqlite_settings_repository.dart';
import '../features/settings/domain/active_pos_settings.dart';
import '../features/settings/domain/models/pos_settings.dart';
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
    required this.checkoutRepository,
    required this.heldBillRepository,
    required this.customerRepository,
    required this.paymentRepository,
    required this.refundRepository,
    required this.inventoryRepository,
    required this.recipeRepository,
    required this.inventoryDeductionRepository,
    required this.kotRepository,
    required this.salesReportRepository,
    required this.settingsRepository,
    required this.activeSettings,
    required this.printer,
    required this.activePrintProfile,
    required this.printService,
  });

  final SqliteDatabase database;

  /// Durable upload queue. Implemented and available, but not yet attached to the
  /// stores, because nothing drains it until a backend exists.
  final SqliteOutboxStore outbox;

  final MenuRepository menuRepository;
  final OrderRepository orderRepository;

  /// Writes a settled bill across the order and payment tables in one transaction.
  /// Separate from [orderRepository] because neither repository alone can make that
  /// write atomic.
  final CheckoutRepository checkoutRepository;

  /// Puts a bill aside at the counter and brings it back. Separate from
  /// [checkoutRepository] because holding a bill commits to nothing: no order number, no
  /// payment, no kitchen slip. See `M007HeldBills`.
  final HeldBillRepository heldBillRepository;

  final CustomerRepository customerRepository;
  final PaymentRepository paymentRepository;

  /// Hands money back on a settled bill, and reads what a bill could have refunded.
  ///
  /// Separate from [paymentRepository] because it is not a write of a payment: deciding a
  /// refund means reading the order's status, the bill's settled tenders and any reversal
  /// already recorded, all inside the transaction that writes the new row. A repository
  /// whose writes are whole-entity upserts cannot make that atomic. See
  /// [RefundRepository].
  final RefundRepository refundRepository;

  final InventoryRepository inventoryRepository;

  /// Links a dish to the stock it consumes. Read by the deduction and edited on the
  /// recipe screen; nothing in billing or printing touches it.
  final RecipeRepository recipeRepository;

  /// Takes a settled bill's ingredients off the shelf.
  ///
  /// Separate from [inventoryRepository] and from [checkoutRepository] because it is
  /// neither: it runs strictly after the money has committed, in its own transaction,
  /// so a shelf that is short can never roll a payment back. See
  /// [InventoryDeductionRepository].
  final InventoryDeductionRepository inventoryDeductionRepository;

  final KotRepository kotRepository;

  /// Aggregates over settled bills for the Reports screen.
  ///
  /// Separate from [orderRepository] because a report is a grouped query rather than a
  /// collection of entities: totalling a month by reading its orders into memory would be
  /// the wrong shape of work, and item-wise sales would mean reading every line of every
  /// bill. It is read-only, so no report can alter a bill.
  final SalesReportRepository salesReportRepository;

  final SettingsRepository settingsRepository;

  /// The configuration this terminal is running with, read once at start-up.
  ///
  /// Held in memory because settlement needs the default order type at the moment a
  /// screen is built, and a widget cannot await a database read while it builds. The
  /// table stays the source of truth; the Settings screen replaces this after a save
  /// commits, so a change takes effect on the next bill rather than the next launch.
  final ActivePosSettings activeSettings;

  /// The terminal's thermal printer.
  ///
  /// An [UnconfiguredThermalPrinter] in this build, because the 80mm ESC/POS printer
  /// has been chosen but not bought. It reports itself as unavailable and fails every
  /// print with a message naming what would fix it, which means the settled-but-not-
  /// printed path is exercised in production rather than waiting for hardware.
  ///
  /// Swapping in a USB or LAN adapter is a change to this one line.
  final ThermalPrinter printer;

  /// The layout documents are encoded for, and the one thing about printing the operator
  /// can change while the application is running.
  ///
  /// The same object as the encoder inside [printService], deliberately: a correction
  /// saved on the Settings screen has to reach the encoder that lays out the next bill,
  /// and holding two copies of a column count is how they come to disagree.
  final ActivePrintProfile activePrintProfile;

  /// Builds and prints the paperwork for a settled sale.
  ///
  /// Separate from [printer] because it coordinates reads across four repositories and
  /// reports per-document outcomes, none of which is a printer's business.
  final PrintService printService;

  Future<void> dispose() async {
    await printer.dispose();
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

  final SqliteOrderRepository orders = SqliteOrderRepository(
    database: database,
  );
  final SqlitePaymentRepository payments = SqlitePaymentRepository(
    database: database,
  );
  final SqliteKotRepository kots = SqliteKotRepository(database: database);
  final SqliteCustomerRepository customers = SqliteCustomerRepository(
    database: database,
  );
  final SqliteSettingsRepository settings = SqliteSettingsRepository(
    database: database,
  );

  // No printer has been bought yet, so the terminal honestly has none. Everything
  // above this line is already written against `ThermalPrinter`, so connecting one
  // later replaces this single construction.
  final ThermalPrinter printer = UnconfiguredThermalPrinter();

  // The stored configuration, read once, before the first frame. A failure here is not
  // fatal: an unreadable settings table means an unconfigured terminal, which prints its
  // own name, claims no GSTIN and lays documents out for the printer's own profile. The
  // Settings screen reads the table again and reports the failure properly.
  final Map<String, String?> stored =
      (await settings.readAll()).valueOrNull ?? const <String, String?>{};

  final ActivePosSettings activeSettings = ActivePosSettings(
    settings: PosSettings.fromStored(stored),
  );

  // The encoder holds the profile rather than being handed a fixed one, so that a
  // corrected column count saved on the Settings screen lays out the next bill instead of
  // waiting for a restart. It is both the encoder and the profile the application exposes,
  // which is what stops the two disagreeing.
  final ConfigurableEscPosEncoder encoder =
      ConfigurableEscPosEncoder.forPrinter(
        printer,
        settings: PrintSettings.fromStored(stored, fallback: printer.profile),
      );

  return AppDependencies(
    database: database,
    outbox: SqliteOutboxStore(database: database),
    menuRepository: SqliteMenuRepository(database: database),
    orderRepository: orders,
    checkoutRepository: SqliteCheckoutRepository(database: database),
    heldBillRepository: SqliteHeldBillRepository(database: database),
    customerRepository: customers,
    paymentRepository: payments,
    refundRepository: SqliteRefundRepository(database: database),
    inventoryRepository: SqliteInventoryRepository(database: database),
    recipeRepository: SqliteRecipeRepository(database: database),
    inventoryDeductionRepository: SqliteInventoryDeductionRepository(
      database: database,
    ),
    kotRepository: kots,
    salesReportRepository: SqliteSalesReportRepository(database: database),
    settingsRepository: settings,
    activeSettings: activeSettings,
    printer: printer,
    activePrintProfile: encoder,
    printService: DefaultPrintService(
      printer: printer,
      // The encoder starts from the printer's own profile, so the layout the documents
      // are encoded for is by construction the layout of the printer they are sent to.
      // When a real 80mm device turns out to print a different number of columns, the
      // correction is saved in Settings and every document narrows with it.
      jobs: PrintJobFactory(encoder: encoder),
      documents: RepositorySalePrintDocumentSource(
        orders: orders,
        payments: payments,
        kots: kots,
        customers: customers,
        // Business details, GSTIN and the UPI address all come from settings. None of
        // them has a hard-coded value anywhere in the printing layer.
        identity: SettingsBusinessIdentitySource(settings: settings),
      ),
    ),
  );
}
