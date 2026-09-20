import 'package:sqflite/sqflite.dart';

import '../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../core/data/local/sqlite/sqlite_outbox_store.dart';
import '../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../core/utils/result.dart';
import '../domain/services/operational_data_wiper.dart';

/// SQLite implementation of [OperationalDataWiper].
///
/// ## What is removed
///
/// Every table that feeds a bill, a kitchen slip, a report or the dashboard,
/// including the menu. Rows are physically deleted rather than soft-deleted, so
/// the till looks empty afterwards rather than full of hidden history.
///
/// ## What is kept
///
/// [SqliteTables.settings] holds the sign-in, the outlet, the printer and the
/// manager password. [SqliteTables.syncMetadata] is left so an ordinary pull
/// does not dump the entire cloud history back onto a just-cleared till.
///
/// ## Foreign keys
///
/// Child tables are emptied before their parents, matching `ON DELETE RESTRICT`.
/// The whole wipe is one transaction, so a fault leaves the previous data intact.
class SqliteOperationalDataWiper implements OperationalDataWiper {
  const SqliteOperationalDataWiper({
    required this.database,
    required this.outbox,
  });

  final SqliteDatabase database;

  final SqliteOutboxStore outbox;

  /// Child-before-parent order. [SqliteTables.settings] and
  /// [SqliteTables.syncMetadata] are deliberately absent.
  static const List<String> tablesInDeleteOrder = <String>[
    SqliteTables.kotItemOptions,
    SqliteTables.kotItems,
    SqliteTables.kotRecords,
    SqliteTables.orderItemOptions,
    SqliteTables.refunds,
    SqliteTables.payments,
    SqliteTables.orderInventoryDeductions,
    SqliteTables.orderItems,
    SqliteTables.orders,
    SqliteTables.heldBillLineOptions,
    SqliteTables.heldBillLines,
    SqliteTables.heldBills,
    SqliteTables.recipeIngredients,
    SqliteTables.stockMovements,
    SqliteTables.menuItemOptions,
    SqliteTables.menuItemVariants,
    SqliteTables.menuItems,
    SqliteTables.categories,
    SqliteTables.inventoryItems,
    SqliteTables.customers,
    SqliteTables.expenses,
    SqliteTables.outbox,
  ];

  @override
  Future<Result<void>> clearOperationalData() {
    return SqliteErrorMapper.guard<void>(() async {
      await database.database.transaction((Transaction txn) async {
        for (final String table in tablesInDeleteOrder) {
          await txn.delete(table);
        }
      });

      await outbox.clearAll();
      database.notifyTablesChanged(tablesInDeleteOrder);
    }, context: 'clear the till data');
  }
}
