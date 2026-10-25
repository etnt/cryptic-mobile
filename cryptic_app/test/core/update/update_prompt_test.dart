// test/core/update/update_prompt_test.dart
//
// Widget tests for the startup update-check prompt. The checker is injected
// through releaseCheckerProvider — the same provider the real CrypticApp
// reads — so the tests exercise the actual wiring, with a fake checker so
// nothing touches the network.

import 'package:auto_upgrade/auto_upgrade.dart';
import 'package:cryptic_app/core/update/update_prompt.dart';
import 'package:cryptic_app/core/update/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [ReleaseChecker] that never touches the network: it resolves [check]
/// with a canned [result] and counts calls.
class _FakeChecker extends ReleaseChecker {
  _FakeChecker(this.result)
      : super(
          owner: 'etnt',
          repo: 'cryptic-mobile',
          currentVersion: '1.0.0',
        );

  final UpdateCheckResult result;

  int calls = 0;

  // A block body is required: the counter must be bumped before the result
  // is returned.
  // ignore: prefer_expression_function_bodies
  @override
  Future<UpdateCheckResult> check() async {
    calls++;
    return result;
  }
}

/// Pumps a minimal app that runs the update check after its first frame,
/// mirroring the CrypticApp hook, and records "Open" launches.
class _Harness extends StatelessWidget {
  const _Harness(this.launched);

  final List<UpdateInfo> launched;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: _TriggerPage(launched: launched),
      );
}

/// The page that triggers the check from *inside* the MaterialApp, matching
/// where the real CrypticApp calls it from — including reading the checker
/// from [releaseCheckerProvider] rather than taking it directly.
class _TriggerPage extends ConsumerStatefulWidget {
  const _TriggerPage({required this.launched});

  final List<UpdateInfo> launched;

  @override
  ConsumerState<_TriggerPage> createState() => _TriggerPageState();
}

class _TriggerPageState extends ConsumerState<_TriggerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybeShowUpdateDialog(
        context,
        checker: ref.read(releaseCheckerProvider),
        onUpdate: (info) async => widget.launched.add(info),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

/// Pumps the harness with [checker] injected through the same provider the
/// real CrypticApp reads, and returns the list that records "Open" launches
/// so tests can assert on the strategy.
Future<List<UpdateInfo>> _pumpHarness(
  WidgetTester tester,
  _FakeChecker checker,
) async {
  final launched = <UpdateInfo>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        releaseCheckerProvider.overrideWithValue(checker),
      ],
      child: _Harness(launched),
    ),
  );
  await tester.pumpAndSettle();
  return launched;
}

UpdateInfo get _updateInfo => const UpdateInfo(
      latestVersion: '1.2.0',
      currentVersion: '1.0.0',
      releasePageUrl: 'https://github.com/etnt/cryptic-mobile/releases/tag/v1.2.0',
      releaseNotes: 'Faster encryption.',
    );

void main() {
  testWidgets('UpdateAvailable shows the dialog with versions and notes',
      (tester) async {
    await _pumpHarness(tester, _FakeChecker(UpdateAvailable(_updateInfo)));

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('1.2.0'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
    expect(find.textContaining('Faster encryption.'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('"Open" invokes the strategy with the right UpdateInfo',
      (tester) async {
    final launched =
        await _pumpHarness(tester, _FakeChecker(UpdateAvailable(_updateInfo)));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(launched, hasLength(1));
    expect(launched.single.latestVersion, '1.2.0');
    expect(
      launched.single.releasePageUrl,
      'https://github.com/etnt/cryptic-mobile/releases/tag/v1.2.0',
    );
    // The dialog is gone.
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('"Later" pops without launching anything', (tester) async {
    final launched =
        await _pumpHarness(tester, _FakeChecker(UpdateAvailable(_updateInfo)));

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(find.text('Update available'), findsNothing);
  });

  for (final entry in {
    'UpToDate': const UpToDate(),
    'CheckSkipped': const CheckSkipped(),
    'CheckError': CheckError(Exception('offline')),
  }.entries) {
    testWidgets('${entry.key} shows nothing', (tester) async {
      await _pumpHarness(tester, _FakeChecker(entry.value));

      expect(find.text('Update available'), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(find.text('Open'), findsNothing);
    });
  }
}
