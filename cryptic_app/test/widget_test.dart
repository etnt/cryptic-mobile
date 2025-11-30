// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cryptic_app/presentation/app.dart';

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
      const ProviderScope(
        child: CrypticApp(),
      ),
    );

    // Verify the app renders correctly
    expect(find.byType(MaterialApp), findsOneWidget);

    // Pump and settle to let all timers complete (splash screen animation)
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
