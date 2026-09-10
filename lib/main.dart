import 'package:flutter/material.dart';

import 'app/brisko_app.dart';

/// Entry point for the Brisko Billing POS.
///
/// Kept deliberately thin. Asynchronous start-up work belongs in a bootstrap step
/// added here later: opening local storage, initialising Firebase, loading outlet
/// settings and starting the sync coordinator. None of that exists yet, so there
/// is nothing to await.
void main() {
  runApp(const BriskoApp());
}
