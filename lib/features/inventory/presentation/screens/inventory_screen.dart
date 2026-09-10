import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Basic stock tracking for the outlet.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Inventory',
      icon: Icons.inventory_2_outlined,
      scope: <String>[
        'Stock items with units and current quantity',
        'Recording stock received',
        'Manual stock adjustment with a reason',
        'Automatic deduction when a linked menu item is sold',
        'Low stock threshold and alerts',
      ],
    );
  }
}
