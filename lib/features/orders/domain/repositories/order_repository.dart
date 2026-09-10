import '../../../../core/utils/result.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/order_item_option.dart';
import '../models/order_status.dart';

/// Read and write access to orders and their lines.
abstract interface class OrderRepository {
  /// Saves an order together with its lines and their options, atomically.
  ///
  /// One call rather than three, because a bill with a header but no lines is not
  /// a valid business record. Either all of it lands or none of it does.
  Future<Result<void>> saveOrder(
    Order order, {
    List<OrderItem> items,
    List<OrderItemOption> itemOptions,
  });

  Future<Result<Order?>> findOrder(String id);

  Future<Result<Order?>> findOrderByNumber(String orderNumber);

  /// Lines on an order, in the sequence they were added.
  Future<Result<List<OrderItem>>> loadItems(String orderId);

  /// Options applied to one line.
  Future<Result<List<OrderItemOption>>> loadItemOptions(String orderItemId);

  /// Orders within a time window, newest first.
  ///
  /// [from] is inclusive and [to] exclusive, which makes "one day" expressible
  /// without worrying about the last millisecond of the day.
  Future<Result<List<Order>>> loadOrders({
    DateTime? from,
    DateTime? to,
    OrderStatus? status,
    int limit,
  });

  /// A customer's order history, newest first.
  ///
  /// Derived from the orders table rather than stored on the customer, so it can
  /// never disagree with the bills themselves.
  Future<Result<List<Order>>> loadOrdersForCustomer(String customerId);

  /// Reserves the next human-readable order number for today.
  Future<Result<String>> nextOrderNumber();

  Future<Result<void>> updateStatus(String orderId, OrderStatus status);

  /// Soft-deletes the order. Lines are left in place and are unreachable through
  /// [loadItems] only if they are themselves deleted, so history stays auditable.
  Future<Result<void>> deleteOrder(String id);
}
