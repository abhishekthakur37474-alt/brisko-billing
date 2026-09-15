import '../../../utils/result.dart';
import '../../remote_store.dart';
import '../../sync/syncable_entity.dart';
import 'firestore_rest_client.dart';

/// [RemoteStore] backed by one Cloud Firestore collection under the signed-in
/// restaurant.
///
/// The cloud document mirrors the local row: the entity's own `toMap` is the payload in
/// both directions — it is what is written to SQLite and, once translated into
/// Firestore's typed values by the client, what is written to the cloud — and [fromRow]
/// turns a downloaded document back into an entity the same way it turns a SQLite row
/// into one. That symmetry is why there is no separate cloud DTO to keep in step.
///
/// This is the one class that is specific to the backend. Everything above it works
/// through [RemoteStore], so the choice of Firestore reaches no further than the
/// bootstrap that constructs it.
class FirestoreRemoteStore<T extends SyncableEntity> implements RemoteStore<T> {
  const FirestoreRemoteStore({
    required this.client,
    required this.collection,
    required this.fromRow,
  });

  final FirestoreRestClient client;

  /// Local table name for this collection. The client maps it to the Firestore
  /// collection id under the restaurant document.
  final String collection;

  /// Rebuilds an entity from a downloaded document, the same function the local store
  /// uses for a SQLite row.
  final T Function(Map<String, Object?> row) fromRow;

  @override
  Future<Result<void>> push(T entity) =>
      client.upsert(collection, <Map<String, dynamic>>[entity.toMap()]);

  @override
  Future<Result<void>> pushAll(Iterable<T> entities) {
    final List<Map<String, dynamic>> rows = entities
        .map((T entity) => entity.toMap())
        .toList(growable: false);
    return client.upsert(collection, rows);
  }

  @override
  Future<Result<void>> pushDelete(String id) =>
      client.markDeleted(collection, id);

  @override
  Future<Result<List<T>>> pullChangedSince(DateTime? since) async {
    final Result<List<Map<String, dynamic>>> result = await client
        .selectChangedSince(collection, since?.toUtc().millisecondsSinceEpoch);
    return result.map(
      (List<Map<String, dynamic>> rows) =>
          rows.map(fromRow).toList(growable: false),
    );
  }
}
