// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in your test. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:cryptic_app/core/update/update_service.dart';
import 'package:cryptic_app/presentation/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A no-op checker so the smoke test never touches the network, even though
/// the default provider's `dev` sentinel already short-circuits the check.
class _NoOpChecker extends ReleaseChecker {
  _NoOpChecker()
      : super(owner: 'etnt', repo: 'cryptic-mobile', currentVersion: 'dev');

  @override
  Future<UpdateCheckResult> check() async => const CheckSkipped();
}

void main() {
  testWidgets('CrypticApp smoke test', (tester) async {
    // Set a larger surface size to avoid overflow issues
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          releaseCheckerProvider.overrideWithValue(_NoOpChecker()),
        ],
        child: const CrypticApp(),
      ),
    );

    // Verify the app renders correctly
    expect(find.byType(MaterialApp), findsOneWidget);

    // The splash screen shows a CircularProgressIndicator, which animates
    // forever, so pumpAndSettle would never return. Pump a fixed duration.
    await tester.pump(const Duration(seconds: 2));
  });
}
