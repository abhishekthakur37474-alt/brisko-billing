import 'package:sqflite/sqflite.dart';

import '../../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../../core/data/local/sqlite/sqlite_local_store.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/data/local/sqlite/sqlite_upsert.dart';
import '../../../../core/data/sync/sync_state.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/kot_item.dart';
import '../../domain/models/kot_record.dart';
import '../../domain/models/kot_status.dart';
import '../../domain/repositories/kot_repository.dart';

/// SQLite implementation of [KotRepository].
class SqliteKotRepository implements KotRepository {
  SqliteKotRepository({required SqliteDatabase database})
    : _database = database,
      _records = SqliteLocalStore<KotRecord>(
        database: database,
        table: SqliteTables.kotRecords,
        fromRow: KotRecord.fromRow,
        orderBy: 'createdAt ASC',
      );

  final SqliteDatabase _database;
  final SqliteLocalStore<KotRecord> _records;

  Database get _db => _database.database;

  @override
  Future<Result<void>> createKot(KotRecord record, List<KotItem> items) {
    return SqliteErrorMapper.guard<void>(() async {
      await _db.transaction((Transaction txn) async {
        // Upsert on id only, so a reused kotNumber is refused rather than
        // silently replacing the slip that already carries that number.
        await SqliteUpsert.run(txn, SqliteTables.kotRecords, record.toMap());
        for (final KotItem item in items) {
          await SqliteUpsert.run(txn, SqliteTables.kotItems, item.toMap());
        }
      });

      _database.notifyTablesChanged(const <String>[
        SqliteTables.kotRecords,
        SqliteTables.kotItems,
      ]);
    }, context: 'create the kitchen slip');
  }

  @override
  Future<Result<KotRecord?>> findKot(String id) => _records.findById(id);

  @override
  Future<Result<List<KotRecord>>> loadForOrder(String orderId) {
    return SqliteErrorMapper.guard<List<KotRecord>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.kotRecords,
        where: 'orderId = ? AND isDeleted = 0',
        whereArgs: <Object?>[orderId],
        orderBy: 'createdAt ASC',
      );
      return rows.map(KotRecord.fromRow).toList(growable: false);
    }, context: 'load the kitchen slips');
  }

  @override
  Future<Result<List<KotItem>>> loadItems(String kotId) {
    return SqliteErrorMapper.guard<List<KotItem>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.kotItems,
        where: 'kotId = ? AND isDeleted = 0',
        whereArgs: <Object?>[kotId],
        orderBy: 'createdAt ASC, rowid ASC',
      );
      return rows.map(KotItem.fromRow).toList(growable: false);
    }, context: 'load the slip lines');
  }

  @override
  Future<Result<List<KotRecord>>> loadPending() {
    return SqliteErrorMapper.guard<List<KotRecord>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.kotRecords,
        where: 'status = ? AND isDeleted = 0',
        whereArgs: <Object?>[KotStatus.pending.name],
        orderBy: 'createdAt ASC',
      );
      return rows.map(KotRecord.fromRow).toList(growable: false);
    }, context: 'load pending kitchen slips');
  }

  @override
  Future<Result<String>> nextKotNumber() {
    return SqliteErrorMapper.guard<String>(() async {
      final DateTime now = DateTime.now();
      final String datePart =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';

      final List<Map<String, Object?>> rows = await _db.rawQuery(
        'SELECT kotNumber FROM ${SqliteTables.kotRecords} '
        'WHERE kotNumber LIKE ? '
        'ORDER BY kotNumber DESC LIMIT 1',
        <Object?>['K$datePart-%'],
      );

      int sequence = 1;
      if (rows.isNotEmpty) {
        final String last = rows.first['kotNumber']! as String;
        final int dashIndex = last.lastIndexOf('-');
        final int? parsed = dashIndex == -1
            ? null
            : int.tryParse(last.substring(dashIndex + 1));
        if (parsed != null) {
          sequence = parsed + 1;
        }
      }

      return 'K$datePart-${sequence.toString().padLeft(4, '0')}';
    }, context: 'allocate a kitchen slip number');
  }

  @override
  Future<Result<void>> updateStatus(String kotId, KotStatus status) {
    return SqliteErrorMapper.guard<void>(() async {
      await _db.update(
        SqliteTables.kotRecords,
        <String, Object?>{
          'status': status.name,
          SyncColumns.updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          SyncColumns.syncState: SyncState.pending.name,
        },
        where: '${SyncColumns.id} = ?',
        whereArgs: <Object?>[kotId],
      );
      _database.notifyTableChanged(SqliteTables.kotRecords);
    }, context: 'update the kitchen slip');
  }
}
