import 'package:brisko_billing/core/data/local/sqlite/sqlite_tables.dart';
import 'package:brisko_billing/core/data/remote/firebase/firestore_value.dart';
import 'package:flutter_test/flutter_test.dart';

/// The value mapping is the one place an entity row meets Firestore's typed-value
/// wire format, so it has to round-trip exactly: encode a stored row, decode it back,
/// and get the same primitives a SQLite read would hand `fromRow`.
void main() {
  group('FirestoreValue', () {
    test('encodes each primitive with its Firestore type tag', () {
      expect(FirestoreValue.encode(null), <String, dynamic>{'nullValue': null});
      expect(FirestoreValue.encode(true), <String, dynamic>{
        'booleanValue': true,
      });
      // Integers travel as strings so 64-bit values survive JSON.
      expect(FirestoreValue.encode(1500), <String, dynamic>{
        'integerValue': '1500',
      });
      expect(FirestoreValue.encode('takeaway'), <String, dynamic>{
        'stringValue': 'takeaway',
      });
    });

    test('decodes each Firestore type tag back to a primitive', () {
      expect(FirestoreValue.decode(<String, dynamic>{'nullValue': null}), null);
      expect(
        FirestoreValue.decode(<String, dynamic>{'booleanValue': true}),
        true,
      );
      // A string-encoded integer comes back as an int, which is what fromRow expects.
      expect(
        FirestoreValue.decode(<String, dynamic>{'integerValue': '1500'}),
        1500,
      );
      expect(
        FirestoreValue.decode(<String, dynamic>{'stringValue': 'takeaway'}),
        'takeaway',
      );
    });

    test('an unknown value shape decodes as absent rather than throwing', () {
      expect(
        FirestoreValue.decode(<String, dynamic>{
          'timestampValue': '2026-01-01T00:00:00Z',
        }),
        null,
      );
      expect(FirestoreValue.decode('not a map'), null);
    });

    test('a whole row round-trips through encode then decode unchanged', () {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': 'ord_123',
        'createdAt': 1750000000000,
        'updatedAt': 1750000009999,
        'isDeleted': 0,
        'syncState': 'pending',
        'orderNumber': '20260601-0001',
        'totalAmountPaise': 45000,
        'customerId': null,
        'notes': null,
      };

      final Map<String, dynamic> fields = FirestoreValue.encodeFields(row);
      final Map<String, Object?> back = FirestoreValue.decodeFields(fields);

      expect(back, row);
      // Types survive: the money field is an int, not a string, on the way back.
      expect(back['totalAmountPaise'], isA<int>());
      expect(back['customerId'], isNull);
    });
  });

  group('FirestoreCollections', () {
    test('maps local table names to clean camelCase Firestore collections', () {
      expect(FirestoreCollections.resolve(SqliteTables.orders), 'orders');
      expect(
        FirestoreCollections.resolve(SqliteTables.orderItems),
        'orderItems',
      );
      expect(FirestoreCollections.resolve(SqliteTables.menuItems), 'menuItems');
      expect(
        FirestoreCollections.resolve(SqliteTables.kotItemOptions),
        'kotItemOptions',
      );
      expect(
        FirestoreCollections.resolve(SqliteTables.orderInventoryDeductions),
        'orderInventoryDeductions',
      );
    });

    test('every synced table has an explicit mapping', () {
      const List<String> syncedTables = <String>[
        SqliteTables.categories,
        SqliteTables.menuItems,
        SqliteTables.menuItemVariants,
        SqliteTables.menuItemOptions,
        SqliteTables.inventoryItems,
        SqliteTables.recipeIngredients,
        SqliteTables.stockMovements,
        SqliteTables.customers,
        SqliteTables.orders,
        SqliteTables.orderItems,
        SqliteTables.orderItemOptions,
        SqliteTables.payments,
        SqliteTables.refunds,
        SqliteTables.orderInventoryDeductions,
        SqliteTables.kotRecords,
        SqliteTables.kotItems,
        SqliteTables.kotItemOptions,
      ];
      for (final String table in syncedTables) {
        // A mapped collection is camelCase, never the snake_case table name.
        expect(FirestoreCollections.resolve(table), isNot(contains('_')));
      }
    });
  });
}
