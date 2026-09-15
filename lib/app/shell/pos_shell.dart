import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../features/billing/presentation/screens/billing_screen.dart';
import '../../features/cloud_sync/presentation/widgets/sync_status_indicator.dart';
import '../../features/customers/presentation/screens/customers_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/kot/presentation/screens/kitchen_screen.dart';
import '../../features/menu/presentation/screens/menu_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import 'pos_section.dart';
import 'shell_controller.dart';

/// Persistent frame around the POS: navigation plus the active section.
///
/// The shell is the only place that knows which widget belongs to which
/// [PosSection]. Feature modules expose a screen and nothing else, so adding or
/// replacing a module touches this one mapping.
class PosShell extends StatelessWidget {
  const PosShell({super.key});

  @override
  Widget build(BuildContext context) {
    final PosSection section = context.select<ShellController, PosSection>(
      (ShellController controller) => controller.section,
    );

    final bool isWide =
        MediaQuery.sizeOf(context).width >= AppConstants.wideLayoutBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: Text(section.label),
        // Unobtrusive, and never a control: the sync status reports here, while
        // the manual sync and detail live in Settings.
        actions: const <Widget>[
          Center(child: SyncStatusIndicator()),
          SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: <Widget>[
          if (isWide) ...<Widget>[
            _ShellNavigationRail(section: section),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: _sectionScreen(section)),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : _ShellNavigationBar(section: section),
    );
  }

  /// Maps a navigation section to the screen that renders it.
  static Widget _sectionScreen(PosSection section) {
    return switch (section) {
      PosSection.dashboard => const DashboardScreen(),
      PosSection.billing => const BillingScreen(),
      // The Orders section is the kitchen board. For this outlet, what the counter
      // needs from a settled order is what the kitchen still has to make; bill
      // history, reprinting and refunds are separate later work.
      PosSection.orders => const KitchenScreen(),
      PosSection.menu => const MenuScreen(),
      PosSection.inventory => const InventoryScreen(),
      PosSection.customers => const CustomersScreen(),
      PosSection.reports => const ReportsScreen(),
      PosSection.settings => const SettingsScreen(),
    };
  }
}

/// Side navigation for tablet and desktop layouts.
class _ShellNavigationRail extends StatelessWidget {
  const _ShellNavigationRail({required this.section});

  final PosSection section;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: section.index,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -1,
      onDestinationSelected: (int index) {
        context.read<ShellController>().select(PosSection.values[index]);
      },
      destinations: <NavigationRailDestination>[
        for (final PosSection item in PosSection.values)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

/// Bottom navigation for narrow layouts.
///
/// `NavigationBar` is not designed for eight destinations, so the narrow layout
/// shows the sections used during a shift and reaches the rest through the
/// "More" sheet.
class _ShellNavigationBar extends StatelessWidget {
  const _ShellNavigationBar({required this.section});

  static const List<PosSection> _primary = <PosSection>[
    PosSection.dashboard,
    PosSection.billing,
    PosSection.orders,
  ];

  final PosSection section;

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = _primary.indexOf(section);

    return NavigationBar(
      // When a secondary section is active, no primary destination is
      // highlighted, so "More" is shown as selected instead.
      selectedIndex: selectedIndex == -1 ? _primary.length : selectedIndex,
      onDestinationSelected: (int index) {
        if (index < _primary.length) {
          context.read<ShellController>().select(_primary[index]);
        } else {
          _showMoreSections(context);
        }
      },
      destinations: <Widget>[
        for (final PosSection item in _primary)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label,
          ),
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'More',
        ),
      ],
    );
  }

  Future<void> _showMoreSections(BuildContext context) async {
    final ShellController controller = context.read<ShellController>();

    final PosSection? chosen = await showModalBottomSheet<PosSection>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final PosSection item in PosSection.values)
                if (!_primary.contains(item))
                  ListTile(
                    leading: Icon(
                      item == section ? item.selectedIcon : item.icon,
                    ),
                    title: Text(item.label),
                    selected: item == section,
                    onTap: () => Navigator.of(sheetContext).pop(item),
                  ),
            ],
          ),
        );
      },
    );

    if (chosen != null) {
      controller.select(chosen);
    }
  }
}
