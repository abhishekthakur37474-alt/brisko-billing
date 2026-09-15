import 'dart:convert';

import 'package:brisko_billing/core/data/remote/firebase/firebase_auth_client.dart';
import 'package:brisko_billing/core/data/remote/firebase/firebase_auth_session.dart';
import 'package:brisko_billing/core/data/remote/firebase/firebase_config.dart';
import 'package:brisko_billing/core/data/remote/firebase/firestore_rest_client.dart';
import 'package:brisko_billing/core/error/app_failure.dart';
import 'package:brisko_billing/core/utils/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/recording_http_server.dart';

/// Exercises the Firestore client end to end over real HTTP against a loopback
/// server: it signs in via a refresh, scopes every request to the signed-in
/// restaurant, writes and reads documents in the wire format Firestore uses, and
/// classifies failures the way the offline-first engine relies on. No live Firebase
/// project is involved.
void main() {
  const FirebaseConfig config = FirebaseConfig(
    projectId: 'brisko-pos',
    apiKey: 'web-api-key',
    refreshToken: 'stored-refresh',
  );

  late RecordingHttpServer server;

  /// A responder that signs the terminal in as [uid] and answers commits and
  /// queries. [queryRows] is returned from any `:runQuery`.
  Future<HttpResponseSpec> Function(RecordedRequest) backend({
    required String uid,
    List<Map<String, dynamic>> queryDocuments = const <Map<String, dynamic>>[],
  }) {
    return (RecordedRequest request) async {
      if (request.path.contains('/securetoken/')) {
        return HttpResponseSpec(
          200,
          jsonEncode(<String, dynamic>{
            'id_token': 'id-token-for-$uid',
            'refresh_token': 'rotated',
            'user_id': uid,
            'expires_in': '3600',
          }),
        );
      }
      if (request.path.endsWith(':runQuery')) {
        return HttpResponseSpec(200, jsonEncode(queryDocuments));
      }
      // :commit
      return const HttpResponseSpec(200, '{"writeResults":[{}]}');
    };
  }

  FirestoreRestClient clientFor(RecordingHttpServer server) {
    final FirebaseAuthClient authClient = FirebaseAuthClient(
      config: config,
      secureTokenBaseUrl: '${server.baseUrl}/securetoken/v1',
    );
    final FirebaseAuthSession session = FirebaseAuthSession(
      config: config,
      authClient: authClient,
    );
    return FirestoreRestClient(
      config: config,
      session: session,
      baseUrl: '${server.baseUrl}/v1',
    );
  }

  setUp(() async {
    server = await RecordingHttpServer.start();
  });

  tearDown(() async {
    await server.close();
  });

  test(
    'an upsert commits documents scoped to the signed-in restaurant',
    () async {
      server.responder = backend(uid: 'restaurant-abc');
      final FirestoreRestClient client = clientFor(server);

      final Result<void> result = await client.upsert(
        'orders',
        <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'ord_1',
            'updatedAt': 1750000000000,
            'totalAmountPaise': 45000,
            'orderNumber': '20260601-0001',
            'customerId': null,
          },
        ],
      );

      expect(result.isOk, isTrue);

      final RecordedRequest commit = server.requests.firstWhere(
        (RecordedRequest r) => r.path.endsWith(':commit'),
      );
      // The token from the refresh is carried as the bearer credential.
      expect(commit.authorization, 'Bearer id-token-for-restaurant-abc');

      final Map<String, dynamic> body = commit.json! as Map<String, dynamic>;
      final Map<String, dynamic> update =
          (body['writes'] as List<dynamic>).first['update']
              as Map<String, dynamic>;
      // Scoped under the restaurant, in the camelCase collection, keyed by entity id.
      expect(
        update['name'],
        'projects/brisko-pos/databases/(default)/documents/restaurants/'
        'restaurant-abc/orders/ord_1',
      );
      // Fields are Firestore-typed: an int as a string integerValue, a null as nullValue.
      final Map<String, dynamic> fields =
          update['fields'] as Map<String, dynamic>;
      expect(fields['totalAmountPaise'], <String, dynamic>{
        'integerValue': '45000',
      });
      expect(fields['customerId'], <String, dynamic>{'nullValue': null});
    },
  );

  test('the same id upserts in place, so a replay cannot duplicate', () async {
    server.responder = backend(uid: 'restaurant-abc');
    final FirestoreRestClient client = clientFor(server);

    final Map<String, dynamic> row = <String, dynamic>{
      'id': 'ord_1',
      'updatedAt': 1750000000000,
    };
    await client.upsert('orders', <Map<String, dynamic>>[row]);
    await client.upsert('orders', <Map<String, dynamic>>[row]);

    final List<RecordedRequest> commits = server.requests
        .where((RecordedRequest r) => r.path.endsWith(':commit'))
        .toList();
    // Both writes target the identical document path — Firestore overwrites, never
    // appends, because the id is the document id.
    for (final RecordedRequest commit in commits) {
      final Map<String, dynamic> update =
          ((commit.json! as Map<String, dynamic>)['writes'] as List<dynamic>)
                  .first['update']
              as Map<String, dynamic>;
      expect(update['name'], endsWith('/orders/ord_1'));
    }
  });

  test(
    'a different signed-in restaurant is scoped to a different path',
    () async {
      server.responder = backend(uid: 'restaurant-other');
      final FirestoreRestClient client = clientFor(server);

      await client.upsert('orders', <Map<String, dynamic>>[
        <String, dynamic>{'id': 'ord_9', 'updatedAt': 1},
      ]);

      final RecordedRequest commit = server.requests.firstWhere(
        (RecordedRequest r) => r.path.endsWith(':commit'),
      );
      final String name =
          (((commit.json! as Map<String, dynamic>)['writes'] as List<dynamic>)
                      .first['update']
                  as Map<String, dynamic>)['name']
              as String;
      expect(name, contains('/restaurants/restaurant-other/'));
      expect(name, isNot(contains('restaurant-abc')));
    },
  );

  test('selectChangedSince runs a filtered, ordered query and decodes rows', () async {
    server.responder = backend(
      uid: 'restaurant-abc',
      queryDocuments: <Map<String, dynamic>>[
        // A leading read-time-only marker, as Firestore sends; must be skipped.
        <String, dynamic>{'readTime': '2026-06-01T00:00:00Z'},
        <String, dynamic>{
          'document': <String, dynamic>{
            'name': 'projects/brisko-pos/.../orders/ord_1',
            'fields': <String, dynamic>{
              'id': <String, dynamic>{'stringValue': 'ord_1'},
              'updatedAt': <String, dynamic>{'integerValue': '1750000005000'},
              'totalAmountPaise': <String, dynamic>{'integerValue': '45000'},
            },
          },
        },
      ],
    );
    final FirestoreRestClient client = clientFor(server);

    final Result<List<Map<String, dynamic>>> result = await client
        .selectChangedSince('orders', 1750000000000);

    final List<Map<String, dynamic>> rows = result.valueOrNull!;
    expect(rows, hasLength(1));
    expect(rows.first['id'], 'ord_1');
    expect(rows.first['updatedAt'], 1750000005000);
    expect(rows.first['totalAmountPaise'], isA<int>());

    // The query filtered on updatedAt > cursor and ordered ascending.
    final RecordedRequest query = server.requests.firstWhere(
      (RecordedRequest r) => r.path.endsWith(':runQuery'),
    );
    expect(query.path, endsWith('/restaurants/restaurant-abc:runQuery'));
    final Map<String, dynamic> structured =
        (query.json! as Map<String, dynamic>)['structuredQuery']
            as Map<String, dynamic>;
    expect(
      (structured['from'] as List<dynamic>).first['collectionId'],
      'orders',
    );
    expect(structured['where']['fieldFilter']['op'], 'GREATER_THAN');
    expect(structured['where']['fieldFilter']['value'], <String, dynamic>{
      'integerValue': '1750000000000',
    });
  });

  test('a full pull (null cursor) omits the filter but still orders', () async {
    server.responder = backend(uid: 'restaurant-abc');
    final FirestoreRestClient client = clientFor(server);

    await client.selectChangedSince('customers', null);

    final RecordedRequest query = server.requests.firstWhere(
      (RecordedRequest r) => r.path.endsWith(':runQuery'),
    );
    final Map<String, dynamic> structured =
        (query.json! as Map<String, dynamic>)['structuredQuery']
            as Map<String, dynamic>;
    expect(structured.containsKey('where'), isFalse);
    expect(structured.containsKey('orderBy'), isTrue);
  });

  test(
    'a soft delete patches only the deleted flag via an update mask',
    () async {
      server.responder = backend(uid: 'restaurant-abc');
      final FirestoreRestClient client = clientFor(server);

      await client.markDeleted('orders', 'ord_1');

      final RecordedRequest commit = server.requests.firstWhere(
        (RecordedRequest r) => r.path.endsWith(':commit'),
      );
      final Map<String, dynamic> write =
          ((commit.json! as Map<String, dynamic>)['writes'] as List<dynamic>)
                  .first
              as Map<String, dynamic>;
      expect(
        (write['updateMask'] as Map<String, dynamic>)['fieldPaths'],
        containsAll(<String>['isDeleted', 'updatedAt', 'syncState']),
      );
      final Map<String, dynamic> fields =
          (write['update'] as Map<String, dynamic>)['fields']
              as Map<String, dynamic>;
      expect(fields['isDeleted'], <String, dynamic>{'integerValue': '1'});
    },
  );

  test(
    'when sign-in is refused, nothing is uploaded and it surfaces',
    () async {
      // The token endpoint refuses; the commit must never be attempted.
      server.responder = (RecordedRequest request) async {
        if (request.path.contains('/securetoken/')) {
          return HttpResponseSpec(400, '{"error":{"message":"INVALID"}}');
        }
        return const HttpResponseSpec(200, '{}');
      };
      final FirestoreRestClient client = clientFor(server);

      final Result<void> result = await client.upsert(
        'orders',
        <Map<String, dynamic>>[
          <String, dynamic>{'id': 'ord_1', 'updatedAt': 1},
        ],
      );

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<RemoteFailure>());
      expect(
        server.requests.any((RecordedRequest r) => r.path.endsWith(':commit')),
        isFalse,
      );
    },
  );

  test('a server refusal on commit is a RemoteFailure', () async {
    server.responder = (RecordedRequest request) async {
      if (request.path.contains('/securetoken/')) {
        return HttpResponseSpec(
          200,
          jsonEncode(<String, dynamic>{
            'id_token': 'id-token',
            'refresh_token': 'r',
            'user_id': 'restaurant-abc',
            'expires_in': '3600',
          }),
        );
      }
      return const HttpResponseSpec(403, '{"error":{"message":"PERMISSION"}}');
    };
    final FirestoreRestClient client = clientFor(server);

    final Result<void> result = await client.upsert(
      'orders',
      <Map<String, dynamic>>[
        <String, dynamic>{'id': 'ord_1', 'updatedAt': 1},
      ],
    );

    expect(result.failureOrNull, isA<RemoteFailure>());
  });

  test(
    'an unreachable Firestore host is a NetworkFailure, leaving work queued',
    () async {
      server.responder = backend(uid: 'restaurant-abc');

      // A client whose Firestore base points at a closed port, but whose token
      // refresh still succeeds against the live server.
      final FirebaseAuthClient authClient = FirebaseAuthClient(
        config: config,
        secureTokenBaseUrl: '${server.baseUrl}/securetoken/v1',
      );
      final FirebaseAuthSession session = FirebaseAuthSession(
        config: config,
        authClient: authClient,
      );
      final RecordingHttpServer dead = await RecordingHttpServer.start();
      final String deadBase = dead.baseUrl;
      await dead.close();

      final FirestoreRestClient client = FirestoreRestClient(
        config: config,
        session: session,
        baseUrl: '$deadBase/v1',
      );

      final Result<void> result = await client.upsert(
        'orders',
        <Map<String, dynamic>>[
          <String, dynamic>{'id': 'ord_1', 'updatedAt': 1},
        ],
      );

      expect(result.failureOrNull, isA<NetworkFailure>());
    },
  );
}
