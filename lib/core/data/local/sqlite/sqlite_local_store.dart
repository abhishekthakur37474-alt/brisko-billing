import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../utils/entity_id.dart';
import '../../../utils/result.dart';
import '../../local_store.dart';
import '../../sync/outbox_entry.dart';
import '../../sync/outbox_store.dart';
import '../../sync/remote_merge_report.dart';
import '../../sync/sync_state.dart';
import '../../sync/syncable_entity.dart';
import 'sqlite_database.dart';
import 'sqlite_error_mapper.dart';
import 'sqlite_tables.dart';
import 'sqlite_upsert.dart';

/// SQLite-backed implementation of [LocalStore] for one table.
///
/// Generic on purpose: the CRUD surface every syncable entity needs is identical,
/// so it is written once here and each repository composes an instance per table.
/// Queries specific to a feature, such as finding a customer by phone or loading
/// an order with its lines, live in that feature's repository implementation. All
/// of it stays inside the data layer, so no SQL reaches a widget.
///
/// Every read filters out soft-deleted rows. A caller that wants them must query
/// explicitly through a repository.
class SqliteLocalStore<T extends SyncableEntity> implements LocalStore<T> {
  SqliteLocalStore({
    required this.database,
    required this.table,
    required this.fromRow,
    this.orderBy,
    this.outbox,
    String? collection,
  }) : _collection = collection ?? table;

  final SqliteDatabase database;

  /// Table this store reads and writes.
  final String table;

  /// Builds an entity from a result row.
  final T Function(Map<String, Object?> row) fromRow;

  /// Default sort applied by [findAll] and [watchAll].
  final String? orderBy;

  /// Optional durable queue for changes that should reach a cloud backend.
  ///
  /// Left `null` for now. The outbox table and [OutboxStore] implementation exist
  /// and are tested, but nothing drains them yet because there is no backend, and
  /// an undrained queue would grow without bound for every bill the outlet ever
  /// takes. Supplying an outbox here is the single change that switches enqueueing
  /// on, at the point a `RemoteStore` and `SyncCoordinator` are actually wired up.
  final OutboxStore? outbox;

  final String _collection;

  Database get _db => database.database;

  @override
  Future<Result<T?>> findById(String id) {
    return SqliteErrorMapper.guard<T?>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        table,
        where: '${SyncColumns.id} = ? AND ${SyncColumns.isDeleted} = 0',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : fromRow(rows.first);
    }, context: 'load the record');
  }

  @override
  Future<Result<List<T>>> findAll() {
    return SqliteErrorMapper.guard<List<T>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        table,
        where: '${SyncColumns.isDeleted} = 0',
        orderBy: orderBy,
      );
      return rows.map(fromRow).toList(growable: false);
    }, context: 'load records');
  }

  @override
  Future<Result<void>> save(T entity) {
    return SqliteErrorMapper.guard<void>(() async {
      await SqliteUpsert.run(_db, table, entity.toMap());
      await _enqueue(entity, OutboxOperation.upsert);
      database.notifyTableChanged(table);
    }, context: 'save the record');
  }

  @override
  Future<Result<void>> saveAll(Iterable<T> entities) {
    return SqliteErrorMapper.guard<void>(() async {
      if (entities.isEmpty) {
        return;
      }
      // One transaction so a partial write cannot leave the table inconsistent.
      await _db.transaction((Transaction txn) async {
        for (final T entity in entities) {
          await SqliteUpsert.run(txn, table, entity.toMap());
        }
      });
      for (final T entity in entities) {
        await _enqueue(entity, OutboxOperation.upsert);
      }
      database.notifyTableChanged(table);
    }, context: 'save records');
  }

  @override
  Future<Result<void>> softDelete(String id) {
    return SqliteErrorMapper.guard<void>(() async {
      final int updated = await _db.update(
        table,
        <String, Object?>{
          SyncColumns.isDeleted: 1,
          SyncColumns.updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          // Back to pending: the deletion is itself a change the cloud has not
          // seen.
          SyncColumns.syncState: SyncState.pending.name,
        },
        where: '${SyncColumns.id} = ?',
        whereArgs: <Object?>[id],
      );

      if (updated == 0) {
        return;
      }

      await _enqueueDelete(id);
      database.notifyTableChanged(table);
    }, context: 'delete the record');
  }

  @override
  Future<Result<List<T>>> findUnsynced() {
    return SqliteErrorMapper.guard<List<T>>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        table,
        where: '${SyncColumns.syncState} != ?',
        whereArgs: <Object?>[SyncState.synced.name],
        orderBy: SyncColumns.updatedAt,
      );
      return rows.map(fromRow).toList(growable: false);
    }, context: 'load unsynced records');
  }

  @override
  Future<Result<void>> markSynced(String id, DateTime version) {
    return SqliteErrorMapper.guard<void>(() async {
      // Guarded on updatedAt: if the record changed after it was pushed, the
      // stored timestamp no longer matches the version that reached the cloud, so
      // it is left pending and the newer edit is uploaded on the next cycle.
      final int updated = await _db.update(
        table,
        <String, Object?>{SyncColumns.syncState: SyncState.synced.name},
        where:
            '${SyncColumns.id} = ? AND ${SyncColumns.updatedAt} = ? '
            'AND ${SyncColumns.syncState} != ?',
        whereArgs: <Object?>[
          id,
          version.toUtc().millisecondsSinceEpoch,
          SyncState.synced.name,
        ],
      );
      if (updated > 0) {
        database.notifyTableChanged(table);
      }
    }, context: 'mark the record synced');
  }

  @override
  Future<Result<RemoteMergeReport>> applyRemoteChanges(Iterable<T> entities) {
    return SqliteErrorMapper.guard<RemoteMergeReport>(() async {
      final List<T> incoming = entities.toList(growable: false);
      if (incoming.isEmpty) {
        return const RemoteMergeReport.empty();
      }

      int applied = 0;
      int keptLocal = 0;

      await _db.transaction((Transaction txn) async {
        for (final T entity in incoming) {
          // Reads the local row including a soft-deleted one, because a delete is
          // itself a change with a timestamp: an older undelete from the cloud
          // must not resurrect a record this terminal has since removed.
          final List<Map<String, Object?>> rows = await txn.query(
            table,
            columns: <String>[SyncColumns.updatedAt],
            where: '${SyncColumns.id} = ?',
            whereArgs: <Object?>[entity.id],
            limit: 1,
          );

          final int remoteAt = entity.updatedAt.toUtc().millisecondsSinceEpoch;

          if (rows.isNotEmpty) {
            final int localAt = rows.first[SyncColumns.updatedAt]! as int;
            // Strictly newer wins. Older or equal is held back, protecting a
            // newer local record — including a settled bill not yet uploaded.
            if (remoteAt <= localAt) {
              keptLocal++;
              continue;
            }
          }

          // Stored as synced: it now matches the cloud, so it must not be queued
          // straight back for upload.
          final Map<String, dynamic> values = Map<String, dynamic>.from(
            entity.toMap(),
          )..[SyncColumns.syncState] = SyncState.synced.name;

          await SqliteUpsert.run(txn, table, values);
          applied++;
        }
      });

      if (applied > 0) {
        database.notifyTableChanged(table);
      }
      return RemoteMergeReport(applied: applied, keptLocal: keptLocal);
    }, context: 'apply cloud changes');
  }

  @override
  Stream<List<T>> watchAll() {
    late final StreamController<List<T>> controller;
    StreamSubscription<String>? subscription;

    Future<void> emit() async {
      final Result<List<T>> result = await findAll();
      if (controller.isClosed) {
        return;
      }
      result.fold(onOk: controller.add, onErr: controller.addError);
    }

    controller = StreamController<List<T>>(
      onListen: () {
        subscription = database.tableChanges
            .where((String table) => table == table)
            .listen((String _) => unawaited(emit()));
        unawaited(emit());
      },
      onCancel: () async {
        await subscription?.cancel();
        subscription = null;
        // The controller belongs to this subscription alone, so it is disposed
        // with it. Leaving it open would leak a listener on `tableChanges` for
        // every screen that has ever watched this table.
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<void> _enqueue(T entity, OutboxOperation operation) async {
    final OutboxStore? queue = outbox;
    if (queue == null) {
      return;
    }
    await queue.enqueue(
      OutboxEntry(
        id: EntityId.generate(prefix: 'obx'),
        collection: _collection,
        entityId: entity.id,
        operation: operation,
        payload: entity.toMap(),
        queuedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> _enqueueDelete(String id) async {
    final OutboxStore? queue = outbox;
    if (queue == null) {
      return;
    }
    await queue.enqueue(
      OutboxEntry(
        id: EntityId.generate(prefix: 'obx'),
        collection: _collection,
        entityId: id,
        operation: OutboxOperation.delete,
        payload: const <String, Object?>{},
        queuedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

/// Encodes and decodes the JSON payload column of the outbox table.
///
/// Kept next to the store because both sides of the outbox use it.
class OutboxPayloadCodec {
  const OutboxPayloadCodec._();

  static String encode(Map<String, dynamic> payload) => jsonEncode(payload);

  static Map<String, dynamic> decode(String payload) {
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Outbox payload is not a JSON object');
  }
}
