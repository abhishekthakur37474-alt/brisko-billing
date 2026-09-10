import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/brisko_app.dart';

/// Entry point for the Brisko Billing POS.
///
/// Start-up is: open and migrate the local database, build the repositories, then
/// run the UI. The database is deliberately ready before the first frame, because a
/// till that renders before it can read its own menu is worse than one that takes a
/// moment longer to appear.
Future<void> main() async {
  final AppDependencies dependencies = await bootstrap();
  runApp(BriskoApp(dependencies: dependencies));
}
