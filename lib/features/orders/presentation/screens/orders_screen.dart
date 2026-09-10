import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// History and management of orders already entered into the POS.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Orders',
      icon: Icons.receipt_long_outlined,
      scope: <String>[
        'List of orders with search and date filtering',
        'Order detail view',
        'Settling an order that was held open',
        'Cancellation and refund handling',
        'Reprinting a bill or a kitchen slip',
        'Per-order indication of whether the record has reached the cloud',
      ],
    );
  }
}
