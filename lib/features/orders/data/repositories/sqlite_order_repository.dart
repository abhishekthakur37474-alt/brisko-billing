import 'package:sqflite/sqflite.dart';

import '../../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../../core/data/local/sqlite/sqlite_local_store.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/local/sqlite/sqlite_upsert.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/order_item_option.dart';
import '../../domain/models/order_status.dart';
import '../../domain/repositories/order_repository.dart';

/// SQLite implementation of [OrderRepository].
class SqliteOrderRepository implements OrderRepository {
  SqliteOrderRepository({required SqliteDatabase database})
    : _database = database,
      _orders = SqliteLocalStore<Order>(
        database: database,
        table: SqliteTables.orders,
        fromRow: Order.fromRow,
        orderBy: 'createdAt DESC',
      );

  final SqliteDatabase _database;
  final SqliteLocalStore<Order> _orders;

  Database get _db => _database.database;

  @override
  Future<Result<void>> saveOrder(
    Order order, {
    List<OrderItem> items = const <OrderItem>[],
    List<OrderItemOption> itemOptions = const <OrderItemOption>[],
  }) {
    return SqliteErrorMapper.guard<void>(() async {
      await _db.transaction((Transaction txn) async {
        // Upsert on id only. A collision on the unique orderNumber must fail
        // rather than replace, because replacing would delete a settled bill.
        await SqliteUpsert.run(txn, SqliteTables.orders, order.toMap());
        for (final OrderItem item in items) {
          await SqliteUpsert.run(txn, SqliteTables.orderItems, item.toMap());
        }
        for (final OrderItemOption option in itemOptions) {
          await SqliteUpsert.run(
            txn,
            SqliteTables.orderItemOptions,
            option.toMap(),
          );
        }
      });

      _database.notifyTablesChanged(const <String>[
        SqliteTables.orders,
        SqliteTables.orderItems,
        SqliteTables.orderItemOptions,
      ]);
    }, context: 'save the order');
  }

  @override
  Future<Result<Order?>> findOrder(String id) => _orders.findById(id);

  @override
  Future<Result<Order?>> findOrderByNumber(String orderNumber) {
    return SqliteErrorMapper.guard<Order?>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.orders,
        where: 'orderNumber = ? AND isDeleted = 0',
        whereArgs: <Object?>[orderNumber],
        limit: 1,
      );
      return rows.isEmpty ? null : Order.fromRow(rows.first);
    }, context: 'find the order');
  }

  /// Lines and their options are ordered by `createdAt` and then by SQLite's
  /// implicit `rowid`.
  ///
  /// The `rowid` tiebreak matters: several lines added within the same millisecond
  /// share a `createdAt`, and entity ids carry random entropy, so ordering by id
  /// would shuffle them arbitrarily. `rowid` increases with each insert, so it
  /// reproduces the exact sequence the cashier entered. A receipt whose lines
  /// reorder between prints looks wrong to the customer even when the total is
  /// right.
  @override
  Future<Result<List<OrderItem>>> loadItems(String orderId) {
    return SqliteErrorMapper.guard<List<OrderItem>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.orderItems,
        where: 'orderId = ? AND isDeleted = 0',
        whereArgs: <Object?>[orderId],
        orderBy: 'createdAt ASC, rowid ASC',
      );
      return rows.map(OrderItem.fromRow).toList(growable: false);
    }, context: 'load the order lines');
  }

  @override
  Future<Result<List<OrderItemOption>>> loadItemOptions(String orderItemId) {
    return SqliteErrorMapper.guard<List<OrderItemOption>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.orderItemOptions,
        where: 'orderItemId = ? AND isDeleted = 0',
        whereArgs: <Object?>[orderItemId],
        orderBy: 'createdAt ASC, rowid ASC',
      );
      return rows.map(OrderItemOption.fromRow).toList(growable: false);
    }, context: 'load the line options');
  }

  @override
  Future<Result<List<Order>>> loadOrders({
    DateTime? from,
    DateTime? to,
    OrderStatus? status,
    int limit = 200,
  }) {
    return SqliteErrorMapper.guard<List<Order>>(() async {
      final List<String> clauses = <String>['isDeleted = 0'];
      final List<Object?> args = <Object?>[];

      if (from != null) {
        clauses.add('createdAt >= ?');
        args.add(from.toUtc().millisecondsSinceEpoch);
      }
      if (to != null) {
        clauses.add('createdAt < ?');
        args.add(to.toUtc().millisecondsSinceEpoch);
      }
      if (status != null) {
        clauses.add('status = ?');
        args.add(status.name);
      }

      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.orders,
        where: clauses.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      return rows.map(Order.fromRow).toList(growable: false);
    }, context: 'load orders');
  }

  @override
  Future<Result<List<Order>>> loadOrdersForCustomer(String customerId) {
    return SqliteErrorMapper.guard<List<Order>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.orders,
        where: 'customerId = ? AND isDeleted = 0',
        whereArgs: <Object?>[customerId],
        orderBy: 'createdAt DESC',
      );
      return rows.map(Order.fromRow).toList(growable: false);
    }, context: 'load the customer order history');
  }

  @override
  Future<Result<String>> nextOrderNumber() {
    return SqliteErrorMapper.guard<String>(() async {
      // Numbers restart each day and carry the date, which is what the outlet
      // reads out over the counter. Safe to derive by counting because a single
      // terminal issues them; there is no second till to race with.
      final DateTime now = DateTime.now();
      final String datePart =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';

      final List<Map<String, Object?>> rows = await _db.rawQuery(
        'SELECT orderNumber FROM ${SqliteTables.orders} '
        'WHERE orderNumber LIKE ? '
        'ORDER BY orderNumber DESC LIMIT 1',
        <Object?>['$datePart-%'],
      );

      int sequence = 1;
      if (rows.isNotEmpty) {
        final String last = rows.first['orderNumber']! as String;
        final int dashIndex = last.lastIndexOf('-');
        final int? parsed = dashIndex == -1
            ? null
            : int.tryParse(last.substring(dashIndex + 1));
        if (parsed != null) {
          sequence = parsed + 1;
        }
      }

      return '$datePart-${sequence.toString().padLeft(4, '0')}';
    }, context: 'allocate an order number');
  }

  @override
  Future<Result<void>> updateStatus(String orderId, OrderStatus status) {
    return SqliteErrorMapper.guard<void>(() async {
      await _db.update(
        SqliteTables.orders,
        <String, Object?>{
          'status': status.name,
          SyncColumns.updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          // The change has not reached any backend yet.
          SyncColumns.syncState: SyncState.pending.name,
        },
        where: '${SyncColumns.id} = ?',
        whereArgs: <Object?>[orderId],
      );
      _database.notifyTableChanged(SqliteTables.orders);
    }, context: 'update the order status');
  }

  @override
  Future<Result<void>> deleteOrder(String id) => _orders.softDelete(id);
}
