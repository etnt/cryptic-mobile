/// User avatar widget.
///
/// Displays a user avatar with optional online status indicator.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A user avatar with optional status indicator.
class UserAvatar extends StatelessWidget {
  /// Creates a user avatar.
  const UserAvatar({
    required this.username,
    super.key,
    this.size = 40,
    this.isOnline,
    this.imageUrl,
    this.hasSession = false,
  });

  /// The username to display initials for.
  final String username;

  /// Avatar size in logical pixels.
  final double size;

  /// Whether user is online (null = unknown).
  final bool? isOnline;

  /// Optional image URL for avatar.
  final String? imageUrl;

  /// Whether an encrypted session exists with this user.
  final bool hasSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
          child: imageUrl == null
              ? Text(
                  _getInitials(),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: size * 0.4,
                  ),
                )
              : null,
        ),
        if (isOnline != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: isOnline! ? AppColors.connected : AppColors.disconnected,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        if (hasSession)
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                color: AppColors.encrypted,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.lock,
                size: size * 0.15,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  String _getInitials() {
    if (username.isEmpty) return '?';

    final parts = username.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return username[0].toUpperCase();
  }
}
