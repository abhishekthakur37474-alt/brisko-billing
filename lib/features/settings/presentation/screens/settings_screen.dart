import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../printing/domain/services/active_print_profile.dart';
import '../../domain/active_pos_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../controllers/settings_controller.dart';
import '../widgets/settings_form.dart';
import '../widgets/settings_notices.dart';

/// Outlet and terminal configuration.
///
/// ## What is here, and what is deliberately not
///
/// Four sections: who the outlet is, how settlement opens, what the bill says around the
/// figures, and how a document is laid out on the roll. Every one of them is verifiable
/// on this terminal today.
///
/// There is no printer address, no USB device, no network host and no pairing, because no
/// transport exists yet and a field to type an IP address into would say one does. There
/// is no tax rate and no discount, because nothing in this build charges either and an
/// input that changes nothing is worse than no input. There is no sync trigger, no
/// account and no backup, for the same reason.
///
/// ## How it is wired
///
/// The screen builds a [SettingsController] over the settings repository, the in-memory
/// configuration and the active print profile, and starts the read. Everything below is
/// widgets reporting what the operator did. No widget on this screen touches SQLite, and
/// no widget decides whether a value is acceptable.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SettingsController>(
      create: (BuildContext context) {
        final SettingsController controller = SettingsController(
          settings: context.read<SettingsRepository>(),
          printProfile: context.read<ActivePrintProfile>(),
          activeSettings: context.read<ActivePosSettings>(),
        );
        // Deliberately not awaited: the first frame renders the loading state while the
        // read runs.
        unawaited(controller.load());
        return controller;
      },
      child: const _SettingsView(),
    );
  }
}

/// Loading, a failure with a retry, or the form.
///
/// The three are mutually exclusive on purpose. A form shown beside a read failure would
/// hold blank fields that look like an unconfigured outlet, and saving them would
/// overwrite a real address with nothing.
class _SettingsView extends StatelessWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context) {
    final SettingsController controller = context.watch<SettingsController>();

    if (!controller.hasLoaded) {
      if (controller.hasError) {
        return SettingsErrorView(
          message: controller.errorMessage!,
          onRetry: controller.load,
        );
      }
      return const SettingsLoadingView();
    }

    return const SettingsForm();
  }
}
