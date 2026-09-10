import '../../../../core/utils/result.dart';
import '../models/inventory_item.dart';
import '../models/stock_movement.dart';
import '../models/stock_movement_type.dart';

/// Read and write access to stock.
///
/// Basic tracking only: items, a running balance, and a ledger of movements. There
/// is no recipe engine, no automatic deduction when a pizza is sold, and no
/// warehouse or transfer concept.
abstract interface class InventoryRepository {
  Future<Result<List<InventoryItem>>> loadItems();

  Stream<List<InventoryItem>> watchItems();

  Future<Result<InventoryItem?>> findItem(String id);

  /// Items at or below their reorder threshold.
  Future<Result<List<InventoryItem>>> loadLowStockItems();

  Future<Result<void>> saveItem(InventoryItem item);

  /// Records a movement and adjusts the item's running balance atomically.
  ///
  /// Both in one operation because a ledger entry without a balance change, or the
  /// reverse, leaves the stock figures wrong with no way to tell which is right.
  ///
  /// [quantityMilli] is in thousandths of the item's unit. For a purchase, sale or
  /// wastage it is unsigned and the direction comes from [type]; for an adjustment
  /// it is signed.
  Future<Result<StockMovement>> recordMovement({
    required String inventoryItemId,
    required StockMovementType type,
    required int quantityMilli,
    String? reason,
    String? referenceId,
  });

  /// Ledger for one item, newest first.
  Future<Result<List<StockMovement>>> loadMovements(
    String inventoryItemId, {
    int limit,
  });

  Future<Result<void>> deleteItem(String id);
}
