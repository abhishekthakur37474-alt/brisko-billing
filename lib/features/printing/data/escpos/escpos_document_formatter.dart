import 'dart:typed_data';

import '../../../../core/constants/app_constants.dart';
import '../../domain/models/business_identity.dart';
import '../../domain/models/print_document.dart';
import '../../domain/models/print_profile.dart';
import '../../domain/print_timestamp.dart';
import '../../domain/services/print_document_encoder.dart';
import 'escpos_builder.dart';
import 'escpos_text_layout.dart';

/// Turns a print document into ESC/POS bytes.
///
/// ## Where the layout decisions live
///
/// All of them, here. This is the only class that knows what a Brisko receipt looks
/// like, and it knows nothing about how the bytes reach the printer. That split is what
/// lets a USB adapter and a network adapter share one layout, and it is why this class
/// can be tested exhaustively with no printer: it is a pure function from a document to
/// a byte list.
///
/// Everything device-specific — the column budget, the font, the indent, the rule
/// characters, the feed, the cut and the QR settings — comes from [profile]. There is no
/// paper width and no column count written into this file.
///
/// ## Two documents, one printer
///
/// The outlet has a single printer for both the customer's bill and the kitchen's slip,
/// so both are laid out for the same paper and both end in a cut. The difference is
/// deliberate and total: [_receipt] prints money, [_kot] has no access to any.
class EscPosDocumentFormatter implements PrintDocumentEncoder {
  const EscPosDocumentFormatter({this.profile = PrintProfile.escPos80mm});

  /// Printed above the totals so the digits in the amount columns are unambiguous.
  ///
  /// The rupee glyph itself is not sent to the printer; see `EscPosEncoding` for why.
  /// Stating the currency once is both correct and one fewer thing to go wrong on
  /// hardware nobody has held yet.
  static const String currencyCode = 'INR';

  /// Marks a second copy, so it cannot be mistaken for a second sale at cash-up.
  static const String reprintMarker = '*** REPRINT ***';

  /// Heading on the kitchen slip, in double height so it is read across a kitchen.
  static const String kotHeading = 'KITCHEN ORDER TICKET';

  @override
  final PrintProfile profile;

  /// Formats [document]. Exhaustive over the sealed document type, so adding a
  /// document is a compile error here rather than a blank page at the counter.
  @override
  Uint8List encode(PrintDocument document) {
    final EscPosBuilder builder = EscPosBuilder(profile: profile);
    builder.initialise();

    switch (document) {
      case CustomerReceipt():
        _receipt(builder, document);
      case KitchenKot():
        _kot(builder, document);
      case PrinterTestPage():
        _testPage(builder, document);
    }

    builder.cut();
    return builder.bytes();
  }

  // --------------------------------------------------------------- receipt ---

  void _receipt(EscPosBuilder builder, CustomerReceipt receipt) {
    _businessHeader(builder, receipt.business);

    if (receipt.isReprint) {
      builder.centred(reprintMarker, bold: true);
      builder.blankLine();
    }

    builder.separator();
    builder.row(
      'Bill ${receipt.orderNumber}',
      receipt.orderType.label,
      bold: true,
    );
    builder.line(PrintTimestamp.stamp(receipt.issuedAt));
    if (receipt.hasCustomerPhone) {
      builder.line('Customer: ${receipt.customerPhone}');
    }
    builder.separator();

    for (final CustomerReceiptLine line in receipt.lines) {
      builder.itemRow(
        name: line.displayName,
        quantity: line.quantity,
        unitPrice: line.unitPrice,
        lineTotal: line.lineTotal,
        options: line.options
            .map((CustomerReceiptLineOption option) => option.name)
            .toList(growable: false),
        notes: line.notes,
      );
    }

    builder.separator();

    // Discount and tax are printed even at zero. Nothing in this build produces
    // either, and a receipt that omitted the lines would leave the customer unable to
    // see that they were not charged tax.
    builder.amountRow('Subtotal', receipt.totals.subtotal);
    builder.amountRow('Discount', receipt.totals.discount);
    builder.amountRow('Tax', receipt.totals.tax);
    builder.separator(emphasis: true);
    builder.totalRow('TOTAL $currencyCode', receipt.totals.total);
    builder.separator(emphasis: true);

    builder.row(
      'Paid by ${receipt.paymentMethod.label}',
      'Items ${receipt.totalQuantity}',
    );

    if (receipt.hasNotes) {
      builder.blankLine();
      builder.line('Note: ${receipt.notes}');
    }

    _upiBlock(builder, receipt);

    if (receipt.business.hasReceiptFooter) {
      builder.blankLine();
      builder.centred(receipt.business.receiptFooter!);
    }
  }

  /// The outlet's own details, centred at the top.
  ///
  /// Only what has been configured is printed. There is no placeholder address and no
  /// placeholder GSTIN: an invented tax number on an invoice is worse than a missing
  /// one, so a blank setting produces a blank space.
  ///
  /// There is no logo either. A bitmap logo needs `PrinterCapabilities.supportsGraphics`,
  /// which is false until a real printer proves otherwise, and an invented placeholder
  /// image on a customer's bill would be worse than none.
  void _businessHeader(EscPosBuilder builder, BusinessIdentity business) {
    builder.centred(business.name, bold: true, doubleHeight: true);

    if (business.hasAddress) {
      builder.centred(business.address!);
    }
    if (business.hasPhone) {
      builder.centred('Phone ${business.phone}');
    }
    if (business.hasGstin) {
      builder.centred('GSTIN ${business.gstin}');
    }
    if (business.hasReceiptHeader) {
      builder.centred(business.receiptHeader!);
    }
  }

  /// The payment QR, when a UPI address has been configured.
  ///
  /// Prints nothing at all when it has not. A QR is a promise that scanning it pays
  /// this outlet, and there is no honest placeholder for that. Nothing is printed either
  /// when the printer has no QR engine, because a heading with no symbol under it would
  /// read as a fault rather than as an absence.
  void _upiBlock(EscPosBuilder builder, CustomerReceipt receipt) {
    if (!receipt.hasUpiPayment || !profile.canPrintQrCode) {
      return;
    }

    builder.blankLine();
    builder.centred('Scan to pay by UPI');
    builder.qrCode(receipt.upiPayment!.toUri());
    builder.centred(receipt.upiPayment!.vpa);
  }

  // ------------------------------------------------------------------- kot ---

  /// The kitchen slip.
  ///
  /// No amount reaches this method, because [KitchenKot] has nowhere to carry one.
  /// The quantity is printed as `Qty 2` rather than `2 x 320.00`, which is the same
  /// item row with its money omitted.
  void _kot(EscPosBuilder builder, KitchenKot kot) {
    builder.centred(kotHeading, bold: true, doubleHeight: true);
    if (kot.isReprint) {
      builder.centred(reprintMarker, bold: true);
    }

    builder.separator();
    builder.row('KOT ${kot.kotNumber}', kot.orderType.label, bold: true);
    builder.row('Bill ${kot.orderNumber}', PrintTimestamp.time(kot.issuedAt));
    builder.line(PrintTimestamp.date(kot.issuedAt));
    builder.separator();

    for (final KitchenKotLine line in kot.lines) {
      builder.itemRow(
        name: line.displayName,
        quantity: line.quantity,
        options: line.options,
        notes: line.notes,
      );
    }

    builder.separator();

    if (kot.hasNotes) {
      builder.line('Note: ${kot.notes}', bold: true);
    }
    builder.line('Items ${kot.totalQuantity}');
  }

  // ------------------------------------------------------------- test page ---

  /// A page that proves the printer and the paper width.
  ///
  /// The ruler is the point. A line of exactly [PrintProfile.columns] characters that
  /// arrives wrapped means the printer is not the device the profile describes, which is
  /// otherwise discovered on a customer's bill. Counting the ruler is how
  /// `PrintProfile.columnOverride` gets its value.
  void _testPage(EscPosBuilder builder, PrinterTestPage page) {
    builder.centred(AppConstants.appName, bold: true, doubleHeight: true);
    builder.centred('Printer test page');
    builder.separator();

    builder.row('Paper', profile.paper.label);
    builder.row('Font', profile.font.label);
    builder.row('Columns', '${profile.columns}');
    builder.row('Printed', PrintTimestamp.stamp(page.printedAt));
    builder.separator();

    builder.line('Width ruler: this line must not wrap');
    builder.line(_ruler(profile.columns));
    builder.blankLine();

    builder.line('Left aligned');
    builder.centred('Centred');
    builder.line('Bold', bold: true);
    builder.line('Double height', doubleHeight: true);
    builder.row('Two columns', 'right edge');
    builder.separator();

    if (page.hasQrData) {
      builder.centred('QR check');
      builder.qrCode(page.qrData!);
    }
  }

  /// `1234567890...` repeated to exactly [width] characters.
  static String _ruler(int width) {
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < width; index++) {
      buffer.write((index + 1) % 10);
    }
    return EscPosTextLayout.truncate(buffer.toString(), width);
  }
}
