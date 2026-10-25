// lib/presentation/screens/settings_screen.dart
//
// Settings for the background message connection (Android foreground service).
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/engine/cryptic_engine.dart';
import '../../data/services/background_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/storage/preferences/encrypted_preferences.dart';
import '../providers/auth_provider.dart';

/// Screen with the background-connection toggle and battery-optimization
/// controls.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _backgroundEnabled = true;
  bool _batteryExempt = false;
  bool _serviceRunning = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = EncryptedPreferences();
    final enabled = await prefs.backgroundConnectionEnabled;
    final exempt = await BackgroundService.instance.isBatteryExempt;
    final running = await BackgroundService.instance.isRunning;
    if (!mounted) return;
    setState(() {
      _backgroundEnabled = enabled;
      _batteryExempt = exempt;
      _serviceRunning = running;
      _loading = false;
    });
  }

  Future<void> _toggleBackground(bool value) async {
    final prefs = EncryptedPreferences();
    await prefs.setBackgroundConnectionEnabled(value);
    // Apply the reconnect policy to the live engine immediately: the policy
    // is otherwise only read at login, so switching the toggle would leave
    // the running engine at the default 10 attempts (on) or keep unlimited
    // retries running (off). 0 = unlimited, matching authentication_service.
    ref.read(authenticatedEngineProvider)?.maxReconnectAttempts =
        value ? 0 : CrypticEngine.defaultMaxReconnectAttempts;
    if (value) {
      await NotificationService.instance.requestPermission();
      await BackgroundService.instance.start();
    } else {
      await BackgroundService.instance.stop();
    }
    if (!mounted) return;
    setState(() => _backgroundEnabled = value);
    await _load();
  }

  Future<void> _requestExemption() async {
    final ok = await BackgroundService.instance.requestBatteryExemption();
    if (!ok) {
      // Direct request blocked (e.g. OEM restriction): fall back to the
      // battery-optimization settings page.
      await BackgroundService.instance.openBatterySettings();
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(8),
              children: [
                if (!Platform.isAndroid)
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Background connection is Android-only'),
                  )
                else ...[
                  SwitchListTile(
                    title: const Text('Keep background connection on'),
                    subtitle: const Text(
                      'Keeps an encrypted connection alive so messages arrive '
                      'while the app is closed. Shows a permanent, silent '
                      'notification. Turn off to save battery (messages then '
                      'arrive only when the app is open).',
                    ),
                    value: _backgroundEnabled,
                    onChanged: (value) =>
                        unawaited(_toggleBackground(value)),
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(
                      _batteryExempt
                          ? Icons.battery_saver
                          : Icons.battery_alert,
                      color: _batteryExempt
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    title: const Text('Battery optimization'),
                    subtitle: Text(
                      _batteryExempt
                          ? 'Exempt - background delivery is unrestricted.'
                          : 'Restricted. Allow Cryptic to run unrestricted '
                              'for reliable background delivery.',
                    ),
                    trailing: _batteryExempt
                        ? const Icon(Icons.check_circle)
                        : TextButton(
                            onPressed: () => unawaited(_requestExemption()),
                            child: const Text('Allow'),
                          ),
                    onTap: _batteryExempt ? null : () => unawaited(_requestExemption()),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Device-specific tips',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        const Text(
                          'Some phone makers kill background apps even with '
                          'the exemption above. If messages arrive late:\n\n'
                          '• Xiaomi / MIUI: Settings → Apps → Cryptic → '
                          'Autostart ON, Battery → No restrictions.\n'
                          '• Huawei / EMUI: Settings → Battery → App launch '
                          '→ Cryptic → manage manually, all switches ON.\n'
                          '• Samsung: Settings → Battery → Background usage '
                          'limits → remove Cryptic from "Sleeping apps".\n'
                          '• Oppo / Vivo: allow background running and lock '
                          'Cryptic in the recent-apps list.',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _serviceRunning
                              ? 'Background service: running'
                              : 'Background service: stopped',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
