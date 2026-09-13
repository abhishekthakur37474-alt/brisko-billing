/// The ESC/POS command bytes this build emits.
///
/// ## Why the bytes are written out here
///
/// ESC/POS is a byte protocol, not a library. Every command is a short escape
/// sequence, and there are perhaps a dozen worth using on a receipt printer. Writing
/// them down once, with the sequence spelled out and named, means the protocol is
/// visible and reviewable in this repository rather than hidden behind a package that
/// would also drag in a transport, a codec and a model assumption.
///
/// No manufacturer or model appears anywhere. These are the commands from the Epson
/// ESC/POS specification that every compatible 80mm printer implements; that is what
/// "ESC/POS compatible" on the box means.
///
/// ## Integers only
///
/// Every value here is an `int` in the range 0..255 and every command is a `List<int>`
/// of exactly those bytes. Nothing in the printing path is a `double`: not a
/// coordinate, not a module size, and above all not an amount.
class EscPosCommands {
  const EscPosCommands._();

  // ------------------------------------------------------------- primitives ---

  /// Escape. Introduces most commands.
  static const int esc = 0x1B;

  /// Group separator. Introduces the cutter, the QR code and the bit-image
  /// commands.
  static const int gs = 0x1D;

  /// Line feed. Prints the buffered line and advances one line.
  static const int lf = 0x0A;

  /// Horizontal tab. Not used: the layout is built from spaces, because tab stops
  /// vary between printers and would move a column on a different unit.
  static const int tab = 0x09;

  // ------------------------------------------------------------ housekeeping ---

  /// `ESC @` — reset. Clears any mode left behind by whatever printed last.
  ///
  /// Sent at the start of every document. Without it a bold or double-height mode
  /// left set by a previous job, or by the printer's own power-on state, would leak
  /// into this one.
  static const List<int> initialise = <int>[esc, 0x40];

  /// `ESC t n` — select the character code page.
  ///
  /// Page 0 is PC437, the default on effectively every ESC/POS printer, and the one
  /// the encoder targets.
  static List<int> selectCodePage(int page) => <int>[esc, 0x74, page];

  /// PC437, the US/European page assumed by [selectCodePage].
  static const int codePagePc437 = 0;

  /// `ESC M n` — select the character font.
  ///
  /// Font 0 is Font A, 12 dots wide, which is what 48 columns on 80mm paper means.
  /// Font 1 is Font B at 9 dots. Sent explicitly at the start of every document
  /// because the printer's power-on font is a configuration setting on the device: a
  /// printer left in Font B would fit 64 columns and make every laid-out line come out
  /// narrow, with the amounts no longer at the paper edge.
  static List<int> selectFont(int font) => <int>[esc, 0x4D, _byte(font)];

  // -------------------------------------------------------------- alignment ---

  /// `ESC a 0` — align left. The default for item lines.
  static const List<int> alignLeft = <int>[esc, 0x61, 0x00];

  /// `ESC a 1` — align centre. Used for the header and the QR code.
  static const List<int> alignCentre = <int>[esc, 0x61, 0x01];

  /// `ESC a 2` — align right.
  ///
  /// Present for completeness, but the layout prefers padding a line to the full
  /// column width and printing it left-aligned: that way one line can hold a label on
  /// the left and an amount on the right, which printer-side alignment cannot do.
  static const List<int> alignRight = <int>[esc, 0x61, 0x02];

  // ---------------------------------------------------------------- emphasis ---

  /// `ESC E 1` — bold on.
  static const List<int> boldOn = <int>[esc, 0x45, 0x01];

  /// `ESC E 0` — bold off.
  static const List<int> boldOff = <int>[esc, 0x45, 0x00];

  /// `ESC - 1` — underline on, one dot.
  static const List<int> underlineOn = <int>[esc, 0x2D, 0x01];

  /// `ESC - 0` — underline off.
  static const List<int> underlineOff = <int>[esc, 0x2D, 0x00];

  /// `ESC ! n` — character size and emphasis in one byte.
  ///
  /// Bit 4 doubles the height and bit 5 doubles the width. Double height is used for
  /// the total and for the KOT heading, which are the two things read from arm's
  /// length. Double *width* halves the columns available, so it is never combined
  /// with a two-column row.
  static const List<int> sizeNormal = <int>[esc, 0x21, 0x00];

  static const List<int> sizeDoubleHeight = <int>[esc, 0x21, 0x10];

  static const List<int> sizeDoubleWidth = <int>[esc, 0x21, 0x20];

  static const List<int> sizeDoubleBoth = <int>[esc, 0x21, 0x30];

  // -------------------------------------------------------------------- feed ---

  /// `ESC d n` — feed [lines] lines without printing.
  ///
  /// Used before a cut, because the cutter sits above the print head: without the
  /// feed the last few lines of the document would be cut off, which on a bill means
  /// the total. How many lines that takes is a property of the printer rather than of
  /// the protocol, so it lives on `PrintProfile` and not here.
  static List<int> feed(int lines) => <int>[esc, 0x64, _byte(lines)];

  // --------------------------------------------------------------------- cut ---

  /// `GS V 0` — full cut. Separates the document completely.
  static const List<int> cutFull = <int>[gs, 0x56, 0x00];

  /// `GS V 1` — partial cut, leaving a tab so the paper does not fall on the floor.
  static const List<int> cutPartial = <int>[gs, 0x56, 0x01];

  // ------------------------------------------------------------------ qr code ---
  //
  // The QR commands are the `GS ( k` family. Each carries a little-endian length
  // (pL, pH) covering the bytes that follow it, which is why they are built rather
  // than declared: the store command's length depends on the data.

  static const int _qrFunctionType = 0x31;

  /// `GS ( k 4 0 49 65 n 0` — select QR model.
  ///
  /// Model 2 is the modern symbol every scanner and every phone camera reads.
  static const List<int> qrSelectModel2 = <int>[
    gs,
    0x28,
    0x6B,
    0x04,
    0x00,
    _qrFunctionType,
    0x41,
    0x32,
    0x00,
  ];

  /// `GS ( k 3 0 49 67 n` — module size in dots, 1 to 16.
  ///
  /// The size of one square of the symbol. Six dots gives a symbol of roughly 25mm
  /// for a UPI URI on 80mm paper: comfortably scannable, and still leaving the
  /// receipt narrow enough not to waste a third of the roll.
  static List<int> qrModuleSize(int dots) => <int>[
    gs,
    0x28,
    0x6B,
    0x03,
    0x00,
    _qrFunctionType,
    0x43,
    _byte(dots),
  ];

  /// `GS ( k 3 0 49 69 n` — error correction level, 48 to 51 for L, M, Q, H.
  ///
  /// M is the usual choice for a printed payment code: it survives a thermal roll
  /// that has been in a pocket, without inflating the symbol the way H does.
  static List<int> qrErrorCorrection(int level) => <int>[
    gs,
    0x28,
    0x6B,
    0x03,
    0x00,
    _qrFunctionType,
    0x45,
    _byte(level),
  ];

  static const int qrErrorCorrectionLow = 48;
  static const int qrErrorCorrectionMedium = 49;
  static const int qrErrorCorrectionQuartile = 50;
  static const int qrErrorCorrectionHigh = 51;

  /// `GS ( k pL pH 49 80 48 <data>` — store the symbol data.
  ///
  /// The length covers the three bytes `49 80 48` plus the data, which is why it is
  /// `data.length + 3`. Getting this wrong is the classic ESC/POS QR bug: the printer
  /// reads the wrong number of bytes and then interprets the remainder of the
  /// document as commands, producing pages of garbage.
  static List<int> qrStoreData(List<int> data) {
    final int length = data.length + 3;
    return <int>[
      gs,
      0x28,
      0x6B,
      length & 0xFF,
      (length >> 8) & 0xFF,
      _qrFunctionType,
      0x50,
      0x30,
      ...data,
    ];
  }

  /// `GS ( k 3 0 49 81 48` — print the stored symbol.
  static const List<int> qrPrint = <int>[
    gs,
    0x28,
    0x6B,
    0x03,
    0x00,
    _qrFunctionType,
    0x51,
    0x30,
  ];

  /// The largest payload the store command can carry, from the 16-bit length.
  static const int qrMaxDataLength = 0xFFFF - 3;

  /// Clamps to a single byte, so a bad argument produces a valid command rather than
  /// a stream the printer would misparse.
  static int _byte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
}
