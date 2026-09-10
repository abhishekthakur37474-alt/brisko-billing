/// Known keys in the settings table.
///
/// Constants rather than free-form strings, so a typo is a compile error instead of
/// a silently missing GSTIN on a printed invoice.
///
/// Values are stored as text and interpreted by the settings repository. Nothing
/// here is populated yet; the settings screen is a later step.
class SettingKeys {
  const SettingKeys._();

  // Outlet identity, printed on every bill.
  static const String businessName = 'business.name';
  static const String businessAddress = 'business.address';
  static const String businessPhone = 'business.phone';

  /// GSTIN of the outlet. Legally required on a tax invoice.
  static const String gstin = 'tax.gstin';

  /// Combined GST rate in basis points, where 10000 is 100%. Integer for the same
  /// determinism reason money is.
  static const String gstRateBasisPoints = 'tax.gstRateBasisPoints';

  /// Whether menu prices already include tax, which changes how the tax line is
  /// derived rather than whether it is charged.
  static const String pricesIncludeTax = 'tax.pricesIncludeTax';

  static const String receiptHeader = 'receipt.header';
  static const String receiptFooter = 'receipt.footer';

  /// UPI virtual payment address used to generate the payment QR.
  static const String upiVpa = 'payment.upiVpa';

  /// Payee name shown to the customer in their UPI app.
  static const String upiPayeeName = 'payment.upiPayeeName';
}
