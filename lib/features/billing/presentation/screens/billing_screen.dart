import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Order entry and bill settlement. The core screen of the application.
class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'New Bill',
      icon: Icons.point_of_sale_outlined,
      scope: <String>[
        'Menu selection and cart building',
        'Order type: dine-in, takeaway or delivery',
        'Customer phone number capture',
        'Line and bill level discounts',
        'GST calculation on the taxable amount',
        'Settlement by cash, UPI or card, including UPI QR display',
        'Writes to local storage first so billing continues without internet',
      ],
    );
  }
}
