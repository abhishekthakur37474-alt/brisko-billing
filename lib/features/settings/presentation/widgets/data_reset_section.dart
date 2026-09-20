import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/data_reset_controller.dart';
import 'settings_notices.dart';

/// The Data section on the Settings screen.
///
/// Offers one action: physically remove bills, the menu, orders, kitchen slips,
/// held carts, customers, inventory, expenses and the upload queue. Login, outlet
/// details, printer binding and the manager password stay, because those live in
/// the settings table this action never touches.
///
/// Renders nothing when no [DataResetController] has been provided, so a screen
/// shown outside the full application shell is never forced to wire one up.
class DataResetSection extends StatelessWidget {
  const DataResetSection({super.key});

  @override
  Widget build(BuildContext context) {
    final DataResetController? controller = context
        .watch<DataResetController?>();
    if (controller == null) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);

    return SettingsSection(
      title: 'Data',
      description:
          'Remove bills, the menu, orders and reports from this till. '
          'The sign-in, outlet details and printer stay.',
      children: <Widget>[
        if (controller.hasError) ...<Widget>[
          Text(
            controller.errorMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (controller.isCleared) ...<Widget>[
          Text(
            'Till data cleared. Login and settings are unchanged.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Clear till data'),
          subtitle: const Text(
            'Deletes bills, the menu, orders, kitchen slips, held bills, '
            'customers, inventory, expenses and reports. Turn the switch on, '
            'then confirm. Sign-in and settings are not deleted.',
          ),
          value: controller.isClearing,
          onChanged: controller.canClear
              ? (bool enabled) {
                  if (enabled) {
                    unawaited(_confirmAndClear(context, controller));
                  }
                }
              : null,
        ),
      ],
    );
  }

  static Future<void> _confirmAndClear(
    BuildContext context,
    DataResetController controller,
  ) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Clear till data?'),
              content: const Text(
                'Bills, the menu, orders, kitchen slips, held bills, '
                'customers, inventory, expenses and reports will be deleted '
                'from this device. The sign-in, outlet details and printer '
                'stay. This cannot be undone.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Clear data'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirmed) {
      await controller.clear();
    }
  }
}
