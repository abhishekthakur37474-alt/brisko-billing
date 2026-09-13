import '../../../../core/error/app_failure.dart';
import '../../../../core/utils/result.dart';
import '../../domain/models/print_job.dart';
import '../../domain/models/print_profile.dart';
import '../../domain/models/printer_capabilities.dart';
import '../../domain/models/printer_connection.dart';
import '../../domain/printers/thermal_printer.dart';

/// The printer this terminal has, which is none.
///
/// ## Why this exists rather than a nullable printer
///
/// The 80mm printer has been chosen and not yet bought. The alternatives to this class
/// were both worse:
///
/// * A `ThermalPrinter?` threaded through the print service and the checkout
///   controller, with a null check at every use, and a print path that is never
///   exercised until the hardware arrives.
/// * A stub that pretends to print, which would make every test and every screen agree
///   that printing works right up until a real printer disagreed.
///
/// This reports the truth instead: [PrinterConnectionState.unavailable], and a
/// [PrinterFailure] from every send with a message that tells the cashier what is
/// actually wrong. The whole "settled but not printed" path — the message, the retry,
/// the guarantee that the sale stands — therefore runs in production from today, and
/// the only thing that changes when the printer is plugged in is which implementation
/// is constructed in the bootstrap.
///
/// It is not a fake and not test data. It states a fact about this terminal.
class UnconfiguredThermalPrinter implements ThermalPrinter {
  UnconfiguredThermalPrinter({
    this.capabilities = PrinterCapabilities.escPos80mm,
  }) : profile = PrintProfile.forCapabilities(capabilities);

  /// What the cashier is told. Names the action that would fix it.
  static const String message =
      'No thermal printer is set up on this terminal yet. Connect the 80mm '
      'ESC/POS printer and configure it in Settings to print.';

  /// The capabilities of the printer the outlet intends to use.
  ///
  /// Populated rather than blank so that documents are laid out for the paper that is
  /// coming, which means the receipt built today is the one that will print unchanged
  /// on the real device.
  @override
  final PrinterCapabilities capabilities;

  /// The 80mm layout, for the same reason.
  ///
  /// Documents are still built and encoded on a terminal with no printer: that is how
  /// the byte stream is verified before any hardware exists, and how the failure path is
  /// exercised in production rather than only in tests.
  @override
  final PrintProfile profile;

  @override
  PrinterConnectionState get connectionState =>
      PrinterConnectionState.unavailable;

  /// A single state that never changes, and a stream that stays open.
  @override
  Stream<PrinterConnectionState> get connectionStates =>
      Stream<PrinterConnectionState>.value(PrinterConnectionState.unavailable);

  /// No endpoint, because nothing has been configured.
  @override
  PrinterEndpoint? get endpoint => null;

  @override
  Future<Result<void>> connect() async => _failure();

  /// Succeeds: there is nothing open, so there is nothing to release.
  @override
  Future<Result<void>> disconnect() async => const Ok<void>(null);

  @override
  Future<Result<void>> send(PrintJob job) async => _failure();

  @override
  Future<void> dispose() async {}

  static Result<void> _failure() => const Err<void>(PrinterFailure(message));
}
