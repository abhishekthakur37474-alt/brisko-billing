import '../../../../core/money/money.dart';
import 'cart.dart';

/// The money on the face of a bill: what the lines came to, what was taken off,
/// what was added, and what is payable.
///
/// ## Why discount and tax are zero
///
/// The `orders` table has carried `discountAmountPaise` and `taxAmountPaise` since
/// the first migration, and a settled order records both. Neither has a source yet:
/// there is no discount entry at the counter, and no GST rate is configured anywhere
/// in the application. Writing a figure into either one would be inventing a charge.
///
/// So they are carried explicitly as [Money.zero] rather than left out. The bill is
/// honest about what it did not charge, the persisted order matches what was shown,
/// and when a discount or a tax rate does arrive, [total] is the one place that has
/// to learn about it.
class BillTotals {
  const BillTotals({
    required this.subtotal,
    this.discount = Money.zero,
    this.tax = Money.zero,
  });

  /// Totals for a cart, before any discount or tax exists to apply.
  factory BillTotals.fromCart(Cart cart) => BillTotals(subtotal: cart.subtotal);

  /// Sum of the line totals, as the cart calculated them.
  final Money subtotal;

  final Money discount;

  final Money tax;

  /// Amount payable. Exact integer paise, in the order an invoice states it.
  Money get total => subtotal - discount + tax;

  /// True when there is something to collect. A bill of zero is not settleable.
  bool get isPayable => total.isPositive;

  /// True when nothing was taken off and nothing added, so the total is the
  /// subtotal. Lets the summary omit two zero rows instead of implying a charge.
  bool get hasAdjustments => !discount.isZero || !tax.isZero;

  @override
  bool operator ==(Object other) {
    return other is BillTotals &&
        other.subtotal == subtotal &&
        other.discount == discount &&
        other.tax == tax;
  }

  @override
  int get hashCode => Object.hash(subtotal, discount, tax);

  @override
  String toString() => 'BillTotals(total ${total.toDecimalString()})';
}
