/// Users screen.
///
/// Displays the list of registered users from the server.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/engine_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'diagnostics_screen.dart';

/// Screen showing available users to chat with.
class UsersScreen extends ConsumerWidget {
  /// Creates a users screen.
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final sessions = ref.watch(sessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Diagnostics',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DiagnosticsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final engine = ref.read(engineProvider);
              print(
                  '[UsersScreen] Refresh pressed, engine=$engine, isConnected=${engine?.isConnected}');
              engine?.requestUserList();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: users.isEmpty
          ? EmptyState.noUsers(
              onRefresh: () {
                final engine = ref.read(engineProvider);
                print(
                    '[UsersScreen] Empty state refresh, engine=$engine, isConnected=${engine?.isConnected}');
                engine?.requestUserList();
              },
            )
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final username = users[index];
                final hasSession = sessions.containsKey(username);

                return ListTile(
                  leading: UserAvatar(
                    username: username,
                    hasSession: hasSession,
                  ),
                  title: Text(username),
                  subtitle: Text(
                    hasSession ? 'Encrypted session' : 'Tap to start chat',
                    style: TextStyle(
                      color: hasSession
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  trailing: hasSession
                      ? Icon(
                          Icons.lock,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: () => _startChat(context, ref, username),
                );
              },
            ),
    );
  }

  void _startChat(BuildContext context, WidgetRef ref, String username) {
    // Set the selected peer
    ref.read(selectedPeerProvider.notifier).state = username;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ChatScreen(peerId: username),
      ),
    );
  }
}
