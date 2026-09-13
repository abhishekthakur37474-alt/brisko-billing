import '../../../../core/money/money.dart';
import '../../../../core/utils/entity_id.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_item.dart';
import '../../../orders/domain/models/order_item_option.dart';
import '../../../orders/domain/models/order_type.dart';
import '../../../payments/domain/models/payment.dart';
import '../../../payments/domain/models/payment_method.dart';
import 'bill_totals.dart';
import 'cart.dart';
import 'cart_line.dart';
import 'cart_line_option.dart';
import 'checkout_transition.dart';

/// A bill the cashier has confirmed, as the exact rows that will be written.
///
/// ## Why this type exists
///
/// It is the one place a cart becomes an order. [BillSettlement.fromCart] copies each
/// [CartLine]'s snapshots straight across into an [OrderItem], and each
/// [CartLineOption] into an [OrderItemOption]. Nothing is looked up in the menu, and
/// no price is recalculated: the amounts written are the amounts the customer was
/// quoted. That is what makes a settled bill reproducible years later, after the menu
/// has been repriced and the product possibly discontinued.
///
/// ## Why it carries no order number
///
/// The number is allocated inside the settlement transaction, by the repository. A
/// number chosen out here would be a guess about what the table looks like by the time
/// the transaction commits.
///
/// ## Why the ids are generated once
///
/// Every id below is fixed when the settlement is built, not when it is written. If a
/// write fails and the cashier retries, the retry carries the same order id, the same
/// line ids and the same payment id, so it can only ever update the same rows. It
/// cannot produce a second bill for one sale.
///
/// ## Why it carries a phone number rather than a customer id
///
/// The customer is resolved by the repository, inside the settlement transaction, for
/// the same reason the order number is: a customer id chosen out here would have to be
/// committed first, and a bill that then failed to write would leave behind a customer
/// who never ordered anything. Carrying the number instead means the customer record and
/// the bill land together or not at all. See `SqliteCustomerWriter`.
class BillSettlement {
  BillSettlement({
    required this.orderId,
    required this.orderType,
    required this.totals,
    required this.payment,
    required this.createdAt,
    required List<OrderItem> items,
    required List<OrderItemOption> itemOptions,
    this.customerPhone,
    this.notes,
    String? kotId,
  }) : items = List<OrderItem>.unmodifiable(items),
       itemOptions = List<OrderItemOption>.unmodifiable(itemOptions),
       kotId = kotId ?? EntityId.generate(prefix: 'kot');

  /// Turns a cart into the rows for a settled bill.
  ///
  /// The line's own `unitPrice` and `lineTotal` are carried across unchanged, and each
  /// option row takes the line's quantity, because two pizzas each with extra cheese
  /// is two portions of extra cheese. That keeps the rows reconcilable: a line's
  /// `totalAmount` equals its base price times quantity plus the total of its option
  /// rows.
  ///
  /// [at] is the settlement instant, injected so a test can pin it. It becomes
  /// `createdAt` on every row, which is what orders them on a reprint.
  factory BillSettlement.fromCart({
    required Cart cart,
    required OrderType orderType,
    required PaymentMethod paymentMethod,
    String? customerPhone,
    String? reference,
    String? notes,
    DateTime? at,
  }) {
    final DateTime createdAt = (at ?? DateTime.now()).toUtc();
    final String orderId = EntityId.generate(prefix: 'ord');
    final BillTotals totals = BillTotals.fromCart(cart);

    final List<OrderItem> items = <OrderItem>[];
    final List<OrderItemOption> itemOptions = <OrderItemOption>[];

    for (final CartLine line in cart.lines) {
      final String orderItemId = EntityId.generate(prefix: 'oit');

      items.add(
        OrderItem(
          id: orderItemId,
          orderId: orderId,
          // Reporting back-references. Never the source of the printed values, and
          // deliberately kept even when the product is later deleted.
          menuItemId: line.menuItemId,
          variantId: line.variantId,
          itemNameSnapshot: line.itemNameSnapshot,
          variantNameSnapshot: line.variantNameSnapshot,
          quantity: line.quantity,
          unitPrice: line.unitPrice,
          totalAmount: line.lineTotal,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

      for (final CartLineOption option in line.options) {
        itemOptions.add(
          OrderItemOption(
            id: EntityId.generate(prefix: 'oio'),
            orderItemId: orderItemId,
            optionId: option.optionId,
            optionNameSnapshot: option.nameSnapshot,
            price: option.priceSnapshot,
            quantity: line.quantity,
            createdAt: createdAt,
            updatedAt: createdAt,
          ),
        );
      }
    }

    return BillSettlement(
      orderId: orderId,
      orderType: orderType,
      totals: totals,
      items: items,
      itemOptions: itemOptions,
      payment: Payment(
        id: EntityId.generate(prefix: 'pay'),
        orderId: orderId,
        paymentMethod: paymentMethod,
        // Exactly the amount payable. Cash may be over-tendered at the counter, but
        // what is recorded as collected against the bill is the bill.
        amount: totals.total,
        reference: reference,
        status: CheckoutTransition.settledPaymentStatus,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      customerPhone: customerPhone,
      notes: notes,
      createdAt: createdAt,
    );
  }

  /// Identity of the order this settlement will write. Fixed across retries.
  final String orderId;

  final OrderType orderType;

  final BillTotals totals;

  /// The bill lines, with their price and name snapshots. Unmodifiable.
  final List<OrderItem> items;

  /// The customisations on those lines. Unmodifiable.
  final List<OrderItemOption> itemOptions;

  /// The tender. One row: split payment is a later feature, not a hidden one.
  final Payment payment;

  /// The number the cashier took, or `null` for a walk-in who gave none.
  ///
  /// Resolved to a customer record by the repository, inside the settlement
  /// transaction. Held as entered rather than pre-normalised so that an unusable number
  /// is refused by the one place that owns that rule.
  final String? customerPhone;

  /// True when this bill is to be filed against a customer.
  bool get hasCustomer =>
      customerPhone != null && customerPhone!.trim().isNotEmpty;

  final String? notes;

  final DateTime createdAt;

  /// Identity of the kitchen slip this settlement will raise. Fixed across retries,
  /// for the same reason [orderId] is: the same bill can only ever write the same
  /// slip row, so one sale cannot produce two slips.
  final String kotId;

  /// Amount payable.
  Money get amountPayable => totals.total;

  bool get hasLines => items.isNotEmpty;

  /// True when the tender recorded matches the bill exactly.
  ///
  /// The database cannot check this, so settlement refuses to write a bill whose
  /// payment row disagrees with its total. A bill that says ₹320 and a payment that
  /// says ₹300 would make every sales figure derived from either one wrong.
  bool get isBalanced => payment.amount == totals.total;

  /// Builds the order header once the number and the customer are known.
  ///
  /// Both arguments come from inside the settlement transaction: [orderNumber] from the
  /// sequence, [customerId] from resolving [customerPhone]. Neither can be decided out
  /// here without guessing at what the tables will look like when the transaction
  /// commits.
  Order toOrder(String orderNumber, {String? customerId}) {
    return Order(
      id: orderId,
      orderNumber: orderNumber,
      orderType: orderType,
      status: CheckoutTransition.settledOrderStatus,
      customerId: customerId,
      subtotal: totals.subtotal,
      discountAmount: totals.discount,
      taxAmount: totals.tax,
      totalAmount: totals.total,
      notes: notes,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  @override
  String toString() =>
      'BillSettlement($orderId, ${items.length} lines, '
      '${amountPayable.toDecimalString()})';
}
