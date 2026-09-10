import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Maintenance of the items and categories the outlet sells.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Menu',
      icon: Icons.local_pizza_outlined,
      scope: <String>[
        'Categories and items',
        'Pricing, including size and variant pricing',
        'Per-item tax rate',
        'Marking an item temporarily unavailable',
        'Linking items to inventory ingredients for stock deduction',
      ],
    );
  }
}
