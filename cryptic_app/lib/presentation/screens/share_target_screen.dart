/// Share target screen.
///
/// Lets the user pick the peer that receives files shared from another app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/engine_provider.dart';
import '../providers/incoming_share_provider.dart';
import '../providers/messages_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// Peer picker for pending shares.
///
/// Peers are disabled until the engine is connected, so nothing is sent
/// while offline. Cancelling deletes the pending copies.
class ShareTargetScreen extends ConsumerWidget {
  /// Creates the share target screen.
  const ShareTargetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(incomingShareProvider);
    final users = ref.watch(usersProvider);
    final connected = ref.watch(isConnectedProvider);

    // Back and swipe discard the pending copies, as Cancel does.
    // canPop is true so iOS swipe-back works; the pop already happened when
    // didPop is true, so only the copies still need to be discarded.
    return PopScope(
      // ignore: avoid_redundant_argument_values, spelled out on purpose
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          await ref.read(incomingShareProvider.notifier).discard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel',
            onPressed: () async {
              final navigator = Navigator.of(context);
              await ref.read(incomingShareProvider.notifier).discard();
              navigator.pop();
            },
          ),
          title: const Text('Send to'),
        ),
        body: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(
                shares.length == 1
                    ? shares.single.fileName
                    : '${shares.length} files',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                shares.length == 1
                    ? 'Choose who receives this file'
                    : 'Choose who receives these files',
              ),
            ),
            if (!connected)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('Connecting to server…')),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: users.isEmpty
                  ? EmptyState.noUsers(
                      onRefresh: () =>
                          ref.read(engineProvider)?.requestUserList(),
                    )
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final username = users[index];
                        return ListTile(
                          leading: UserAvatar(
                            username: username,
                          ),
                          title: Text(username),
                          enabled: connected,
                          onTap: connected
                              ? () => _sendTo(context, ref, username)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the chat with [username]. The chat takes the pending shares
  /// when it opens.
  void _sendTo(BuildContext context, WidgetRef ref, String username) {
    ref.read(selectedPeerProvider.notifier).state = username;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(peerId: username, takeSharedFiles: true),
      ),
    );
  }
}
