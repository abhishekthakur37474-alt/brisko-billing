import '../../../orders/domain/models/order_type.dart';
import 'setting_keys.dart';

/// The outlet's own configuration: who it is, what its bills say, and how the till
/// behaves.
///
/// ## Why a typed value rather than a map
///
/// The settings table is key/value text, which is the right shape for storage — adding
/// a setting needs no migration — and the wrong shape for everything above it. A map
/// invites `stored['business.name']` at a dozen call sites, each with its own idea of
/// what a blank string means. This is the one place that decision is made: a key that
/// is absent, or holds nothing but whitespace, is `null`, and `null` means *not
/// configured*.
///
/// ## Nothing here is invented
///
/// Every business field is nullable and starts out null. There is no sample outlet
/// name, no placeholder address, no example GSTIN and no default UPI address, because
/// those are legal and financial identifiers belonging to the owner. A receipt omits
/// what has not been configured; it never prints a plausible-looking stand-in.
///
/// [defaultOrderType] is the one exception, and it is not business data: an order type
/// is one of four values this build already defines, and settlement has always had to
/// open on one of them.
///
/// ## No money
///
/// There is no amount, no tax rate and no discount on this class. Settings does not
/// calculate money: every figure on a bill is carried from the committed order, and
/// nothing the operator types here can change one.
class PosSettings {
  const PosSettings({
    this.businessName,
    this.businessAddress,
    this.businessPhone,
    this.gstin,
    this.receiptHeader,
    this.receiptFooter,
    this.upiVpa,
    this.upiPayeeName,
    this.defaultOrderType = fallbackOrderType,
  });

  /// What is stored in the settings table, read into one value.
  ///
  /// A blank stored value reads the same as a missing row. That matters because clearing
  /// a field on the screen removes the row, and an older build may have written a blank
  /// one; both mean unconfigured.
  factory PosSettings.fromStored(Map<String, String?> stored) {
    return PosSettings(
      businessName: _text(stored[SettingKeys.businessName]),
      businessAddress: _text(stored[SettingKeys.businessAddress]),
      businessPhone: _text(stored[SettingKeys.businessPhone]),
      gstin: _text(stored[SettingKeys.gstin]),
      receiptHeader: _text(stored[SettingKeys.receiptHeader]),
      receiptFooter: _text(stored[SettingKeys.receiptFooter]),
      upiVpa: _text(stored[SettingKeys.upiVpa]),
      upiPayeeName: _text(stored[SettingKeys.upiPayeeName]),
      defaultOrderType:
          _orderType(stored[SettingKeys.defaultOrderType]) ?? fallbackOrderType,
    );
  }

  /// A terminal that has configured nothing.
  ///
  /// What a freshly installed till holds, and what the Settings screen shows on the day
  /// it is opened for the first time.
  static const PosSettings unconfigured = PosSettings();

  /// The order type settlement opens on when none has been chosen.
  ///
  /// Takeaway, which is the value `CheckoutController` has always started on and the
  /// fallback `Order.fromRow` uses for an unreadable row. Named here so the Settings
  /// screen and the checkout flow cannot disagree about it.
  static const OrderType fallbackOrderType = OrderType.takeaway;

  /// The outlet's trading name, or `null` to print the build's own name.
  ///
  /// Optional because `BusinessIdentity` already falls back to `Brisko Pizza`: the
  /// outlet name was given as part of the requirement rather than left to
  /// configuration, and a bill with no name on it is not identifiable as a bill.
  final String? businessName;

  /// Street address, printed under the name. Omitted from the bill when null.
  final String? businessAddress;

  /// The outlet's own contact number.
  ///
  /// Stored as typed, apart from trimming. Deliberately **not** put through
  /// `CustomerPhone`: that rule is ten digits starting 6-9, because a customer's number
  /// is a lookup key and has to reduce to one form. An outlet's number is a line on a
  /// receipt and may legitimately be a landline with an STD code, so normalising it
  /// would refuse a real number, and silently rewriting it would print a number nobody
  /// can call.
  final String? businessPhone;

  /// GST identification number, validated by `Gstin` before it is stored.
  final String? gstin;

  /// Extra line printed above the bill details, for example a branch name.
  final String? receiptHeader;

  /// Closing line, for example a thank-you or a return policy.
  final String? receiptFooter;

  /// UPI address the payment QR pays. No QR is printed when this is null.
  final String? upiVpa;

  /// Payee name shown in the customer's UPI application.
  final String? upiPayeeName;

  /// Order type the checkout flow opens on.
  final OrderType defaultOrderType;

  /// These settings as rows for the settings table.
  ///
  /// A `null` value removes the key rather than storing an empty string, so "not
  /// configured" is one state in the table instead of two.
  Map<String, String?> toStored() => <String, String?>{
    SettingKeys.businessName: businessName,
    SettingKeys.businessAddress: businessAddress,
    SettingKeys.businessPhone: businessPhone,
    SettingKeys.gstin: gstin,
    SettingKeys.receiptHeader: receiptHeader,
    SettingKeys.receiptFooter: receiptFooter,
    SettingKeys.upiVpa: upiVpa,
    SettingKeys.upiPayeeName: upiPayeeName,
    SettingKeys.defaultOrderType: defaultOrderType.name,
  };

  bool get hasBusinessName => businessName != null;

  bool get hasAddress => businessAddress != null;

  bool get hasPhone => businessPhone != null;

  bool get hasGstin => gstin != null;

  bool get hasReceiptHeader => receiptHeader != null;

  bool get hasReceiptFooter => receiptFooter != null;

  bool get hasUpiVpa => upiVpa != null;

  /// True when the outlet has entered what a tax invoice needs.
  ///
  /// Not enforced anywhere: refusing to print a bill because a setting is blank would
  /// stop the outlet trading. Surfaced so the Settings screen can say what is missing.
  bool get isCompleteForTaxInvoice => hasAddress && hasGstin;

  PosSettings copyWith({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? gstin,
    String? receiptHeader,
    String? receiptFooter,
    String? upiVpa,
    String? upiPayeeName,
    OrderType? defaultOrderType,
  }) {
    return PosSettings(
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessPhone: businessPhone ?? this.businessPhone,
      gstin: gstin ?? this.gstin,
      receiptHeader: receiptHeader ?? this.receiptHeader,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      upiVpa: upiVpa ?? this.upiVpa,
      upiPayeeName: upiPayeeName ?? this.upiPayeeName,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PosSettings &&
      other.businessName == businessName &&
      other.businessAddress == businessAddress &&
      other.businessPhone == businessPhone &&
      other.gstin == gstin &&
      other.receiptHeader == receiptHeader &&
      other.receiptFooter == receiptFooter &&
      other.upiVpa == upiVpa &&
      other.upiPayeeName == upiPayeeName &&
      other.defaultOrderType == defaultOrderType;

  @override
  int get hashCode => Object.hash(
    businessName,
    businessAddress,
    businessPhone,
    gstin,
    receiptHeader,
    receiptFooter,
    upiVpa,
    upiPayeeName,
    defaultOrderType,
  );

  @override
  String toString() =>
      'PosSettings(name: ${businessName ?? 'unset'}, '
      'gstin: ${hasGstin ? 'set' : 'unset'}, '
      'defaultOrderType: ${defaultOrderType.name})';

  /// [stored] with its surrounding whitespace removed, or `null` when it holds nothing.
  ///
  /// Trimming is the only transformation applied to any text on this class. A receipt
  /// footer keeps its wording, its punctuation and its capitalisation exactly as the
  /// owner typed it.
  static String? _text(String? stored) {
    if (stored == null) {
      return null;
    }
    final String trimmed = stored.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The order type named by [stored], or `null` when it names none.
  ///
  /// Stored by enum name, so reordering `OrderType` cannot change a saved default, and
  /// an unrecognised name falls back rather than throwing.
  static OrderType? _orderType(String? stored) {
    if (stored == null) {
      return null;
    }
    for (final OrderType type in OrderType.values) {
      if (type.name == stored) {
        return type;
      }
    }
    return null;
  }
}
