import 'package:flutter/material.dart';

import '../shell/pos_shell.dart';

/// Named routes for screens that open on top of the shell.
///
/// Top-level sections are not routes. They are swapped inside the persistent
/// shell so the navigation frame never rebuilds. Routes are reserved for
/// full-screen flows pushed over the shell, such as bill settlement or a report
/// detail view. Those entries are added as the modules are built.
class AppRoutes {
  const AppRoutes._();

  /// Entry point of the application.
  static const String home = '/';

  static Map<String, WidgetBuilder> routes() {
    return <String, WidgetBuilder>{
      home: (BuildContext context) => const PosShell(),
    };
  }

  /// Fallback for an unregistered route name. Reaching this is a programming
  /// error, so it says so rather than silently showing a blank page.
  static Route<void> onUnknownRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Navigation error')),
        body: Center(
          child: Text('No route registered for "${settings.name}".'),
        ),
      ),
    );
  }
}
