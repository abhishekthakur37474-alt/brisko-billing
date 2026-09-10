import '../../../../core/utils/result.dart';
import '../models/kot_item.dart';
import '../models/kot_record.dart';
import '../models/kot_status.dart';

/// Read and write access to kitchen slips.
///
/// Records what the kitchen was asked to make. Producing the paper slip is the
/// printing module's job and is not implemented yet.
abstract interface class KotRepository {
  /// Creates a slip and its lines atomically.
  Future<Result<void>> createKot(KotRecord record, List<KotItem> items);

  Future<Result<KotRecord?>> findKot(String id);

  /// Slips raised against an order, oldest first. More than one is normal when
  /// items were added after the first slip went to the kitchen.
  Future<Result<List<KotRecord>>> loadForOrder(String orderId);

  Future<Result<List<KotItem>>> loadItems(String kotId);

  /// Slips still waiting to be printed, across all orders.
  Future<Result<List<KotRecord>>> loadPending();

  /// Reserves the next slip number for today.
  Future<Result<String>> nextKotNumber();

  Future<Result<void>> updateStatus(String kotId, KotStatus status);
}
