/// Diagnostics screen.
///
/// Read-only screen displaying certificate status, engine/connection state,
/// identity key fingerprints, per-peer ratchet session details, and
/// application configuration.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/diagnostics_provider.dart';

/// Screen showing application diagnostics and status information.
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(diagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
        ],
      ),
      body: diagnostics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load diagnostics:\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (data) => _DiagnosticsBody(data: data),
      ),
    );
  }
}

class _DiagnosticsBody extends StatelessWidget {
  const _DiagnosticsBody({required this.data});

  final DiagnosticsData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _CertificateSection(cert: data.certificate),
        const SizedBox(height: 12),
        _ConnectionSection(conn: data.connection),
        const SizedBox(height: 12),
        _KeysSection(keys: data.keys),
        const SizedBox(height: 12),
        _SessionsSection(sessions: data.sessions),
        const SizedBox(height: 12),
        _AppSection(app: data.app),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate Section
// ─────────────────────────────────────────────────────────────────────────────

class _CertificateSection extends StatelessWidget {
  const _CertificateSection({required this.cert});

  final CertificateDiag cert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expiryColor = cert.isExpired ? theme.colorScheme.error : null;

    return _DiagCard(
      icon: Icons.verified_user,
      title: 'Certificate',
      children: [
        _Row('Username', cert.username ?? 'N/A'),
        _Row(
          'Server',
          cert.serverHost != null
              ? '${cert.serverHost}:${cert.serverPort}'
              : 'N/A',
        ),
        _Row('Imported', _formatDate(cert.importedAt)),
        _Row(
          'Expires',
          cert.expiresAt != null
              ? '${_formatDate(cert.expiresAt)} (${cert.daysUntilExpiry ?? "?"} days)'
              : 'N/A',
          valueColor: expiryColor,
        ),
        _Row(
          'Fingerprint',
          cert.fingerprint ?? 'N/A',
          copyable: cert.fingerprint != null,
        ),
        _Row(
          'Status',
          cert.isExpired ? 'EXPIRED' : 'Valid',
          valueColor: cert.isExpired
              ? theme.colorScheme.error
              : theme.colorScheme.primary,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection Section
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.conn});

  final ConnectionDiag conn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = conn.connectionStatus == 'connected';

    return _DiagCard(
      icon: Icons.cloud,
      title: 'Connection',
      children: [
        _Row('Engine status', conn.engineStatus),
        _Row(
          'Connection',
          conn.connectionStatus,
          valueColor:
              isConnected ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        _Row('WebSocket URL', conn.wsUrl ?? 'N/A'),
        _Row('Last connected', _formatDate(conn.lastConnectedAt)),
        _Row('Reconnect attempts', '${conn.reconnectAttempts}'),
        _Row('Keys uploaded', conn.keysUploaded ? 'yes' : 'no'),
        _Row('Online users', '${conn.onlineUserCount}'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity Keys Section
// ─────────────────────────────────────────────────────────────────────────────

class _KeysSection extends StatelessWidget {
  const _KeysSection({required this.keys});

  final KeysDiag keys;

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      icon: Icons.key,
      title: 'Identity Keys',
      children: [
        _Row(
          'Signing key',
          keys.signingKeyFingerprint ??
              (keys.hasIdentityKeys ? 'present' : 'none'),
          copyable: keys.signingKeyFingerprint != null,
          mono: true,
        ),
        _Row(
          'Signed prekey ID',
          keys.signedPrekeyId?.toString() ?? 'N/A',
        ),
        _Row('One-time prekeys', '${keys.oneTimePrekeyCount} remaining'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sessions Section
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsSection extends StatelessWidget {
  const _SessionsSection({required this.sessions});

  final Map<String, Map<String, dynamic>> sessions;

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      icon: Icons.chat_bubble_outline,
      title: 'Sessions (${sessions.length})',
      children: sessions.isEmpty
          ? [const _Row('', 'No active sessions')]
          : sessions.entries
              .map((e) => _PeerTile(peer: e.key, data: e.value))
              .toList(),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, required this.data});

  final String peer;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      title: Text(peer, style: theme.textTheme.titleSmall),
      children: [
        _Row('DH ratchet step', '${data['dh_ratchet_step'] ?? '?'}'),
        _Row('Messages sent', '${data['send_message_number'] ?? '?'}'),
        _Row('Messages received', '${data['recv_message_number'] ?? '?'}'),
        _Row('Skipped keys', '${data['skipped_keys_count'] ?? '0'}'),
        _Row('Created', _formatDate(_parseIso(data['created_at']))),
        _Row('Last updated', _formatDate(_parseIso(data['last_updated']))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App Section
// ─────────────────────────────────────────────────────────────────────────────

class _AppSection extends StatelessWidget {
  const _AppSection({required this.app});

  final AppDiag app;

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      icon: Icons.info_outline,
      title: 'App',
      children: [
        _Row('Environment', app.environment),
        _Row('Version', app.version),
        _Row('Log level', app.logLevel),
        _Row('Config server', '${app.serverHost}:${app.serverPort}'),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DiagCard extends StatelessWidget {
  const _DiagCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(
    this.label,
    this.value, {
    this.valueColor,
    this.copyable = false,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool copyable;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final valueStyle = (mono
            ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
            : theme.textTheme.bodyMedium)
        ?.copyWith(color: valueColor);

    if (label.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: copyable
                ? GestureDetector(
                    onLongPress: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$label copied'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Text(value, style: valueStyle),
                  )
                : Text(value, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _formatDate(DateTime? dt) {
  if (dt == null) return 'N/A';
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
      '${_pad(dt.hour)}:${_pad(dt.minute)}';
}

String _pad(int n) => n.toString().padLeft(2, '0');

DateTime? _parseIso(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}
