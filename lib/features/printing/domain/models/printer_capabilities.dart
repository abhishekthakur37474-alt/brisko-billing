import 'paper_width.dart';

/// What a printer can physically do.
///
/// Read by the formatter, not by billing code. It exists so a document can be laid
/// out for the paper and the features actually present rather than for an assumed
/// model: a printer without a cutter should be fed extra paper for a manual tear
/// instead of being sent a cut command it will ignore.
///
/// [escPos80mm] describes the hardware the outlet has selected.
class PrinterCapabilities {
  const PrinterCapabilities({
    required this.paperWidth,
    required this.hasAutoCutter,
    required this.supportsQrCode,
    this.supportsGraphics = false,
    this.isColour = false,
  });

  /// The selected hardware: 80mm, ESC/POS, auto cutter, native QR, monochrome.
  static const PrinterCapabilities escPos80mm = PrinterCapabilities(
    paperWidth: PaperWidth.mm80,
    hasAutoCutter: true,
    supportsQrCode: true,
  );

  final PaperWidth paperWidth;

  /// True when the printer can cut the roll itself.
  final bool hasAutoCutter;

  /// True when the printer renders a QR code from data, rather than needing one
  /// rasterised into a bitmap by the application.
  final bool supportsQrCode;

  /// True when arbitrary bitmaps can be printed, which a logo would need.
  final bool supportsGraphics;

  /// Always false for thermal paper. Declared so nothing has to assume it, and so
  /// a document never tries to convey meaning with colour.
  final bool isColour;

  /// Characters per line available to a layout.
  int get characterColumns => paperWidth.characterColumns;

  @override
  String toString() =>
      'PrinterCapabilities(${paperWidth.label}, '
      'cutter: $hasAutoCutter, qr: $supportsQrCode)';
}
