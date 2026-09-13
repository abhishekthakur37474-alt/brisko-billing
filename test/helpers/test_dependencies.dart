import 'package:brisko_billing/app/bootstrap.dart';
import 'package:brisko_billing/core/data/local/sqlite/sqlite_database.dart';
import 'package:brisko_billing/core/data/local/sqlite/sqlite_outbox_store.dart';
import 'package:brisko_billing/features/billing/data/repositories/sqlite_checkout_repository.dart';
import 'package:brisko_billing/features/billing/data/repositories/sqlite_held_bill_repository.dart';
import 'package:brisko_billing/features/billing/domain/repositories/held_bill_repository.dart';
import 'package:brisko_billing/features/customers/data/repositories/sqlite_customer_repository.dart';
import 'package:brisko_billing/features/inventory/data/repositories/sqlite_inventory_deduction_repository.dart';
import 'package:brisko_billing/features/inventory/data/repositories/sqlite_inventory_repository.dart';
import 'package:brisko_billing/features/inventory/data/repositories/sqlite_recipe_repository.dart';
import 'package:brisko_billing/features/kot/data/repositories/sqlite_kot_repository.dart';
import 'package:brisko_billing/features/menu/data/repositories/sqlite_menu_repository.dart';
import 'package:brisko_billing/features/orders/data/repositories/sqlite_order_repository.dart';
import 'package:brisko_billing/features/payments/data/repositories/sqlite_payment_repository.dart';
import 'package:brisko_billing/features/payments/data/repositories/sqlite_refund_repository.dart';
import 'package:brisko_billing/features/payments/domain/repositories/refund_repository.dart';
import 'package:brisko_billing/features/printing/data/escpos/configurable_escpos_encoder.dart';
import 'package:brisko_billing/features/printing/data/printers/unconfigured_thermal_printer.dart';
import 'package:brisko_billing/features/printing/domain/models/print_settings.dart';
import 'package:brisko_billing/features/printing/domain/printers/thermal_printer.dart';
import 'package:brisko_billing/features/reports/data/repositories/sqlite_sales_report_repository.dart';
import 'package:brisko_billing/features/reports/domain/repositories/sales_report_repository.dart';
import 'package:brisko_billing/features/settings/data/repositories/sqlite_settings_repository.dart';
import 'package:brisko_billing/features/settings/domain/active_pos_settings.dart';
import 'package:brisko_billing/features/settings/domain/models/pos_settings.dart';
import 'package:brisko_billing/features/settings/domain/repositories/settings_repository.dart';

import 'test_printing.dart';

/// The production dependency graph over an already-open test database.
///
/// Every repository is the real one. Only the printer is substituted, because no
/// hardware exists, and by default with the same [UnconfiguredThermalPrinter] the
/// production bootstrap builds — which is the state of every terminal today.
///
/// Written once and shared, so adding a repository to [AppDependencies] does not have to
/// be repeated in every widget test that needs a whole application.
class TestDependencies {
  const TestDependencies._();

  /// Pass [salesReportRepository] to substitute the reports data source, which is what a
  /// test that needs the Reports screen to fail does. Pass [settingsRepository] to
  /// substitute the settings data source, which is what a test that needs the Settings
  /// screen to fail does. Pass [refundRepository] to substitute refunds, which is what a
  /// test that needs a refund to fail from the bill detail screen does. Everything else
  /// stays real.
  ///
  /// [activeSettings] is the configuration the bootstrap would have read before the first
  /// frame. Left out, it is an unconfigured terminal, which is what a fresh install is.
  static AppDependencies over(
    SqliteDatabase database, {
    ThermalPrinter? printer,
    SalesReportRepository? salesReportRepository,
    SettingsRepository? settingsRepository,
    HeldBillRepository? heldBillRepository,
    RefundRepository? refundRepository,
    PosSettings activeSettings = PosSettings.unconfigured,
    PrintSettings? printSettings,
  }) {
    final ThermalPrinter resolved = printer ?? UnconfiguredThermalPrinter();

    // One encoder, shared between the print service and the profile the application
    // exposes, exactly as the bootstrap wires it. That is what makes a printer setting
    // saved on the Settings screen affect the next document a test prints.
    final ConfigurableEscPosEncoder encoder =
        ConfigurableEscPosEncoder.forPrinter(resolved, settings: printSettings);

    return AppDependencies(
      database: database,
      outbox: SqliteOutboxStore(database: database),
      menuRepository: SqliteMenuRepository(database: database),
      orderRepository: SqliteOrderRepository(database: database),
      checkoutRepository: SqliteCheckoutRepository(database: database),
      heldBillRepository:
          heldBillRepository ?? SqliteHeldBillRepository(database: database),
      customerRepository: SqliteCustomerRepository(database: database),
      paymentRepository: SqlitePaymentRepository(database: database),
      refundRepository:
          refundRepository ?? SqliteRefundRepository(database: database),
      inventoryRepository: SqliteInventoryRepository(database: database),
      recipeRepository: SqliteRecipeRepository(database: database),
      inventoryDeductionRepository: SqliteInventoryDeductionRepository(
        database: database,
      ),
      kotRepository: SqliteKotRepository(database: database),
      salesReportRepository:
          salesReportRepository ??
          SqliteSalesReportRepository(database: database),
      settingsRepository:
          settingsRepository ?? SqliteSettingsRepository(database: database),
      activeSettings: ActivePosSettings(settings: activeSettings),
      printer: resolved,
      activePrintProfile: encoder,
      printService: TestPrinting.serviceOver(
        database,
        printer: resolved,
        encoder: encoder,
      ),
    );
  }
}
