import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Business reporting for the outlet.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Reports',
      icon: Icons.bar_chart_outlined,
      scope: <String>[
        'Daily and date-range sales summaries',
        'Sales by order type and by payment mode',
        'Item-wise and category-wise sales',
        'GST and tax summary',
        'Discounts, cancellations and refunds',
        'Stock consumption and low stock',
        'Customer repeat and top customer reports',
        'The agreed set of roughly ten to fifteen reports',
      ],
    );
  }
}
