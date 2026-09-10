import '../utils/result.dart';
import 'sync/syncable_entity.dart';

/// On-device persistence for one collection of entities.
///
/// This is the write path the billing module talks to, directly or through a
/// repository. It must succeed with no internet connection, which is why it is a
/// separate contract from `RemoteStore` rather than a cache in front of it.
///
/// The concrete implementation is chosen later. Nothing above this interface
/// depends on which local database is used.
abstract interface class LocalStore<T extends SyncableEntity> {
  /// Returns the entity, or `null` when absent. Soft-deleted records are not
  /// returned.
  Future<Result<T?>> findById(String id);

  /// All live records. Soft-deleted records are excluded.
  Future<Result<List<T>>> findAll();

  /// Inserts or replaces a record.
  Future<Result<void>> save(T entity);

  /// Inserts or replaces many records in one transaction. Used when pulling
  /// changes down from the cloud.
  Future<Result<void>> saveAll(Iterable<T> entities);

  /// Marks a record deleted without physically removing it, so the deletion can
  /// still be pushed to the cloud.
  Future<Result<void>> softDelete(String id);

  /// Records that the cloud has not acknowledged yet.
  Future<Result<List<T>>> findUnsynced();

  /// Emits the full live record set whenever it changes, so the UI can rebuild
  /// without polling.
  Stream<List<T>> watchAll();
}
