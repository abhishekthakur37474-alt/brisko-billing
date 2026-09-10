import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Customer records, keyed by phone number.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Customers',
      icon: Icons.people_outline,
      scope: <String>[
        'Lookup by phone number',
        'Name and delivery address',
        'Order history for a customer',
        'Spend and visit totals',
        'Sharing a bill over WhatsApp using the saved number',
      ],
    );
  }
}
