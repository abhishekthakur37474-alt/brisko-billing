import 'package:sqflite/sqflite.dart';

import '../../../../core/data/local/sqlite/sqlite_database.dart';
import '../../../../core/data/local/sqlite/sqlite_error_mapper.dart';
import '../../../../core/data/local/sqlite/sqlite_local_store.dart';
import '../../../../core/data/local/sqlite/sqlite_tables.dart';
import '../../../../core/utils/entity_id.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/customer.dart';
import '../../domain/repositories/customer_repository.dart';

/// SQLite implementation of [CustomerRepository].
class SqliteCustomerRepository implements CustomerRepository {
  SqliteCustomerRepository({required SqliteDatabase database})
    : _database = database,
      _customers = SqliteLocalStore<Customer>(
        database: database,
        table: SqliteTables.customers,
        fromRow: Customer.fromRow,
        orderBy: 'name ASC, phone ASC',
      );

  final SqliteDatabase _database;
  final SqliteLocalStore<Customer> _customers;

  Database get _db => _database.database;

  @override
  Future<Result<Customer?>> findByPhone(String phone) {
    return SqliteErrorMapper.guard<Customer?>(() async {
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.customers,
        where: 'phone = ? AND isDeleted = 0',
        whereArgs: <Object?>[phone.trim()],
        // Oldest first, so a duplicate created later never shadows the record
        // that carries the longer history.
        orderBy: 'createdAt ASC',
        limit: 1,
      );
      return rows.isEmpty ? null : Customer.fromRow(rows.first);
    }, context: 'find the customer');
  }

  @override
  Future<Result<Customer?>> findById(String id) => _customers.findById(id);

  @override
  Future<Result<List<Customer>>> search(String query, {int limit = 25}) {
    return SqliteErrorMapper.guard<List<Customer>>(() async {
      final String pattern = '%${query.trim()}%';
      final List<Map<String, Object?>> rows = await _db.query(
        SqliteTables.customers,
        where: 'isDeleted = 0 AND (phone LIKE ? OR name LIKE ?)',
        whereArgs: <Object?>[pattern, pattern],
        orderBy: 'name ASC, phone ASC',
        limit: limit,
      );
      return rows.map(Customer.fromRow).toList(growable: false);
    }, context: 'search customers');
  }

  @override
  Future<Result<List<Customer>>> loadAll() => _customers.findAll();

  @override
  Future<Result<void>> save(Customer customer) => _customers.save(customer);

  @override
  Future<Result<Customer>> findOrCreateByPhone(String phone, {String? name}) {
    return SqliteErrorMapper.guard<Customer>(() async {
      final String normalised = phone.trim();
      if (normalised.isEmpty) {
        throw ArgumentError.value(phone, 'phone', 'Must not be empty');
      }

      // Lookup and insert in one transaction so two rapid entries of the same
      // number cannot both decide the customer is missing.
      return _db
          .transaction<Customer>((Transaction txn) async {
            final List<Map<String, Object?>> existing = await txn.query(
              SqliteTables.customers,
              where: 'phone = ? AND isDeleted = 0',
              whereArgs: <Object?>[normalised],
              orderBy: 'createdAt ASC',
              limit: 1,
            );

            if (existing.isNotEmpty) {
              return Customer.fromRow(existing.first);
            }

            final DateTime now = DateTime.now().toUtc();
            final Customer created = Customer(
              id: EntityId.generate(prefix: 'cus'),
              name: name,
              phone: normalised,
              createdAt: now,
              updatedAt: now,
            );

            await txn.insert(SqliteTables.customers, created.toMap());
            return created;
          })
          .then((Customer customer) {
            _database.notifyTableChanged(SqliteTables.customers);
            return customer;
          });
    }, context: 'save the customer');
  }

  @override
  Future<Result<void>> delete(String id) => _customers.softDelete(id);
}
