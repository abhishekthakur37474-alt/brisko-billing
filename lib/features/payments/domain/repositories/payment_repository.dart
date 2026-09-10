import '../../../../core/money/money.dart';
import '../../../../core/utils/result.dart';
import '../models/payment.dart';

/// Read and write access to payments.
abstract interface class PaymentRepository {
  Future<Result<void>> record(Payment payment);

  /// Every payment against an order, oldest first. Several rows means a split
  /// payment.
  Future<Result<List<Payment>>> loadForOrder(String orderId);

  /// Total of the settled payments against an order.
  ///
  /// Only completed payments count, so a pending UPI attempt does not make a bill
  /// look paid.
  Future<Result<Money>> settledTotalForOrder(String orderId);

  Future<Result<void>> updateStatusFor(String paymentId, Payment payment);

  Future<Result<void>> delete(String id);
}
