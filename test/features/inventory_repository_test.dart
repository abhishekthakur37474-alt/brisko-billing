import 'package:brisko_billing/core/data/local/sqlite/sqlite_database.dart';
import 'package:brisko_billing/features/inventory/data/repositories/sqlite_inventory_repository.dart';
import 'package:brisko_billing/features/inventory/domain/models/inventory_item.dart';
import 'package:brisko_billing/features/inventory/domain/models/stock_movement.dart';
import 'package:brisko_billing/features/inventory/domain/models/stock_movement_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_database.dart';

void main() {
  setUpAll(TestDatabase.register);

  late SqliteDatabase database;
  late SqliteInventoryRepository inventory;

  setUp(() async {
    database = await TestDatabase.openInMemory();
    inventory = SqliteInventoryRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  group('quantity representation', () {
    test('parses and formats thousandths without floating point', () {
      expect(InventoryItem.parseQuantity('10'), 10000);
      expect(InventoryItem.parseQuantity('2.5'), 2500);
      expect(InventoryItem.parseQuantity('0.125'), 125);
      expect(InventoryItem.formatQuantity(2500), '2.5');
      expect(InventoryItem.formatQuantity(10000), '10');
      expect(InventoryItem.formatQuantity(125), '0.125');
    });

    test('rejects more precision than thousandths', () {
      expect(
        () => InventoryItem.parseQuantity('1.0001'),
        throwsFormatException,
      );
    });
  });

  group('items', () {
    test('an item can be saved and retrieved', () async {
      final InventoryItem item = Fixtures.inventoryItem(
        name: 'Test Cheese',
        unit: 'kg',
        currentQuantity: '10',
        minimumQuantity: '2',
      );
      expect((await inventory.saveItem(item)).isOk, isTrue);

      final InventoryItem? loaded = (await inventory.findItem(item.id))
          .valueOrNull;

      expect(loaded, isNotNull);
      expect(loaded!.name, 'Test Cheese');
      expect(loaded.unit, 'kg');
      expect(loaded.currentQuantityMilli, 10000);
      expect(loaded.currentQuantityDisplay, '10');
    });
  });

  group('stock movements', () {
    late InventoryItem item;

    setUp(() async {
      item = Fixtures.inventoryItem(
        currentQuantity: '10',
        minimumQuantity: '2',
      );
      await inventory.saveItem(item);
    });

    test(
      'a purchase increases the balance and is recorded in the ledger',
      () async {
        final StockMovement movement = (await inventory.recordMovement(
          inventoryItemId: item.id,
          type: StockMovementType.purchase,
          quantityMilli: InventoryItem.parseQuantity('5.5'),
          reason: 'test delivery',
        )).valueOrNull!;

        expect(movement.movementType, StockMovementType.purchase);
        expect(movement.signedQuantityMilli, 5500);

        final InventoryItem updated = (await inventory.findItem(item.id))
            .valueOrNull!;
        expect(updated.currentQuantityMilli, 15500);
        expect(updated.currentQuantityDisplay, '15.5');

        final List<StockMovement> ledger = (await inventory.loadMovements(
          item.id,
        )).valueOrNull!;
        expect(ledger, hasLength(1));
        expect(ledger.single.reason, 'test delivery');
      },
    );

    test('a sale decreases the balance', () async {
      await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.sale,
        quantityMilli: InventoryItem.parseQuantity('3'),
        referenceId: 'ord-test-1',
      );

      final InventoryItem updated = (await inventory.findItem(item.id))
          .valueOrNull!;
      expect(updated.currentQuantityMilli, 7000);
    });

    test('wastage decreases the balance', () async {
      await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.wastage,
        quantityMilli: InventoryItem.parseQuantity('1.25'),
        reason: 'spoiled',
      );

      expect(
        (await inventory.findItem(item.id)).valueOrNull!.currentQuantityMilli,
        8750,
      );
    });

    test('an adjustment carries its own sign', () async {
      // A physical count can correct in either direction.
      await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.adjustment,
        quantityMilli: -2000,
        reason: 'monthly count',
      );

      expect(
        (await inventory.findItem(item.id)).valueOrNull!.currentQuantityMilli,
        8000,
      );
    });

    test('the balance stays exact over many fractional movements', () async {
      for (int i = 0; i < 100; i++) {
        await inventory.recordMovement(
          inventoryItemId: item.id,
          type: StockMovementType.sale,
          quantityMilli: InventoryItem.parseQuantity('0.001'),
        );
      }

      // 10 kg less 100 grams-of-a-gram, with no drift.
      expect(
        (await inventory.findItem(item.id)).valueOrNull!.currentQuantityMilli,
        10000 - 100,
      );
    });

    test('a movement of zero is rejected', () async {
      final result = await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.adjustment,
        quantityMilli: 0,
      );
      expect(result.isErr, isTrue);
    });

    test(
      'a movement against a missing item fails and records nothing',
      () async {
        final result = await inventory.recordMovement(
          inventoryItemId: 'inv-does-not-exist',
          type: StockMovementType.purchase,
          quantityMilli: 1000,
        );
        expect(result.isErr, isTrue);

        final List<Map<String, Object?>> rows = await database.database.query(
          'stock_movements',
        );
        expect(rows, isEmpty, reason: 'the transaction must have rolled back');
      },
    );

    test('the ledger is returned newest first', () async {
      await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.purchase,
        quantityMilli: 1000,
        reason: 'first',
      );
      await inventory.recordMovement(
        inventoryItemId: item.id,
        type: StockMovementType.purchase,
        quantityMilli: 1000,
        reason: 'second',
      );

      final List<StockMovement> ledger = (await inventory.loadMovements(
        item.id,
      )).valueOrNull!;
      expect(ledger, hasLength(2));
      expect(ledger.first.reason, 'second');
    });
  });

  group('low stock', () {
    test('an item at or below its threshold is reported', () async {
      final InventoryItem low = Fixtures.inventoryItem(
        name: 'Test Low',
        currentQuantity: '2',
        minimumQuantity: '2',
      );
      final InventoryItem healthy = Fixtures.inventoryItem(
        name: 'Test Healthy',
        currentQuantity: '50',
        minimumQuantity: '5',
      );
      await inventory.saveItem(low);
      await inventory.saveItem(healthy);

      final List<InventoryItem> reported =
          (await inventory.loadLowStockItems()).valueOrNull!;

      expect(reported.map((InventoryItem i) => i.name), <String>['Test Low']);
      expect(low.isLow, isTrue);
      expect(healthy.isLow, isFalse);
    });

    test('an item with no threshold is never reported as low', () async {
      // A minimum of zero means "not monitored", not "always low".
      final InventoryItem unmonitored = Fixtures.inventoryItem(
        name: 'Test Unmonitored',
        currentQuantity: '0',
        minimumQuantity: '0',
      );
      await inventory.saveItem(unmonitored);

      expect((await inventory.loadLowStockItems()).valueOrNull, isEmpty);
      expect(unmonitored.isLow, isFalse);
    });
  });

  group('soft delete', () {
    test('a deleted item is hidden but its row remains', () async {
      final InventoryItem item = Fixtures.inventoryItem();
      await inventory.saveItem(item);

      expect((await inventory.deleteItem(item.id)).isOk, isTrue);

      expect((await inventory.findItem(item.id)).valueOrNull, isNull);
      expect((await inventory.loadItems()).valueOrNull, isEmpty);

      final List<Map<String, Object?>> raw = await database.database.query(
        'inventory_items',
        where: 'id = ?',
        whereArgs: <Object?>[item.id],
      );
      expect(raw.single['isDeleted'], 1);
    });
  });
}
