/// Known keys in the settings table.
///
/// Constants rather than free-form strings, so a typo is a compile error instead of
/// a silently missing GSTIN on a printed invoice.
///
/// Values are stored as text and interpreted by the settings repository. A key with
/// no row is unconfigured, which is not the same as blank: `PosSettings` and
/// `PrintSettings` decide what an absent value means, once each, rather than at every
/// reader.
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

  /// Order type the checkout flow opens on, as an `OrderType` name.
  ///
  /// A convenience for an outlet whose trade is mostly one kind: it changes which
  /// choice is already selected, never which choices exist, and the cashier can still
  /// pick any of them on the review step.
  static const String defaultOrderType = 'pos.defaultOrderType';

  // ------------------------------------------------------------------ printer ---
  //
  // The printer's *layout*, not its address. There is deliberately no key here for a
  // USB device, an IP address or a port: no transport exists on this terminal yet, and
  // a stored printer address would claim one does. Every key below changes how a
  // document is laid out, which is verifiable today without any hardware.

  /// `PrinterFont` name. Font A at 12 dots, or Font B at 9.
  static const String printerFont = 'printer.font';

  /// Columns to use instead of the font's own arithmetic, when a real printer
  /// disagrees with it. Absent means use the arithmetic.
  static const String printerColumnOverride = 'printer.columnOverride';

  /// `PrintCut` name: a full cut, a partial cut, or none for a printer with no blade.
  static const String printerCut = 'printer.cut';

  /// Lines fed before the cut, so the printed area clears the blade.
  static const String printerFeedLinesBeforeCut = 'printer.feedLinesBeforeCut';

  /// Whether the printer's QR engine is used. False suppresses the payment block
  /// rather than printing a heading with nothing under it.
  static const String printerQrEnabled = 'printer.qrEnabled';

  /// Size of one QR module in dots.
  static const String printerQrModuleSize = 'printer.qrModuleSize';

  /// `QrErrorCorrection` name: the redundancy built into the printed symbol.
  static const String printerQrErrorCorrection = 'printer.qrErrorCorrection';
}
