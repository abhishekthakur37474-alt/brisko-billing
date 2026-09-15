import '../../local/sqlite/sqlite_tables.dart';

/// Translates between an entity's stored row and Cloud Firestore's typed-value
/// wire format.
///
/// Firestore does not accept bare JSON: every field is tagged with its type, so an
/// integer travels as `{"integerValue": "42"}` and a string as
/// `{"stringValue": "…"}`. An entity's `toMap` produces only the primitives the local
/// SQLite row holds — integers (millisecond timestamps, paise, 0/1 flags), strings,
/// and nulls — so the mapping is small and total, and it round-trips: encoding a row
/// and decoding it back yields the same map a SQLite read would, which is exactly what
/// [FirestoreRemoteStore] relies on to rebuild an entity with the same `fromRow` the
/// local store uses.
class FirestoreValue {
  const FirestoreValue._();

  /// Encodes one entity row into Firestore's `fields` map.
  static Map<String, dynamic> encodeFields(Map<String, dynamic> row) {
    return <String, dynamic>{
      for (final MapEntry<String, dynamic> entry in row.entries)
        entry.key: encode(entry.value),
    };
  }

  /// Decodes a Firestore `fields` map back into an entity row.
  static Map<String, Object?> decodeFields(Map<String, dynamic> fields) {
    return <String, Object?>{
      for (final MapEntry<String, dynamic> entry in fields.entries)
        entry.key: decode(entry.value),
    };
  }

  /// Encodes one primitive into a Firestore typed value.
  static Map<String, dynamic> encode(Object? value) {
    if (value == null) {
      return <String, dynamic>{'nullValue': null};
    }
    if (value is bool) {
      return <String, dynamic>{'booleanValue': value};
    }
    if (value is int) {
      // Firestore integers travel as strings so 64-bit values survive JSON.
      return <String, dynamic>{'integerValue': value.toString()};
    }
    if (value is double) {
      return <String, dynamic>{'doubleValue': value};
    }
    if (value is String) {
      return <String, dynamic>{'stringValue': value};
    }
    // The stored rows never reach here, but a stray type is stringified rather than
    // allowed to abort an upload of everything else in the batch.
    return <String, dynamic>{'stringValue': value.toString()};
  }

  /// Decodes a Firestore typed value back into a primitive.
  static Object? decode(Object? value) {
    if (value is! Map) {
      return null;
    }
    if (value.containsKey('nullValue')) {
      return null;
    }
    if (value.containsKey('booleanValue')) {
      return value['booleanValue'] as bool?;
    }
    if (value.containsKey('integerValue')) {
      final Object? raw = value['integerValue'];
      if (raw is int) {
        return raw;
      }
      return int.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('doubleValue')) {
      final Object? raw = value['doubleValue'];
      return raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    }
    if (value.containsKey('stringValue')) {
      return value['stringValue'] as String?;
    }
    // timestampValue, mapValue, arrayValue and friends are never written by this
    // client, so an unknown shape reads as absent rather than crashing a pull.
    return null;
  }
}

/// Maps a local SQLite table name to the Cloud Firestore collection id used beneath
/// each restaurant document.
///
/// The cloud representation is deliberately not a carbon copy of the SQLite/Postgres
/// naming: Firestore collections read as camelCase (`orderItems`, `menuItems`) so the
/// document tree is clean for any other client on the same project, including the
/// future Android app. This is the single place that translation lives, so the sync
/// engine keeps speaking in local table names and never has to know the cloud's names.
class FirestoreCollections {
  const FirestoreCollections._();

  static const Map<String, String> _byTable = <String, String>{
    SqliteTables.categories: 'categories',
    SqliteTables.menuItems: 'menuItems',
    SqliteTables.menuItemVariants: 'menuItemVariants',
    SqliteTables.menuItemOptions: 'menuItemOptions',
    SqliteTables.inventoryItems: 'inventoryItems',
    SqliteTables.recipeIngredients: 'recipeIngredients',
    SqliteTables.stockMovements: 'stockMovements',
    SqliteTables.customers: 'customers',
    SqliteTables.orders: 'orders',
    SqliteTables.orderItems: 'orderItems',
    SqliteTables.orderItemOptions: 'orderItemOptions',
    SqliteTables.payments: 'payments',
    SqliteTables.refunds: 'refunds',
    SqliteTables.orderInventoryDeductions: 'orderInventoryDeductions',
    SqliteTables.kotRecords: 'kotRecords',
    SqliteTables.kotItems: 'kotItems',
    SqliteTables.kotItemOptions: 'kotItemOptions',
  };

  /// The Firestore collection id for [table]. Falls back to the table name itself for
  /// any collection not in the map, so an unmapped table still syncs to a sane place
  /// rather than failing.
  static String resolve(String table) => _byTable[table] ?? table;
}
