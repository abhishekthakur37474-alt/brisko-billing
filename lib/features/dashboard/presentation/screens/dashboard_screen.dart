import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Landing screen for the billing terminal.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Dashboard',
      icon: Icons.space_dashboard_outlined,
      scope: <String>[
        'Sales totals for the current day and shift',
        'Split of dine-in, takeaway and delivery orders',
        'Collections by cash, UPI and card',
        'Open orders awaiting settlement',
        'Low stock warnings from the inventory module',
        'Synchronisation status when the terminal has been offline',
      ],
    );
  }
}
