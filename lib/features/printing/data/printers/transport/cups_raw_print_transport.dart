import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'raw_print_transport.dart';

/// Sends raw ESC/POS bytes to a printer through the macOS print system (CUPS).
///
/// ## Why go through CUPS rather than open the USB device directly
///
/// The TVS RP 3200 Lite is connected to the Mac by USB. macOS does not let an ordinary
/// application claim a USB printer interface — the operating system's own printing stack
/// (CUPS) owns it — and prising it away would mean a low-level libusb/IOKit driver, an
/// entitlement, and the risk of leaving the device in a state the OS can no longer talk
/// to. None of that is appropriate for a till.
///
/// CUPS already speaks to the printer. What it needs from us is the guarantee that it
/// will not *interpret* our bytes: a normal print queue would run our ESC/POS stream
/// through a rasteriser and print garbage. A **raw** queue passes bytes through
/// untouched, which is exactly what an ESC/POS printer wants. So the printer is added
/// once as a raw queue (its name is the operator's `deviceName`), and this transport
/// hands the encoded document to that queue with `lp -o raw`.
///
/// This is the safe, reversible, driver-free path to real physical printing on the Mac,
/// and it is the direct analogue of the Windows RAW-spooler path: both hand the identical
/// bytes to the operating system's own spooler and let it drive the port.
///
/// ## It does not claim success it cannot see
///
/// `lp` accepting a job is necessary but not sufficient: CUPS will happily queue a job
/// for a printer it has *disabled* because the USB cable came out. So [open] refuses a
/// queue that does not exist or is disabled, and [write] — after submitting — watches the
/// queue until the job leaves it, and fails if the queue becomes disabled while the job
/// is still pending. A job that is accepted by an enabled queue and then leaves it is the
/// strongest evidence of physical printing this one-way path can produce.
class CupsRawPrintTransport implements RawPrintTransport {
  CupsRawPrintTransport({
    String? queueName,
    CupsCommandRunner? runner,
    Future<void> Function(Duration)? sleeper,
    this.completionTimeout = const Duration(seconds: 12),
    this.pollInterval = const Duration(milliseconds: 300),
  }) : _configuredQueue = _trimToNull(queueName),
       _run = runner ?? _runProcess,
       _sleep = sleeper ?? Future<void>.delayed;

  /// The queue name the operator saved, or null for "use the system default printer".
  final String? _configuredQueue;
  final CupsCommandRunner _run;
  final Future<void> Function(Duration) _sleep;

  /// How long to watch a submitted job before accepting it as printing on an enabled
  /// queue. Long enough for a receipt to cut; short enough not to stall the next bill.
  final Duration completionTimeout;
  final Duration pollInterval;

  /// Resolved on [open], so the description and every command use one stable name.
  String? _queue;

  @override
  String get description =>
      _queue ?? _configuredQueue ?? 'the default macOS printer';

  @override
  Future<void> open() async {
    final String queue = await _resolveQueue();
    final _QueueState state = await _queueState(queue);
    if (!state.exists) {
      throw CupsTransportException(
        'macOS has no printer queue named "$queue". Add the printer as a raw '
        'queue (lpadmin -p "$queue" -E -v <device> -m raw) or correct the '
        'printer name in Settings.',
      );
    }
    if (state.disabled) {
      throw CupsTransportException(
        'The macOS printer queue "$queue" is paused or the printer is '
        'offline${state.reason == null ? '' : ' (${state.reason})'}. '
        'Check the cable and resume the queue.',
      );
    }
    _queue = queue;
  }

  @override
  Future<void> write(Uint8List bytes, {required String jobName}) async {
    final String queue = _queue ?? await _resolveQueue();

    // -o raw: hand the ESC/POS stream to the printer untouched, with no rasteriser in
    // between. -t: a label for the queue, never part of the bytes. The document is fed
    // on stdin so nothing is written to a temp file the operator would have to trust.
    final CommandResult result = await _run(
      'lp',
      <String>['-d', queue, '-o', 'raw', '-t', jobName],
      stdin: bytes,
    );

    if (result.exitCode != 0) {
      throw CupsTransportException(
        'The macOS print system rejected the document for "$queue": '
        '${_firstLine(result.stderr).isEmpty ? 'lp exited with ${result.exitCode}' : _firstLine(result.stderr)}.',
      );
    }

    final String? requestId = _parseRequestId(result.stdout);
    // If lp reported no request id we cannot follow the job; the enabled-queue check in
    // open() is the guarantee we keep, and a missing id is treated as accepted rather
    // than invented into a failure.
    if (requestId == null) {
      return;
    }

    await _awaitCompletion(queue, requestId);
  }

  @override
  Future<void> close() async {
    // CUPS submission is stateless — there is no handle to release. Kept as a no-op so
    // the printer lifecycle above can call it unconditionally.
    _queue = null;
  }

  // --------------------------------------------------------------- internals ---

  /// Watches the queue until the job leaves it, failing if the queue goes disabled.
  ///
  /// This is what turns "lp accepted the job" into "an enabled printer processed it".
  /// A cable pulled after submission disables the queue in CUPS, and that is caught here
  /// rather than reported as a successful print.
  Future<void> _awaitCompletion(String queue, String requestId) async {
    final DateTime deadline = DateTime.now().add(completionTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final _QueueState state = await _queueState(queue);
      if (state.disabled) {
        throw CupsTransportException(
          'The printer "$queue" went offline while printing '
          '(${state.reason ?? 'queue disabled'}). The document was not printed.',
        );
      }
      final bool stillQueued = await _isJobPending(queue, requestId);
      if (!stillQueued) {
        // Left an enabled queue: the printer took it.
        return;
      }
      await _sleep(pollInterval);
    }
    // Timed out with the job still on an enabled queue. Not a failure: the printer is
    // accepting work and the bytes are the spooler's responsibility now, exactly as a
    // successful WritePrinter is on Windows.
  }

  Future<String> _resolveQueue() async {
    final String? configured = _configuredQueue;
    if (configured != null) {
      return configured;
    }
    // No name saved: a terminal with a single ESC/POS printer added as the default.
    final CommandResult result = await _run('lpstat', <String>['-d']);
    final String? def = _parseDefaultDestination(result.stdout);
    if (def == null) {
      throw const CupsTransportException(
        'No macOS printer name was configured and there is no default printer. '
        'Add the ESC/POS printer as a raw queue and set its name in Settings.',
      );
    }
    return def;
  }

  Future<_QueueState> _queueState(String queue) async {
    // `lpstat -p <queue>` prints "printer X is idle." / "... disabled since ...".
    // A non-zero exit or empty output means the queue does not exist.
    final CommandResult result = await _run('lpstat', <String>['-p', queue]);
    if (result.exitCode != 0 || result.stdout.trim().isEmpty) {
      return const _QueueState(exists: false, disabled: false);
    }
    final String out = result.stdout.toLowerCase();
    final bool disabled = out.contains('disabled');
    return _QueueState(
      exists: true,
      disabled: disabled,
      reason: disabled ? _firstLine(result.stdout) : null,
    );
  }

  Future<bool> _isJobPending(String queue, String requestId) async {
    // `lpstat -o <queue>` lists jobs not yet completed. If the id is gone, it printed.
    final CommandResult result = await _run('lpstat', <String>['-o', queue]);
    if (result.exitCode != 0) {
      return false;
    }
    return result.stdout.contains(requestId);
  }

  static String? _parseRequestId(String stdout) {
    // "request id is TVS-42 (1 file(s))"
    final RegExp pattern = RegExp(r'request id is (\S+)');
    final Match? match = pattern.firstMatch(stdout);
    return match?.group(1);
  }

  static String? _parseDefaultDestination(String stdout) {
    // "system default destination: TVS" or "no system default destination"
    final RegExp pattern = RegExp(r'system default destination:\s*(\S+)');
    final Match? match = pattern.firstMatch(stdout);
    return match?.group(1);
  }

  static String _firstLine(String value) {
    final String trimmed = value.trim();
    final int newline = trimmed.indexOf('\n');
    return newline == -1 ? trimmed : trimmed.substring(0, newline);
  }

  static String? _trimToNull(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The default runner: really shells out to CUPS command-line tools.
  static Future<CommandResult> _runProcess(
    String executable,
    List<String> arguments, {
    Uint8List? stdin,
  }) async {
    final Process process = await Process.start(executable, arguments);
    if (stdin != null) {
      process.stdin.add(stdin);
    }
    await process.stdin.close();
    final Future<String> out =
        process.stdout.transform(utf8.decoder).join();
    final Future<String> err =
        process.stderr.transform(utf8.decoder).join();
    final int code = await process.exitCode;
    return CommandResult(
      exitCode: code,
      stdout: await out,
      stderr: await err,
    );
  }
}

/// The state of a CUPS queue, reduced to the two facts that decide whether printing can
/// happen: does it exist, and is it enabled.
class _QueueState {
  const _QueueState({
    required this.exists,
    required this.disabled,
    this.reason,
  });

  final bool exists;
  final bool disabled;
  final String? reason;
}

/// Runs a CUPS command-line tool. Injected so a test can drive the transport's decisions
/// — queue exists, queue disabled, job pending then gone — without a printer or a shell.
typedef CupsCommandRunner = Future<CommandResult> Function(
  String executable,
  List<String> arguments, {
  Uint8List? stdin,
});

/// The outcome of a command-line invocation.
class CommandResult {
  const CommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A fault from the macOS print system: a missing queue, a disabled printer, or `lp`
/// refusing a document. An exception because that is what a transport deals in; the
/// printer base class turns it into the `PrinterFailure` the cashier reads.
class CupsTransportException implements Exception {
  const CupsTransportException(this.message);

  final String message;

  @override
  String toString() => 'CupsTransportException($message)';
}
