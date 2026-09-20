import 'package:flutter/foundation.dart';

import '../../../../core/error/app_failure.dart';
import '../../../../core/utils/result.dart';
import '../../../billing/presentation/controllers/billing_controller.dart';
import '../../domain/services/operational_data_wiper.dart';

/// Where a data-clear attempt stands.
enum DataResetStatus {
  /// Nothing in flight.
  idle,

  /// The wipe is writing.
  clearing,

  /// The last wipe committed.
  cleared,

  /// The last wipe failed. [DataResetController.errorMessage] says why.
  error,
}

/// Owns the Settings "clear till data" action.
///
/// The widgets confirm; this class writes. A failed wipe leaves every table as it
/// was, because the repository transaction rolls back, and the live cart is only
/// emptied after the write commits.
class DataResetController extends ChangeNotifier {
  DataResetController({
    required OperationalDataWiper wiper,
    required BillingController billing,
  }) : _wiper = wiper,
       _billing = billing;

  final OperationalDataWiper _wiper;
  final BillingController _billing;

  DataResetStatus _status = DataResetStatus.idle;
  String? _errorMessage;
  bool _isDisposed = false;

  DataResetStatus get status => _status;

  bool get isClearing => _status == DataResetStatus.clearing;

  bool get isCleared => _status == DataResetStatus.cleared;

  bool get hasError => _errorMessage != null;

  String? get errorMessage => _errorMessage;

  /// True when the button should start a wipe.
  bool get canClear => !isClearing;

  /// Removes operational data. Returns true when the till is empty of it.
  Future<bool> clear() async {
    if (isClearing) {
      return false;
    }

    _status = DataResetStatus.clearing;
    _errorMessage = null;
    _notify();

    final Result<void> result = await _wiper.clearOperationalData();
    final AppFailure? failure = result.failureOrNull;
    if (failure != null) {
      _status = DataResetStatus.error;
      _errorMessage = failure.message;
      _notify();
      return false;
    }

    _billing.clearCart();
    await _billing.loadMenu();

    _status = DataResetStatus.cleared;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _notify() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }
}
