import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'routes/app_routes.dart';
import 'shell/shell_controller.dart';

/// Root widget of the application.
///
/// Owns three things and nothing else: the application-wide state objects, the
/// theme, and the route table. Business logic and data access are deliberately
/// absent here.
///
/// As modules are built, their controllers and repositories are registered in the
/// provider list below. That list is the single place where dependencies are
/// wired, which keeps construction out of the widget tree.
class BriskoApp extends StatelessWidget {
  const BriskoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      // Type argument omitted deliberately: the element type
      // (`SingleChildWidget`) lives in provider's transitive `nested` package and
      // is not re-exported, so it cannot be named without an implicit
      // dependency. Inference supplies it correctly.
      providers: [
        ChangeNotifierProvider<ShellController>(
          create: (BuildContext context) => ShellController(),
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // The billing terminal is used in a bright, fixed environment, so the
        // light theme is pinned until a display preference exists in settings.
        themeMode: ThemeMode.light,
        initialRoute: AppRoutes.home,
        routes: AppRoutes.routes(),
        onUnknownRoute: AppRoutes.onUnknownRoute,
      ),
    );
  }
}
