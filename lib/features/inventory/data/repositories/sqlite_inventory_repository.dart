import 'package:sqflite/sqflite.dart';

import '../../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../../core/data/local/sqlite/sqlite_local_store.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/utils/entity_id.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/inventory_item.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/models/stock_movement_type.dart';
import '../../domain/repositories/inventory_repository.dart';

/// SQLite implementation of [InventoryRepository].
class SqliteInventoryRepository implements InventoryRepository {
  SqliteInventoryRepository({required SqliteDatabase database})
    : _database = database,
      _items = SqliteLocalStore<InventoryItem>(
        database: database,
        table: SqliteTables.inventoryItems,
        fromRow: InventoryItem.fromRow,
        orderBy: 'name ASC',
      );

  final SqliteDatabase _database;
  final SqliteLocalStore<InventoryItem> _items;

  Database get _db => _database.database;

  @override
  Future<Result<List<InventoryItem>>> loadItems() {
    return SqliteErrorMapper.guard<List<InventoryItem>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.inventoryItems,
        where: 'isDeleted = 0 AND isActive = 1',
        orderBy: 'name ASC',
      );
      return rows.map(InventoryItem.fromRow).toList(growable: false);
    }, context: 'load the stock items');
  }

  @override
  Stream<List<InventoryItem>> watchItems() => _items.watchAll();

  @override
  Future<Result<InventoryItem?>> findItem(String id) => _items.findById(id);

  @override
  Future<Result<List<InventoryItem>>> loadLowStockItems() {
    return SqliteErrorMapper.guard<List<InventoryItem>>(() async {
      // A minimum of zero means the item is not monitored, so it is excluded
      // rather than perpetually reported as low.
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.inventoryItems,
        where:
            'isDeleted = 0 AND isActive = 1 '
            'AND minimumQuantityMilli > 0 '
            'AND currentQuantityMilli <= minimumQuantityMilli',
        orderBy: 'name ASC',
      );
      return rows.map(InventoryItem.fromRow).toList(growable: false);
    }, context: 'load low stock items');
  }

  @override
  Future<Result<void>> saveItem(InventoryItem item) => _items.save(item);

  @override
  Future<Result<StockMovement>> recordMovement({
    required String inventoryItemId,
    required StockMovementType type,
    required int quantityMilli,
    String? reason,
    String? referenceId,
  }) {
    return SqliteErrorMapper.guard<StockMovement>(() async {
      if (quantityMilli == 0) {
        throw ArgumentError.value(
          quantityMilli,
          'quantityMilli',
          'A movement of zero has no effect',
        );
      }

      final DateTime now = DateTime.now().toUtc();
      final StockMovement movement = StockMovement(
        id: EntityId.generate(prefix: 'stk'),
        inventoryItemId: inventoryItemId,
        movementType: type,
        quantityMilli: quantityMilli,
        reason: reason,
        referenceId: referenceId,
        createdAt: now,
        updatedAt: now,
      );

      await _db.transaction((Transaction txn) async {
        await txn.insert(SqliteTables.stockMovements, movement.toMap());

        // Applied as a relative UPDATE rather than read-modify-write, so the
        // balance cannot be clobbered by a concurrent movement.
        final int updated = await txn.rawUpdate(
          'UPDATE ${SqliteTables.inventoryItems} '
          'SET currentQuantityMilli = currentQuantityMilli + ?, '
          '    ${SyncColumns.updatedAt} = ?, '
          '    ${SyncColumns.syncState} = ? '
          'WHERE ${SyncColumns.id} = ? AND ${SyncColumns.isDeleted} = 0',
          <Object?>[
            movement.signedQuantityMilli,
            now.millisecondsSinceEpoch,
            SyncState.pending.name,
            inventoryItemId,
          ],
        );

        if (updated == 0) {
          // Rolls the movement back: a ledger entry against a stock item that
          // does not exist would corrupt the running totals.
          throw ArgumentError.value(
            inventoryItemId,
            'inventoryItemId',
            'No such stock item',
          );
        }
      });

      _database.notifyTablesChanged(const <String>[
        SqliteTables.stockMovements,
        SqliteTables.inventoryItems,
      ]);

      return movement;
    }, context: 'record the stock movement');
  }

  @override
  Future<Result<List<StockMovement>>> loadMovements(
    String inventoryItemId, {
    int limit = 100,
  }) {
    return SqliteErrorMapper.guard<List<StockMovement>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.stockMovements,
        where: 'inventoryItemId = ? AND isDeleted = 0',
        whereArgs: <Object?>[inventoryItemId],
        orderBy: 'createdAt DESC, rowid DESC',
        limit: limit,
      );
      return rows.map(StockMovement.fromRow).toList(growable: false);
    }, context: 'load the stock ledger');
  }

  @override
  Future<Result<void>> deleteItem(String id) => _items.softDelete(id);
}
