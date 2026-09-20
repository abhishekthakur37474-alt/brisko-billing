import '../../../../core/utils/result.dart';

/// Clears operational till data while leaving the sign-in and configuration alone.
///
/// Bills, the menu, kitchen slips, held carts, customers, inventory, expenses and
/// the upload queue are removed. The settings table is not touched, so the
/// persisted session, outlet details, printer binding and manager password stay.
abstract interface class OperationalDataWiper {
  /// Physically removes operational rows in one transaction.
  ///
  /// Reports and the dashboard are derived from those rows, so they empty as a
  /// consequence. A failure rolls the transaction back; nothing is half-cleared.
  Future<Result<void>> clearOperationalData();
}
