import 'package:brisko_billing/core/data/local/sqlite/sqlite_database.dart';
import 'package:brisko_billing/features/customers/data/repositories/sqlite_customer_repository.dart';
import 'package:brisko_billing/features/customers/domain/models/customer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(TestDatabase.register);

  late SqliteDatabase database;
  late SqliteCustomerRepository customers;

  setUp(() async {
    database = await TestDatabase.openInMemory();
    customers = SqliteCustomerRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('a customer can be saved and retrieved by phone', () async {
    final Customer customer = Fixtures.customer(
      phone: '9812300001',
      name: 'Test Customer',
    );
    expect((await customers.save(customer)).isOk, isTrue);

    final Customer? found = (await customers.findByPhone('9812300001'))
        .valueOrNull;
    expect(found, isNotNull);
    expect(found!.id, customer.id);
    expect(found.name, 'Test Customer');
  });

  test('an unknown phone number returns null rather than failing', () async {
    final result = await customers.findByPhone('0000000000');
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isNull);
  });

  test('lookup ignores surrounding whitespace', () async {
    await customers.save(Fixtures.customer(phone: '9812300002'));
    expect(
      (await customers.findByPhone('  9812300002  ')).valueOrNull,
      isNotNull,
    );
  });

  test('findOrCreateByPhone creates once and reuses thereafter', () async {
    final Customer created = (await customers.findOrCreateByPhone(
      '9812300003',
      name: 'First',
    )).valueOrNull!;
    final Customer reused = (await customers.findOrCreateByPhone('9812300003'))
        .valueOrNull!;

    expect(reused.id, created.id);
    expect((await customers.loadAll()).valueOrNull, hasLength(1));
  });

  test('findOrCreateByPhone rejects an empty number', () async {
    final result = await customers.findOrCreateByPhone('   ');
    expect(result.isErr, isTrue);
  });

  test('a customer with no name falls back to the phone number', () async {
    final Customer created = (await customers.findOrCreateByPhone('9812300004'))
        .valueOrNull!;
    expect(created.name, isNull);
    expect(created.displayName, '9812300004');
  });

  test('search matches on partial phone or name', () async {
    await customers.save(
      Fixtures.customer(phone: '9812345678', name: 'Test Alpha'),
    );
    await customers.save(
      Fixtures.customer(phone: '9887654321', name: 'Test Beta'),
    );

    expect((await customers.search('98123')).valueOrNull, hasLength(1));
    expect((await customers.search('Beta')).valueOrNull, hasLength(1));
    expect((await customers.search('Test')).valueOrNull, hasLength(2));
  });

  test('a soft-deleted customer is hidden from lookup', () async {
    final Customer customer = Fixtures.customer(phone: '9812300005');
    await customers.save(customer);

    expect((await customers.delete(customer.id)).isOk, isTrue);

    expect((await customers.findByPhone('9812300005')).valueOrNull, isNull);
    expect((await customers.findById(customer.id)).valueOrNull, isNull);
    expect((await customers.loadAll()).valueOrNull, isEmpty);

    // Row retained so the deletion can be synchronised later.
    final List<Map<String, Object?>> raw = await database.database.query(
      'customers',
      where: 'id = ?',
      whereArgs: <Object?>[customer.id],
    );
    expect(raw.single['isDeleted'], 1);
  });
}
