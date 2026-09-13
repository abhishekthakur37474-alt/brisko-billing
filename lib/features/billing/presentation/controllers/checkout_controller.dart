import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/money/money.dart';
import '../../../../core/utils/result.dart';
import '../../../customers/domain/models/customer.dart';
import '../../../customers/domain/models/customer_phone.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../inventory/domain/models/order_inventory_deduction.dart';
import '../../../inventory/domain/repositories/inventory_deduction_repository.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_type.dart';
import '../../../payments/domain/models/payment_method.dart';
import '../../../printing/domain/models/sale_print_run.dart';
import '../../../printing/domain/services/print_service.dart';
import '../../domain/models/bill_settlement.dart';
import '../../domain/models/bill_totals.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/cash_tender.dart';
import '../../domain/repositories/checkout_repository.dart';

/// Where the cashier is in the settlement flow.
enum CheckoutStep {
  /// Check the lines, the order type and the customer.
  review,

  /// Choose how it is being paid and, for cash, count the tender.
  payment,

  /// Last look before the money is taken.
  confirm,

  /// Settled. The order number exists and the cart is gone.
  success;

  String get label => switch (this) {
    CheckoutStep.review => 'Review bill',
    CheckoutStep.payment => 'Payment',
    CheckoutStep.confirm => 'Confirm payment',
    CheckoutStep.success => 'Bill settled',
  };
}

/// Drives settlement: review, tender, confirm, persist.
///
/// ## The cart is a snapshot
///
/// [cart] is the immutable cart handed over when checkout opened. It is not the live
/// billing cart, so nothing the cashier does here can edit the bill mid-settlement,
/// and backing out of the flow leaves the original untouched. The live cart is only
/// cleared through [onSettled], and only after the write has committed.
///
/// ## Money
///
/// Every amount is a [Money] in integer paise, including the cash keyed in, which is
/// accumulated digit by digit through [CashTender]. Nothing in this file reads an
/// amount out of a text field or converts one to a floating point value.
///
/// ## Submitting once
///
/// [submit] is guarded twice over. It refuses to run while a write is in flight or once
/// the bill is settled, and the [BillSettlement] it builds is cached, so a retry after a
/// failure carries the same order, line and payment ids. Even if the guard were
/// defeated, the second write would land on the same rows rather than create a second
/// bill.
class CheckoutController extends ChangeNotifier {
  CheckoutController({
    required Cart cart,
    required this._checkoutRepository,
    required this._customerRepository,
    required this._inventoryDeductionRepository,
    required this._printService,
    required this._onSettled,
    OrderType initialOrderType = OrderType.takeaway,
  }) : _cart = cart,
       _orderType = initialOrderType,
       _totals = BillTotals.fromCart(cart),
       _cashTender = CashTender(payable: BillTotals.fromCart(cart).total);

  /// Digits in the stored form of a phone number.
  ///
  /// Kept here as well as on [CustomerPhone] because the screen reads it, and the rule
  /// itself lives in one place.
  static const int phoneDigits = CustomerPhone.digits;

  final Cart _cart;
  final CheckoutRepository _checkoutRepository;
  final CustomerRepository _customerRepository;
  final InventoryDeductionRepository _inventoryDeductionRepository;
  final PrintService _printService;
  final VoidCallback _onSettled;
  final BillTotals _totals;

  CheckoutStep _step = CheckoutStep.review;

  /// Which type the flow opened on, until the cashier changes it.
  ///
  /// Takeaway unless the outlet has configured a different default in Settings. A default
  /// only decides which of the four is already selected; every one of them stays
  /// available on the review step, because the type is a fact about the order rather
  /// than a preference.
  OrderType _orderType;
  String _customerPhone = '';
  String _notes = '';
  PaymentMethod? _paymentMethod;
  CashTender _cashTender;
  String _reference = '';

  bool _isSubmitting = false;
  String? _errorMessage;
  Order? _settledOrder;

  bool _isDisposed = false;

  bool _isPrinting = false;
  SalePrintRun? _printRun;

  OrderInventoryDeduction? _deduction;
  String? _inventoryMessage;

  /// Fixed once built, so a retry cannot write a second bill.
  BillSettlement? _settlement;

  /// The customer already on file for the number entered, if there is one.
  ///
  /// A read, never a write. It exists so the cashier can see they are serving somebody
  /// the outlet already knows before taking the money, which is the moment that is
  /// useful. The customer record for a new number is created by settlement, not here.
  Customer? _knownCustomer;

  // ------------------------------------------------------------------- state ---

  CheckoutStep get step => _step;

  /// The bill being settled. Immutable for the lifetime of this controller.
  Cart get cart => _cart;

  BillTotals get totals => _totals;

  /// Amount to collect.
  Money get amountPayable => _totals.total;

  OrderType get orderType => _orderType;

  /// Digits the cashier has entered, or empty for a walk-in.
  ///
  /// What was typed, not what will be stored. See [normalisedCustomerPhone].
  String get customerPhone => _customerPhone;

  /// The number as it will be stored, or `null` when what was entered is not usable.
  ///
  /// `null` covers both a half-typed number and one that cannot be made sense of. The
  /// difference is [hasCustomerPhone].
  String? get normalisedCustomerPhone =>
      CustomerPhone.tryNormalise(_customerPhone);

  /// The customer already on file for the entered number, or `null`.
  ///
  /// Populated by a lookup as the number is completed. `null` also means "not looked up
  /// yet" or "the lookup failed", so this drives a hint on screen and nothing else.
  Customer? get knownCustomer => _knownCustomer;

  /// True when the number entered belongs to a customer the outlet has already served.
  bool get isReturningCustomer => _knownCustomer != null;

  String get notes => _notes;

  PaymentMethod? get paymentMethod => _paymentMethod;

  /// Cash counted out. Only meaningful when [paymentMethod] is cash.
  CashTender get cashTender => _cashTender;

  /// Transaction reference for a non-cash payment. Optional.
  String get reference => _reference;

  bool get isSubmitting => _isSubmitting;

  String? get errorMessage => _errorMessage;

  bool get hasError => _errorMessage != null;

  // ---------------------------------------------------------------- printing ---
  //
  // Printing state is kept apart from settlement state on purpose. `errorMessage` is
  // about the sale and blocks it; nothing below blocks anything, because by the time
  // any of it is set the money is already collected and recorded.

  /// How the printing of this sale went, or `null` before it has been attempted.
  SalePrintRun? get printRun => _printRun;

  bool get isPrinting => _isPrinting;

  /// True when the bill is settled but a document did not reach the printer.
  bool get hasPrintFailure => _printRun?.hasFailure ?? false;

  /// True when every document printed.
  bool get isPrinted => _printRun?.isComplete ?? false;

  /// The whole message for the cashier, leading with the fact that the money is safe.
  String? get printMessage => _printRun?.operatorMessage;

  // --------------------------------------------------------------- inventory ---
  //
  // Kept apart from settlement state for the same reason printing is, and for a
  // stronger version of the same reason. Nothing below can block the sale, because
  // everything below happens after the money is committed. A shelf that is short is a
  // stock figure for the owner to correct, not a reason to charge the customer again.

  /// How the stock deduction for this bill went, or `null` before it has been
  /// attempted.
  OrderInventoryDeduction? get deduction => _deduction;

  /// A note for the cashier about stock, or `null` when there is nothing to say.
  ///
  /// Set only when something needs reporting: the deduction failed, or the bill
  /// contained an item with no recipe. A successful deduction is silent, because the
  /// cashier has no decision to make about it.
  String? get inventoryMessage => _inventoryMessage;

  bool get hasInventoryNotice => _inventoryMessage != null;

  /// The settled order once the write has committed, otherwise `null`.
  Order? get settledOrder => _settledOrder;

  bool get isSettled => _settledOrder != null;

  /// Number printed on the bill, available only after settlement.
  String? get orderNumber => _settledOrder?.orderNumber;

  // ----------------------------------------------------------------- derived ---

  /// True when there is a bill worth settling at all.
  bool get hasBill => _cart.isNotEmpty && _totals.isPayable;

  /// True when the order type means the customer has to be contactable.
  bool get requiresCustomerPhone => _orderType.isOffPremises;

  bool get hasCustomerPhone => _customerPhone.isNotEmpty;

  /// True when what has been entered reduces to a number that can be stored.
  bool get isCustomerPhoneComplete => normalisedCustomerPhone != null;

  /// True when the phone entry is acceptable: usable, or absent when optional.
  bool get isCustomerAcceptable {
    if (requiresCustomerPhone) {
      return isCustomerPhoneComplete;
    }
    return !hasCustomerPhone || isCustomerPhoneComplete;
  }

  /// What is wrong with the number entered, or `null` when there is nothing to say.
  ///
  /// Empty is not a problem for a walk-in, so it reports nothing. Anything else that
  /// cannot be stored says what is wanted instead, because the alternative — a silently
  /// shortened number — files the bill under a stranger.
  String? get customerPhoneProblem {
    if (!hasCustomerPhone) {
      return requiresCustomerPhone
          ? 'This order leaves the outlet, so a number is needed'
          : null;
    }
    return isCustomerPhoneComplete ? null : CustomerPhone.requirement;
  }

  /// True when the review step is complete enough to take payment.
  bool get canProceedToPayment => hasBill && isCustomerAcceptable;

  /// True when the cash counted covers the bill, or the method is not cash.
  bool get isTenderSufficient {
    if (_paymentMethod != PaymentMethod.cash) {
      return true;
    }
    return _cashTender.isSufficient;
  }

  /// Change owed back. Zero for a non-cash payment or a short tender.
  Money get changeDue =>
      _paymentMethod == PaymentMethod.cash ? _cashTender.change : Money.zero;

  /// True when the payment step is complete.
  bool get canProceedToConfirm =>
      canProceedToPayment && _paymentMethod != null && isTenderSufficient;

  /// True when the money may be taken and the bill written.
  bool get canSubmit => canProceedToConfirm && !_isSubmitting && !isSettled;

  /// The step [goBack] would move to, or `null` when there is nowhere to go.
  ///
  /// `null` at [CheckoutStep.review] means the flow is at its start and the screen
  /// should leave. `null` at [CheckoutStep.success] means the bill is settled and
  /// there is nothing to go back to.
  CheckoutStep? get previousStep => switch (_step) {
    CheckoutStep.review => null,
    CheckoutStep.payment => CheckoutStep.review,
    CheckoutStep.confirm => CheckoutStep.payment,
    CheckoutStep.success => null,
  };

  // ----------------------------------------------------------------- intents ---

  void selectOrderType(OrderType type) {
    if (_orderType == type || isSettled) {
      return;
    }
    _orderType = type;
    _invalidateSettlement();
    notifyListeners();
  }

  /// Records the customer's phone number, keeping only the digits.
  ///
  /// Punctuation and spaces are stripped, because a number pasted as `+91 98765 43210`
  /// is the number the cashier meant and refusing it at the till would be pedantry. What
  /// is *not* done is shortening: the digits are kept as entered, up to the length of a
  /// full international number, and whether they amount to a usable phone number is
  /// answered by [isCustomerPhoneComplete].
  ///
  /// The distinction matters. Keeping the first ten digits of `+91 90000 00001` would
  /// produce `9190000000`, a real number belonging to somebody else, and file the bill
  /// against them. Refusing it tells the cashier to look again.
  void setCustomerPhone(String value) {
    final String digits = CustomerPhone.digitsOf(value);

    if (_customerPhone == digits || isSettled) {
      return;
    }
    _customerPhone = digits;
    // A different number is a different customer, so any record found for the old one
    // is stale.
    _knownCustomer = null;
    _invalidateSettlement();
    notifyListeners();

    unawaited(_lookUpCustomer(digits));
  }

  void setNotes(String value) {
    if (_notes == value || isSettled) {
      return;
    }
    _notes = value;
    _invalidateSettlement();
    notifyListeners();
  }

  void selectPaymentMethod(PaymentMethod method) {
    if (_paymentMethod == method || isSettled) {
      return;
    }
    _paymentMethod = method;
    // A method change resets the counted cash: leaving ₹500 on screen after
    // switching to UPI and back would show a tender nobody put down.
    _cashTender = CashTender(payable: amountPayable);
    _reference = '';
    _invalidateSettlement();
    notifyListeners();
  }

  void setReference(String value) {
    if (_reference == value || isSettled) {
      return;
    }
    _reference = value;
    _invalidateSettlement();
    notifyListeners();
  }

  /// One keypad press. Ignored unless cash is the chosen method.
  void appendTenderDigit(int digit) =>
      _updateTender((CashTender tender) => tender.appendDigit(digit));

  void removeTenderDigit() =>
      _updateTender((CashTender tender) => tender.removeLastDigit());

  void clearTender() => _updateTender((CashTender tender) => tender.cleared());

  /// Sets the tender to the exact amount payable.
  void tenderExact() => _updateTender((CashTender tender) => tender.exact());

  /// Adds a note the customer handed over.
  void addTenderNote(Money note) =>
      _updateTender((CashTender tender) => tender.addNote(note));

  void goToPayment() {
    if (_step != CheckoutStep.review || !canProceedToPayment) {
      return;
    }
    _step = CheckoutStep.payment;
    _errorMessage = null;
    notifyListeners();
  }

  void goToConfirm() {
    if (_step != CheckoutStep.payment || !canProceedToConfirm) {
      return;
    }
    _step = CheckoutStep.confirm;
    _errorMessage = null;
    notifyListeners();
  }

  /// Steps back one stage. Returns false when there is nowhere to go, which is the
  /// screen's signal to leave the flow.
  ///
  /// Going back never touches the bill: the cart is a snapshot and the tender is kept,
  /// so a cashier who wants to check a line before taking the money loses nothing.
  bool goBack() {
    final CheckoutStep? previous = previousStep;
    if (previous == null) {
      return false;
    }
    _step = previous;
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Dismisses a failure message without leaving the confirm step.
  void dismissError() {
    if (_errorMessage == null) {
      return;
    }
    _errorMessage = null;
    notifyListeners();
  }

  /// Takes the money: writes the bill, its payment, its kitchen slip and, when a number
  /// was taken, its customer — all in one transaction.
  ///
  /// Does nothing when the bill is not ready, when a write is already in flight, or
  /// when the bill is already settled. On success the live cart is cleared through
  /// `onSettled` and the flow moves to [CheckoutStep.success]. On failure nothing at all
  /// was persisted — not even the customer record — the cart is untouched, and the same
  /// settlement can be submitted again.
  Future<void> submit() async {
    if (!canSubmit) {
      return;
    }

    _isSubmitting = true;
    _errorMessage = null;
    _notify();

    final BillSettlement settlement = _settlement ??= BillSettlement.fromCart(
      cart: _cart,
      orderType: _orderType,
      paymentMethod: _paymentMethod!,
      // The number, not a customer id. The repository resolves it inside the settlement
      // transaction, so a failed sale cannot leave a customer behind and a retry cannot
      // create a second one.
      customerPhone: normalisedCustomerPhone,
      reference: _referenceOrNull,
      notes: _notesOrNull,
    );

    final Result<Order> result = await _checkoutRepository.settle(settlement);

    result.fold<void>(
      onOk: (Order order) {
        _settledOrder = order;
        _step = CheckoutStep.success;
        // Only now, and only once the write has committed.
        _onSettled();
      },
      onErr: (AppFailure failure) => _errorMessage = failure.message,
    );

    _isSubmitting = false;
    _notify();

    // Strictly after the commit, and deliberately after the success step is already
    // on screen. The sale is finished at this point whatever the printer or the shelf
    // does.
    if (_settledOrder != null) {
      await _print();
      await _deductStock();
    }
  }

  /// Dismisses the stock note, leaving the settled bill on screen.
  ///
  /// Clears a message, not a record. The deduction row stays exactly as it is, so a
  /// bill whose stock was not taken off remains on the owner's list in Inventory even
  /// after the cashier has moved on. That is the point of writing it down.
  void dismissInventoryNotice() {
    if (_inventoryMessage == null) {
      return;
    }
    _inventoryMessage = null;
    notifyListeners();
  }

  /// Sends the receipt and the kitchen slip again, for the documents that failed.
  ///
  /// Prints; it does not settle. The bill is already on disk, so this cannot produce a
  /// second order, payment or kitchen slip, and the cashier can press it as many times
  /// as the printer needs.
  Future<void> retryPrinting() async {
    final SalePrintRun? run = _printRun;
    if (run == null || !run.hasFailure || _isPrinting) {
      return;
    }

    _isPrinting = true;
    _notify();

    _printRun = await _printService.retry(run);
    _isPrinting = false;
    _notify();
  }

  /// Dismisses the printing notice, leaving the settled bill on screen.
  ///
  /// For the case where the cashier has decided the customer does not need paper. The
  /// sale is unaffected: this clears a message, not a record.
  void dismissPrintFailure() {
    if (_printRun == null || !_printRun!.hasFailure) {
      return;
    }
    _printRun = null;
    notifyListeners();
  }

  // --------------------------------------------------------------- internals ---

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  /// Looks up whether the number entered is already on file.
  ///
  /// Read-only, and deliberately so: nothing is created until the bill settles. A
  /// failure is swallowed, because this only drives a hint. The counter can take the
  /// money whether or not the customer table could be read.
  ///
  /// The result is discarded if the number changed while the read was in flight, so a
  /// cashier typing quickly cannot be shown the customer for a number they have already
  /// moved past.
  Future<void> _lookUpCustomer(String enteredDigits) async {
    final String? normalised = CustomerPhone.tryNormalise(enteredDigits);
    if (normalised == null) {
      return;
    }

    final Result<Customer?> found = await _customerRepository.findByPhone(
      normalised,
    );

    if (_customerPhone != enteredDigits || isSettled) {
      return;
    }

    final Customer? customer = found.fold<Customer?>(
      onOk: (Customer? value) => value,
      onErr: (AppFailure _) => null,
    );
    if (customer == null) {
      return;
    }

    _knownCustomer = customer;
    _notify();
  }

  /// Notifies unless the controller has already been disposed.
  ///
  /// The two things that happen after the money commits — printing and the stock
  /// deduction — can still be in flight when the cashier leaves the success screen and
  /// starts the next bill. Both are deliberately allowed to finish, because the bill is
  /// already written and their outcomes are recorded where they belong: the print run in
  /// the printer's own reporting, and the deduction durably in the database. Only the
  /// notification is dropped, since there is no longer a screen to tell.
  void _notify() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  /// Prints the paperwork for the settled bill.
  ///
  /// Never touches [_errorMessage], [_settledOrder] or [_step]. A printer that is
  /// missing, jammed or unplugged must not make a settled bill look unsettled, so the
  /// outcome lands only in [_printRun].
  Future<void> _print() async {
    final Order? order = _settledOrder;
    if (order == null) {
      return;
    }

    _isPrinting = true;
    _notify();

    _printRun = await _printService.printSale(order.id);
    _isPrinting = false;
    _notify();
  }

  /// Takes the bill's ingredients off the shelf.
  ///
  /// Never touches [_errorMessage], [_settledOrder] or [_step], for the same reason
  /// [_print] does not, and with less room for argument: this runs after the money is
  /// in the till and the bill is on disk. A recipe that cannot be fulfilled, a stock
  /// item somebody deleted, or a storage fault must not make a settled bill look
  /// unsettled. The outcome lands in [_deduction] and, only when there is something to
  /// say, in [_inventoryMessage].
  ///
  /// The repository has already recorded a failure durably by the time this returns,
  /// so nothing is lost when the cashier starts the next bill.
  Future<void> _deductStock() async {
    final Order? order = _settledOrder;
    if (order == null) {
      return;
    }

    final Result<OrderInventoryDeduction> result =
        await _inventoryDeductionRepository.deductForOrder(order.id);

    result.fold<void>(
      onOk: (OrderInventoryDeduction deduction) {
        _deduction = deduction;
        // Silent on a clean deduction. Reports only an item with no recipe, which is
        // the owner's cue to configure one.
        _inventoryMessage = deduction.operatorMessage;
      },
      onErr: (AppFailure failure) {
        // Deliberately not `errorMessage`: that field is about the sale, and the sale
        // succeeded.
        _inventoryMessage =
            'Bill ${order.orderNumber} is settled. Stock was not deducted: '
            '${failure.message}';
      },
    );

    _notify();
  }

  String? get _referenceOrNull {
    final String trimmed = _reference.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? get _notesOrNull {
    final String trimmed = _notes.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _updateTender(CashTender Function(CashTender tender) change) {
    if (_paymentMethod != PaymentMethod.cash || isSettled) {
      return;
    }
    final CashTender updated = change(_cashTender);
    if (updated == _cashTender) {
      return;
    }
    _cashTender = updated;
    notifyListeners();
  }

  /// Drops a built settlement after an input changed.
  ///
  /// The settlement is a frozen copy of the bill and its tender. Once the order type,
  /// the customer or the payment method moves, that copy would write the wrong thing,
  /// so it is discarded and rebuilt on the next submit.
  void _invalidateSettlement() {
    if (isSettled) {
      return;
    }
    _settlement = null;
  }
}
