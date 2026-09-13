import 'package:brisko_billing/app/bootstrap.dart';
import 'package:brisko_billing/app/brisko_app.dart';
import 'package:brisko_billing/app/shell/pos_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';
import 'helpers/test_dependencies.dart';

/// Builds the dependency graph against an in-memory database.
///
/// The widget tests drive the real repositories rather than fakes, because the shell
/// has to be able to construct them. Nothing here writes to a real database file.
Future<AppDependencies> _testDependencies() async {
  return TestDependencies.over(await TestDatabase.openInMemory());
}

void main() {
  setUpAll(TestDatabase.register);

  late AppDependencies dependencies;

  setUp(() async {
    dependencies = await _testDependencies();
  });

  tearDown(() async {
    await dependencies.dispose();
  });

  group('PosShell', () {
    testWidgets('starts on the dashboard section', (WidgetTester tester) async {
      await tester.pumpWidget(BriskoApp(dependencies: dependencies));

      // Title in the app bar, plus the heading rendered by the placeholder.
      expect(find.text(PosSection.dashboard.label), findsWidgets);
    });

    testWidgets('navigating the rail swaps the active section', (
      WidgetTester tester,
    ) async {
      // Wide enough to render the navigation rail rather than the bottom bar.
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(BriskoApp(dependencies: dependencies));

      expect(find.byType(NavigationRail), findsOneWidget);

      await tester.tap(find.text(PosSection.reports.label));
      await tester.pumpAndSettle();

      expect(find.text(PosSection.reports.label), findsWidgets);
      expect(find.text(PosSection.dashboard.label), findsOneWidget);
    });
  });
}
