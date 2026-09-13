import 'package:flutter/foundation.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/result.dart';
import '../../../customers/domain/models/customer.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../payments/domain/models/payment.dart';
import '../../../payments/domain/models/payment_method.dart';
import '../../../payments/domain/models/payment_status.dart';
import '../../../payments/domain/models/refund.dart';
import '../../../payments/domain/models/refund_request.dart';
import '../../../payments/domain/models/refundable_bill.dart';
import '../../../payments/domain/repositories/payment_repository.dart';
import '../../../payments/domain/repositories/refund_repository.dart';
import '../../domain/models/bill_line_snapshot.dart';
import '../../domain/models/order.dart';
import '../../domain/repositories/order_repository.dart';

/// Holds one stored bill, exactly as it was written.
///
/// ## The one rule this file exists to keep
///
/// Every figure it exposes was read from `orders`, `order_items`, `order_item_options`
/// or `payments`. There is no `MenuRepository` here and there cannot be one: looking up
/// a current price to display a historical bill would mean a receipt reprinted next
/// month disagreed with the one the customer was handed, and a bill whose product has
/// since been deleted could not be opened at all.
///
/// ## Money
///
/// Totals are the persisted [Money] values in integer paise. Nothing is recalculated,
/// nothing is parsed from a string, and [linesTotal] exists only so a reader can see
/// that the stored lines add up to the stored subtotal — not to replace it.
///
/// ## Failure
///
/// Nothing throws. A read that fails becomes [errorMessage] with no bill attached, which
/// the view renders as a notice with a retry.
///
/// ## Refunding
///
/// This is the one thing here that writes. [refund] hands back the whole of what the bill
/// collected and is the only mutation on the controller; everything else is a read of a
/// document that must never change.
///
/// The controller decides nothing about whether a refund is allowed. It shows the figures
/// [RefundableBill] derived and calls [RefundRepository.refund], which re-reads and
/// re-decides the whole thing inside the transaction that writes it. A screen's idea of
/// what is refundable is always slightly stale, so it is used to draw a button and never to
/// authorise money.
///
/// [refundError] is kept separate from [errorMessage] on purpose: a refund that was refused
/// must not blank out the bill behind it. The document is still perfectly readable and the
/// cashier needs to see it while being told why the refund did not happen.
class BillDetailController extends ChangeNotifier {
  BillDetailController({
    required this._orderId,
    required OrderRepository orderRepository,
    required PaymentRepository paymentRepository,
    required CustomerRepository customerRepository,
    required RefundRepository refundRepository,
  }) : _orders = orderRepository,
       _payments = paymentRepository,
       _customers = customerRepository,
       _refunds = refundRepository;

  final String _orderId;
  final OrderRepository _orders;
  final PaymentRepository _payments;
  final CustomerRepository _customers;
  final RefundRepository _refunds;

  Order? _order;
  List<BillLineSnapshot> _lines = const <BillLineSnapshot>[];
  List<Payment> _tenders = const <Payment>[];
  Customer? _customer;
  RefundableBill? _refundable;

  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  bool _isDisposed = false;

  bool _isRefunding = false;
  String? _refundError;
  Refund? _justRefunded;

  /// The request currently being attempted, held so a retry is a retry.
  ///
  /// Reused rather than rebuilt, because the id inside it is what makes the repository
  /// recognise a second attempt at the same intent and return the reversal it already wrote
  /// instead of writing another. Cleared once the outcome is known and acted on.
  RefundRequest? _attempt;

  // ------------------------------------------------------------------- state ---

  String get orderId => _orderId;

  /// The stored bill header, or `null` before it has been read or if it is gone.
  Order? get order => _order;

  /// The stored lines with their customisations, in bill order.
  List<BillLineSnapshot> get lines => _lines;

  /// Tenders recorded against the bill, oldest first.
  List<Payment> get payments => _tenders;

  /// The customer the bill was filed against, or `null` for a walk-in.
  Customer? get customer => _customer;

  bool get isLoading => _isLoading;

  bool get hasLoaded => _hasLoaded;

  String? get errorMessage => _errorMessage;

  bool get hasError => _errorMessage != null;

  /// True when the read finished and the bill is not on this terminal.
  bool get isMissing => _hasLoaded && !hasError && _order == null;

  // ------------------------------------------------------------------ refund ---

  /// What the bill collected, what has gone back and what is left, or `null` before the
  /// read.
  RefundableBill? get refundable => _refundable;

  /// True while a refund is being written.
  bool get isRefunding => _isRefunding;

  /// Why the last refund attempt did not happen, or `null`.
  ///
  /// Separate from [errorMessage]: the bill is still shown behind this.
  String? get refundError => _refundError;

  bool get hasRefundError => _refundError != null;

  /// The reversal this screen just wrote, or `null` when it has not written one.
  ///
  /// Set only by a refund made here, so the view can confirm the action rather than merely
  /// showing that the bill is now refunded. [RefundableBill.existingRefund] is what says a
  /// bill arrived already refunded.
  Refund? get justRefunded => _justRefunded;

  /// True when a refund made on this screen has succeeded.
  bool get hasRefunded => _justRefunded != null;

  /// What has been handed back on this bill in total, including before this screen opened.
  Money get refundedAmount => _refundable?.refundedAmount ?? Money.zero;

  /// What could still be handed back.
  Money get refundableAmount => _refundable?.refundableAmount ?? Money.zero;

  /// What the bill collected, which is the ceiling on any refund.
  Money get paidAmount => _refundable?.paidAmount ?? Money.zero;

  /// True when a refund can be attempted right now.
  ///
  /// False while one is in flight, and false once one has succeeded here, so the action
  /// cannot be fired twice from the same screen. The repository refuses a second refund
  /// anyway; this only avoids asking it to.
  bool get canRefund =>
      !_isRefunding && !hasRefunded && (_refundable?.canRefund ?? false);

  /// Why a refund cannot be attempted, or `null` when one can.
  ///
  /// Drawn from the read model, so the wording a disabled action explains itself with is the
  /// same wording the repository would refuse with.
  String? get refundRefusal => hasRefunded ? null : _refundable?.refusalReason;

  // ----------------------------------------------------------------- derived ---

  String? get orderNumber => _order?.orderNumber;

  /// The number recorded for the customer, or `null` for a walk-in.
  String? get customerPhone => _customer?.phone;

  /// How the bill was paid, or `null` when no settled tender is stored.
  ///
  /// The first settled tender. Split payment is a later feature, and this is the line
  /// that changes when it arrives.
  PaymentMethod? get paymentMethod {
    for (final Payment payment in _tenders) {
      if (payment.status == PaymentStatus.completed) {
        return payment.paymentMethod;
      }
    }
    return null;
  }

  /// The transaction reference on the settled tender, if one was recorded.
  String? get paymentReference {
    for (final Payment payment in _tenders) {
      if (payment.status == PaymentStatus.completed) {
        final String? reference = payment.reference?.trim();
        return reference == null || reference.isEmpty ? null : reference;
      }
    }
    return null;
  }

  /// Number of units sold on the bill.
  int get itemCount => _lines.fold<int>(
    0,
    (int total, BillLineSnapshot line) => total + line.quantity,
  );

  /// Sum of the stored line totals.
  ///
  /// For checking, not for displaying as the bill's subtotal. The subtotal on the header
  /// is the figure that was charged, and this is here so a discrepancy between the two
  /// is visible rather than hidden.
  Money get linesTotal =>
      Money.sum(_lines.map((BillLineSnapshot line) => line.lineTotal));

  /// True when the stored lines add up to the stored subtotal, to the paisa.
  ///
  /// An exact comparison, not a tolerance: both sides are integers.
  bool get isConsistent => _order != null && linesTotal == _order!.subtotal;

  // ----------------------------------------------------------------- reading ---

  /// Reads the bill and everything shown beside it.
  ///
  /// Ignores a call made while a read is already running, so a double tap on retry
  /// cannot interleave two reads.
  Future<void> load() async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();

    final Result<Order?> found = await _orders.findOrder(_orderId);
    final AppFailure? headerFailure = found.failureOrNull;
    if (headerFailure != null) {
      _fail(headerFailure.message);
      return;
    }

    final Order? order = found.valueOrNull;
    if (order == null) {
      // Not a failure. The bill is simply not here, which is a different thing to tell
      // the cashier than a storage fault.
      _order = null;
      _lines = const <BillLineSnapshot>[];
      _tenders = const <Payment>[];
      _customer = null;
      _isLoading = false;
      _hasLoaded = true;
      _notify();
      return;
    }

    final Result<List<BillLineSnapshot>> lines = await _orders.loadBillLines(
      order.id,
    );
    final AppFailure? lineFailure = lines.failureOrNull;
    if (lineFailure != null) {
      _fail(lineFailure.message);
      return;
    }

    final Result<List<Payment>> tendered = await _payments.loadForOrder(
      order.id,
    );
    final AppFailure? paymentFailure = tendered.failureOrNull;
    if (paymentFailure != null) {
      _fail(paymentFailure.message);
      return;
    }

    final Result<RefundableBill?> refundable = await _refunds.loadRefundable(
      order.id,
    );
    final AppFailure? refundableFailure = refundable.failureOrNull;
    if (refundableFailure != null) {
      // Fatal, unlike the customer read below. This read is what the refund figures and the
      // refund action are drawn from, and a bill shown with a Refund button whose amounts
      // could not be read is a bill somebody could refund the wrong amount of.
      _fail(refundableFailure.message);
      return;
    }

    _order = order;
    _lines = lines.valueOrNull!;
    _tenders = tendered.valueOrNull!;
    _refundable = refundable.valueOrNull;
    // Deliberately last, and deliberately not fatal. A bill whose customer record could
    // not be read is still a complete bill; the phone number is one line on it.
    _customer = await _customerFor(order.customerId);

    _isLoading = false;
    _hasLoaded = true;
    _notify();
  }

  Future<void> retry() => load();

  // ----------------------------------------------------------------- writing ---

  /// Hands back the whole of what this bill collected.
  ///
  /// Returns true when the money went back. On failure returns false and leaves everything
  /// on screen exactly as it was, with [refundError] set: the sale is untouched, so there is
  /// nothing to redraw except the notice.
  ///
  /// Ignores a call made while one is already running, so a double tap cannot start two.
  /// Where a tap does get through twice — a retry after an outcome nobody saw — the held
  /// [RefundRequest] is reused, so the repository recognises it and returns the reversal it
  /// already wrote rather than writing a second.
  ///
  /// The figures are re-read afterwards, from storage, so what the screen shows next is what
  /// is on disk rather than what this method assumed it would be.
  Future<bool> refund({String? reason}) async {
    if (_isRefunding || hasRefunded) {
      return false;
    }

    final RefundableBill? bill = _refundable;
    if (bill == null) {
      // No figures were read, so there is nothing to refund against. Reported rather than
      // attempted, because the repository would only refuse it after a round trip.
      _refundError =
          'This bill has not finished loading, so it cannot be refunded yet.';
      _notify();
      return false;
    }

    _isRefunding = true;
    _refundError = null;
    _notify();

    // Built once and held. A retry of a refund whose outcome was lost has to be the same
    // request, or it becomes a second refund.
    final RefundRequest request = _attempt ??= RefundRequest.forBill(
      bill,
      reason: reason,
    );

    final Result<Refund> outcome = await _refunds.refund(request);

    final AppFailure? failure = outcome.failureOrNull;
    if (failure != null) {
      _isRefunding = false;
      _refundError = failure.message;
      // The request is kept, so tapping again retries this same intent rather than starting a
      // new one. Nothing was written, so the bill on screen is still correct.
      _notify();
      return false;
    }

    _justRefunded = outcome.valueOrNull;
    _attempt = null;
    _isRefunding = false;
    // Re-read rather than adjusted in memory: the refunded and refundable figures now come
    // from the committed rows, so the screen cannot disagree with the database.
    await _reloadRefundable();
    _notify();
    return true;
  }

  /// Clears the failure notice, leaving the bill and its figures alone.
  void dismissRefundError() {
    if (_refundError == null) {
      return;
    }
    _refundError = null;
    _notify();
  }

  // --------------------------------------------------------------- internals ---

  /// Re-reads the refund figures after a successful reversal.
  ///
  /// Deliberately not fatal. The refund has committed by the time this runs, so a read that
  /// fails here must not be reported as a refund that failed — that would be the one lie
  /// this screen could tell that costs money twice. The success stands and the figures are
  /// left as they were.
  Future<void> _reloadRefundable() async {
    final Result<RefundableBill?> refreshed = await _refunds.loadRefundable(
      _orderId,
    );
    final RefundableBill? bill = refreshed.valueOrNull;
    if (bill != null) {
      _refundable = bill;
    }
  }

  Future<Customer?> _customerFor(String? customerId) async {
    if (customerId == null) {
      return null;
    }
    final Result<Customer?> found = await _customers.findById(customerId);
    return found.fold<Customer?>(
      onOk: (Customer? customer) => customer,
      onErr: (AppFailure _) => null,
    );
  }

  /// Reports a read that failed, showing no part of the bill.
  ///
  /// Half a bill is worse than none: a subtotal beside lines that failed to load is a
  /// document nobody should be reading numbers off.
  void _fail(String message) {
    _errorMessage = message;
    _order = null;
    _lines = const <BillLineSnapshot>[];
    _tenders = const <Payment>[];
    _customer = null;
    // Cleared too, so no refund action can be offered against figures that failed to read.
    _refundable = null;
    _isLoading = false;
    _hasLoaded = true;
    _notify();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _notify() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }
}
