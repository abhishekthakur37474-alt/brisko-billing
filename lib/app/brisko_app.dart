import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/customers/domain/repositories/customer_repository.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/kot/domain/repositories/kot_repository.dart';
import '../features/menu/domain/repositories/menu_repository.dart';
import '../features/orders/domain/repositories/order_repository.dart';
import '../features/payments/domain/repositories/payment_repository.dart';
import '../features/settings/domain/repositories/settings_repository.dart';
import 'bootstrap.dart';
import 'routes/app_routes.dart';
import 'shell/shell_controller.dart';

/// Root widget of the application.
///
/// Owns three things and nothing else: the application-wide state objects, the
/// theme, and the route table. Business logic and data access are deliberately
/// absent here.
///
/// The provider list below is the single place dependencies are wired. Repositories
/// are provided under their abstract types, so a screen can depend on
/// `MenuRepository` and remains unaware that SQLite is behind it.
class BriskoApp extends StatelessWidget {
  const BriskoApp({required this.dependencies, super.key});

  /// Built by [bootstrap] before `runApp`, so the database is already open and
  /// migrated by the time any widget builds.
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    // Type argument omitted deliberately: the element type
    // (`SingleChildWidget`) lives in provider's transitive `nested` package and
    // is not re-exported, so it cannot be named without an implicit
    // dependency. Inference supplies it correctly.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShellController>(
          create: (BuildContext context) => ShellController(),
        ),
        // Plain `Provider` rather than a factory: these are stateless
        // collaborators created once at start-up, and rebuilding one mid-shift
        // would drop any active `watch` subscription.
        Provider<MenuRepository>.value(value: dependencies.menuRepository),
        Provider<OrderRepository>.value(value: dependencies.orderRepository),
        Provider<CustomerRepository>.value(
          value: dependencies.customerRepository,
        ),
        Provider<PaymentRepository>.value(
          value: dependencies.paymentRepository,
        ),
        Provider<InventoryRepository>.value(
          value: dependencies.inventoryRepository,
        ),
        Provider<KotRepository>.value(value: dependencies.kotRepository),
        Provider<SettingsRepository>.value(
          value: dependencies.settingsRepository,
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
