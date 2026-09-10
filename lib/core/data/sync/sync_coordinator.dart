import '../../utils/result.dart';
import 'sync_status_snapshot.dart';

/// Drives synchronisation between local storage and the cloud.
///
/// The coordinator owns the whole offline story, which is what keeps that concern
/// out of the billing module. Billing writes locally and enqueues; it never waits
/// on the network and never asks whether the device is online.
///
/// Intended behaviour of the eventual implementation:
///
/// 1. Push first. Replay outbox entries in queue order so local work reaches the
///    cloud before anything is pulled down on top of it.
/// 2. Then pull, requesting only records changed since the last successful sync.
/// 3. Resolve collisions by `updatedAt`, last write wins.
/// 4. Retry with backoff, triggered both on a timer and on the connectivity
///    monitor reporting that the link is back.
abstract interface class SyncCoordinator {
  /// Current synchronisation health, for display in the shell.
  Stream<SyncStatusSnapshot> get status;

  /// Most recent snapshot, for callers that cannot wait for the stream.
  SyncStatusSnapshot get currentStatus;

  /// Begins automatic synchronisation: timer plus connectivity-triggered runs.
  void start();

  /// Runs one push-then-pull cycle immediately. Used by a manual "sync now"
  /// action in settings.
  Future<Result<void>> syncNow();

  /// Stops automatic synchronisation and releases resources.
  Future<void> dispose();
}
