/// Connection status banner widget.
///
/// Displays the current connection state as a banner.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/engine/engine_state.dart';

/// A banner showing the current connection status.
class ConnectionStatusBanner extends StatelessWidget {
  /// Creates a connection status banner.
  const ConnectionStatusBanner({
    required this.status,
    super.key,
    this.onTap,
  });

  /// The current connection status.
  final ConnectionStatus status;

  /// Optional callback when banner is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Don't show banner when connected
    if (status == ConnectionStatus.connected) {
      return const SizedBox.shrink();
    }

    final (color, icon, text) = _getStatusInfo();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: color,
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (status == ConnectionStatus.connecting ||
                  status == ConnectionStatus.reconnecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    icon,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (status == ConnectionStatus.disconnected ||
                  status == ConnectionStatus.error)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'Tap to retry',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, IconData, String) _getStatusInfo() {
    return switch (status) {
      ConnectionStatus.disconnected => (
          AppColors.disconnected,
          Icons.cloud_off,
          'Disconnected',
        ),
      ConnectionStatus.connecting => (
          AppColors.connecting,
          Icons.cloud_sync,
          'Connecting...',
        ),
      ConnectionStatus.connected => (
          AppColors.connected,
          Icons.cloud_done,
          'Connected',
        ),
      ConnectionStatus.reconnecting => (
          AppColors.connecting,
          Icons.cloud_sync,
          'Reconnecting...',
        ),
      ConnectionStatus.error => (
          AppColors.connectionError,
          Icons.cloud_off,
          'Connection error',
        ),
    };
  }
}
