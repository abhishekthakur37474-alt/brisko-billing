import 'package:flutter/material.dart';

import '../../../../shared/widgets/module_placeholder.dart';

/// Outlet and terminal configuration.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePlaceholder(
      title: 'Settings',
      icon: Icons.settings_outlined,
      scope: <String>[
        'Outlet details: name, address, GSTIN, contact number',
        'Tax rates and whether prices are entered inclusive of tax',
        'UPI payee details used to generate the payment QR',
        'Receipt header and footer text',
        'Thermal printer selection and paper width',
        'Manual sync trigger and pending upload count',
      ],
    );
  }
}
