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

/// The app version injected at release build time via `--dart-define`.
/// Local builds fall back to the `dev` sentinel.
// ignore: do_not_use_environment
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

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
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cryptic'),
            const SizedBox(width: 8),
            Text(
              _appVersion == 'dev' ? 'dev' : 'v$_appVersion',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _promptNewChat(context, ref),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('New chat'),
      ),
    );
  }

  /// Prompts for a username and starts a chat with that peer.
  ///
  /// Presence is not required to message a peer: the engine fetches the
  /// recipient's key bundle by username, runs X3DH, and the server queues
  /// the encrypted message until the peer reconnects. This lets a user start
  /// a conversation with anyone whose username they know, even while that
  /// peer is offline and therefore absent from the online-users list.
  Future<void> _promptNewChat(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final currentUsername = ref.read(currentUsernameProvider);

    final username = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final value = controller.text.trim();
              if (value.isEmpty) {
                setState(() => errorText = 'Enter a username');
                return;
              }
              if (value == currentUsername) {
                setState(() => errorText = "You can't chat with yourself");
                return;
              }
              Navigator.of(dialogContext).pop(value);
            }

            return AlertDialog(
              title: const Text('New chat'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'Enter a username',
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) {
                    setState(() => errorText = null);
                  }
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: submit,
                  child: const Text('Start chat'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (username != null && context.mounted) {
      _startChat(context, ref, username);
    }
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
