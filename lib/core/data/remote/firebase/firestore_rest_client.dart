import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../error/app_failure.dart';
import '../../../utils/result.dart';
import 'firebase_auth_session.dart';
import 'firebase_config.dart';
import 'firestore_value.dart';

/// A thin Cloud Firestore client over `dart:io`.
///
/// One place that knows the shape of a Firestore request: how a document write is
/// batched into a `:commit`, how "changed since" becomes a `:runQuery` structured
/// query, how a row is scoped under `restaurants/{restaurantId}/…`, and how an HTTP
/// outcome becomes an [AppFailure]. Everything above it works in terms of rows and
/// never sees a document path or a typed value.
///
/// Every call first asks the [FirebaseAuthSession] for a valid ID token and the
/// restaurant scope. A session that cannot be refreshed because the link is down yields
/// a [NetworkFailure], so the work stays queued exactly as an unreachable write would;
/// a session the server refused yields a [RemoteFailure], surfaced and retried later.
/// The restaurant scope is the signed-in `uid`, so the client can only ever address the
/// terminal's own restaurant — the same boundary the security rules enforce server-side.
class FirestoreRestClient {
  FirestoreRestClient({
    required this.config,
    required this.session,
    HttpClient? httpClient,
    this.baseUrl = 'https://firestore.googleapis.com/v1',
    this.timeout = const Duration(seconds: 20),
  }) : _client = httpClient ?? HttpClient();

  final FirebaseConfig config;
  final FirebaseAuthSession session;

  /// Base of the Firestore REST endpoint. Overridable so tests can point the client at
  /// a local server instead of Google's.
  final String baseUrl;

  final HttpClient _client;
  final Duration timeout;

  /// The Firestore documents root for the configured project.
  String get _documentsRoot =>
      '$baseUrl/projects/${config.projectId}/databases/(default)/documents';

  /// Inserts or overwrites [rows] in [collection] for the signed-in restaurant.
  ///
  /// Each write is keyed by the row's stable `id`, so replaying a queued write or
  /// running a restore updates the document in place rather than creating a second
  /// copy. Writes are sent in a single atomic `:commit` (chunked to Firestore's
  /// 500-write limit), which is what makes an upload of a whole bill all-or-nothing.
  Future<Result<void>> upsert(
    String collection,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) {
      return const Ok<void>(null);
    }
    return _withAuth((FirebaseAuthContext auth) async {
      for (final List<Map<String, dynamic>> chunk in _chunk(rows, 500)) {
        final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[
          for (final Map<String, dynamic> row in chunk)
            <String, dynamic>{
              'update': <String, dynamic>{
                'name': _documentName(
                  auth.restaurantId,
                  collection,
                  row['id'] as String,
                ),
                'fields': FirestoreValue.encodeFields(row),
              },
            },
        ];
        final Result<void> result = await _commit(
          auth,
          writes,
          'upload records',
        );
        if (result.isErr) {
          return result;
        }
      }
      return const Ok<void>(null);
    });
  }

  /// Marks a document soft-deleted in the cloud.
  ///
  /// The engine normally propagates a deletion by upserting the whole soft-deleted row,
  /// which carries the correct `updatedAt`; this patches only the flag when an id is all
  /// that is to hand, using an update mask so no other field is disturbed.
  Future<Result<void>> markDeleted(String collection, String id) async {
    return _withAuth((FirebaseAuthContext auth) {
      final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[
        <String, dynamic>{
          'update': <String, dynamic>{
            'name': _documentName(auth.restaurantId, collection, id),
            'fields': FirestoreValue.encodeFields(<String, dynamic>{
              'isDeleted': 1,
              'updatedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
              'syncState': 'synced',
            }),
          },
          'updateMask': <String, dynamic>{
            'fieldPaths': <String>['isDeleted', 'updatedAt', 'syncState'],
          },
        },
      ];
      return _commit(auth, writes, 'upload a deletion');
    });
  }

  /// Reads documents from [collection] whose `updatedAt` is greater than [sinceMillis],
  /// oldest change first. A `null` [sinceMillis] reads everything, which is what a fresh
  /// terminal needs to restore.
  Future<Result<List<Map<String, dynamic>>>> selectChangedSince(
    String collection,
    int? sinceMillis,
  ) async {
    return _withAuth((FirebaseAuthContext auth) async {
      final Map<String, dynamic> structuredQuery = <String, dynamic>{
        'from': <Map<String, dynamic>>[
          <String, dynamic>{
            'collectionId': FirestoreCollections.resolve(collection),
          },
        ],
        'orderBy': <Map<String, dynamic>>[
          <String, dynamic>{
            'field': <String, dynamic>{'fieldPath': 'updatedAt'},
            'direction': 'ASCENDING',
          },
        ],
        if (sinceMillis != null)
          'where': <String, dynamic>{
            'fieldFilter': <String, dynamic>{
              'field': <String, dynamic>{'fieldPath': 'updatedAt'},
              'op': 'GREATER_THAN',
              'value': FirestoreValue.encode(sinceMillis),
            },
          },
      };

      final Uri uri = Uri.parse('${_parentPath(auth.restaurantId)}:runQuery');
      return _send<List<Map<String, dynamic>>>(
        method: 'POST',
        uri: uri,
        idToken: auth.idToken,
        body: jsonEncode(<String, dynamic>{'structuredQuery': structuredQuery}),
        onSuccess: _decodeQueryRows,
        context: 'download records',
      );
    });
  }

  Future<void> close() async => _client.close(force: true);

  // ------------------------------------------------------------------ helpers ---

  Future<Result<T>> _withAuth<T>(
    Future<Result<T>> Function(FirebaseAuthContext auth) action,
  ) async {
    final Result<FirebaseAuthContext> auth = await session.current();
    return switch (auth) {
      Ok<FirebaseAuthContext>(:final FirebaseAuthContext value) => action(
        value,
      ),
      Err<FirebaseAuthContext>(:final AppFailure failure) => Err<T>(failure),
    };
  }

  Future<Result<void>> _commit(
    FirebaseAuthContext auth,
    List<Map<String, dynamic>> writes,
    String context,
  ) {
    final Uri uri = Uri.parse('$_documentsRoot:commit');
    return _send<void>(
      method: 'POST',
      uri: uri,
      idToken: auth.idToken,
      body: jsonEncode(<String, dynamic>{'writes': writes}),
      onSuccess: (_) {},
      context: context,
    );
  }

  String _parentPath(String restaurantId) =>
      '$_documentsRoot/restaurants/$restaurantId';

  String _documentName(String restaurantId, String collection, String id) =>
      'projects/${config.projectId}/databases/(default)/documents/restaurants/'
      '$restaurantId/${FirestoreCollections.resolve(collection)}/$id';

  static Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (int i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }

  /// A `:runQuery` response is an array of results; each carries a `document` (unless it
  /// is the leading read-time-only marker), and each document a `fields` map to decode.
  static List<Map<String, dynamic>> _decodeQueryRows(String body) {
    if (body.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const FormatException('Expected a JSON array of query results');
    }
    final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
    for (final Object? entry in decoded) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final Object? document = entry['document'];
      if (document is! Map<String, dynamic>) {
        continue;
      }
      final Object? fields = document['fields'];
      if (fields is Map<String, dynamic>) {
        rows.add(
          Map<String, dynamic>.from(FirestoreValue.decodeFields(fields)),
        );
      }
    }
    return rows;
  }

  Future<Result<T>> _send<T>({
    required String method,
    required Uri uri,
    required String idToken,
    required T Function(String body) onSuccess,
    required String context,
    String? body,
  }) async {
    try {
      final HttpClientRequest request = await _client
          .openUrl(method, uri)
          .timeout(timeout);

      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $idToken')
        ..set(HttpHeaders.acceptHeader, 'application/json');

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }

      final HttpClientResponse response = await request.close().timeout(
        timeout,
      );
      final String responseBody = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return Ok<T>(onSuccess(responseBody));
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return Err<T>(
          RemoteFailure(
            'The cloud rejected the terminal\'s credentials. Check the Firebase '
            'sign-in and the security rules.',
            cause: responseBody,
          ),
        );
      }

      return Err<T>(
        RemoteFailure(
          'The cloud could not $context (HTTP ${response.statusCode}).',
          cause: responseBody,
        ),
      );
    } on SocketException catch (error) {
      // No route to the host: the ordinary offline case. Leaves work queued.
      return Err<T>(NetworkFailure('The cloud is unreachable.', cause: error));
    } on TimeoutException catch (error) {
      return Err<T>(
        NetworkFailure('The cloud did not respond in time.', cause: error),
      );
    } on HandshakeException catch (error) {
      return Err<T>(
        NetworkFailure(
          'The secure connection to the cloud failed.',
          cause: error,
        ),
      );
    } on FormatException catch (error) {
      return Err<T>(
        RemoteFailure(
          'The cloud returned data that could not be read.',
          cause: error,
        ),
      );
    } on Object catch (error) {
      return Err<T>(
        NetworkFailure('The cloud could not $context.', cause: error),
      );
    }
  }
}
