// lib/data/storage/message_database.dart
//
// SQLCipher-backed message database for persisting chat history.
//
// Uses sqflite_sqlcipher to store messages in an encrypted SQLite database.
// The database password is derived from the user's passphrase using SHA-256,
// so message history is protected at rest.

import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../domain/models/message.dart';

/// Encrypted message database backed by SQLCipher.
///
/// Stores chat messages and conversation metadata. The database is
/// encrypted with a key derived from the user's passphrase.
class MessageDatabase {
  /// Creates a message database instance.
  MessageDatabase();

  Database? _db;

  /// Whether the database is open.
  bool get isOpen => _db != null;

  /// Open (or create) the encrypted database.
  ///
  /// [passphrase] is used to derive the SQLCipher encryption key.
  /// [username] scopes the database file per user.
  Future<void> open({
    required String passphrase,
    required String username,
  }) async {
    if (_db != null) return;

    final dir = await getApplicationSupportDirectory();
    final dbPath = '${dir.path}/cryptic_${username}_messages.db';
    final dbPassword = _deriveDbPassword(passphrase, username);

    _db = await openDatabase(
      dbPath,
      version: 1,
      password: dbPassword,
      onCreate: _onCreate,
    );
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Schema
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        read_at INTEGER,
        delivered_at INTEGER,
        failure_reason TEXT,
        is_deleted INTEGER DEFAULT 0,
        reply_to_id TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_conversation
        ON messages(conversation_id, timestamp)
    ''');

    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        peer_username TEXT NOT NULL UNIQUE,
        unread_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        is_muted INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Messages
  // ─────────────────────────────────────────────────────────────────────────

  /// Insert a message. Replaces on conflict (idempotent).
  Future<void> insertMessage(ChatMessage message) async {
    final db = _requireDb();
    await db.insert(
      'messages',
      _messageToRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load messages for a conversation, ordered by timestamp ascending.
  ///
  /// [limit] caps the number of messages returned (newest N).
  Future<List<ChatMessage>> getMessages(
    String conversationId, {
    int limit = 200,
  }) async {
    final db = _requireDb();
    // Sub-select newest N, then order ascending for display.
    final rows = await db.rawQuery(
      '''
      SELECT * FROM (
        SELECT * FROM messages
        WHERE conversation_id = ? AND is_deleted = 0
        ORDER BY timestamp DESC
        LIMIT ?
      ) sub ORDER BY timestamp ASC
      ''',
      [conversationId, limit],
    );
    return rows.map(_rowToMessage).toList();
  }

  /// Update the status of a message.
  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = _requireDb();
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all messages for a conversation.
  Future<void> deleteConversationMessages(String conversationId) async {
    final db = _requireDb();
    await db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Conversations
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensure a conversation row exists. Creates if missing.
  Future<void> ensureConversation(String peerUsername) async {
    final db = _requireDb();
    await db.insert(
      'conversations',
      {
        'id': peerUsername, // use peer username as ID
        'peer_username': peerUsername,
        'unread_count': 0,
        'is_pinned': 0,
        'is_muted': 0,
        'is_archived': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Increment unread count for a conversation.
  Future<void> incrementUnread(String peerUsername) async {
    final db = _requireDb();
    await db.rawUpdate(
      'UPDATE conversations SET unread_count = unread_count + 1 WHERE peer_username = ?',
      [peerUsername],
    );
  }

  /// Reset unread count for a conversation.
  Future<void> markAsRead(String peerUsername) async {
    final db = _requireDb();
    await db.update(
      'conversations',
      {'unread_count': 0},
      where: 'peer_username = ?',
      whereArgs: [peerUsername],
    );
  }

  /// Load all conversations with their last message and unread count.
  Future<List<ConversationRow>> loadConversations() async {
    final db = _requireDb();
    final rows = await db.rawQuery('''
      SELECT c.peer_username, c.unread_count, c.is_pinned, c.is_muted,
             c.is_archived, c.created_at,
             m.id AS last_msg_id, m.sender_id AS last_msg_sender,
             m.content AS last_msg_content, m.timestamp AS last_msg_ts,
             m.direction AS last_msg_dir, m.status AS last_msg_status
      FROM conversations c
      LEFT JOIN messages m ON m.conversation_id = c.peer_username
        AND m.timestamp = (
          SELECT MAX(m2.timestamp) FROM messages m2
          WHERE m2.conversation_id = c.peer_username AND m2.is_deleted = 0
        )
      ORDER BY COALESCE(m.timestamp, c.created_at) DESC
    ''');
    return rows.map(ConversationRow.fromRow).toList();
  }

  /// Delete a conversation and its messages.
  Future<void> deleteConversation(String peerUsername) async {
    final db = _requireDb();
    await db.transaction((txn) async {
      await txn.delete('messages',
          where: 'conversation_id = ?', whereArgs: [peerUsername]);
      await txn.delete('conversations',
          where: 'peer_username = ?', whereArgs: [peerUsername]);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Database _requireDb() {
    final db = _db;
    if (db == null) throw StateError('MessageDatabase is not open');
    return db;
  }

  /// Derive a database password from the user passphrase.
  ///
  /// Uses SHA-256(passphrase + fixed salt) to produce a hex key.
  /// This is not a full Argon2id derivation — the passphrase has
  /// already been verified via Argon2id before reaching here,
  /// and SQLCipher internally applies PBKDF2 to the supplied key.
  static String _deriveDbPassword(String passphrase, String username) {
    final input = utf8.encode('$passphrase:cryptic_msg_db:$username');
    final digest = SHA256Digest().process(Uint8List.fromList(input));
    // Convert to hex string
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── Row mapping ──

  Map<String, Object?> _messageToRow(ChatMessage m) => {
        'id': m.id,
        'conversation_id': m.conversationId,
        'sender_id': m.senderId,
        'content': m.content,
        'timestamp': m.timestamp.millisecondsSinceEpoch,
        'direction': m.direction.name,
        'status': m.status.name,
        'read_at': m.readAt?.millisecondsSinceEpoch,
        'delivered_at': m.deliveredAt?.millisecondsSinceEpoch,
        'failure_reason': m.failureReason,
        'is_deleted': m.isDeleted ? 1 : 0,
        'reply_to_id': m.replyToId,
      };

  ChatMessage _rowToMessage(Map<String, Object?> row) => ChatMessage(
        id: row['id']! as String,
        conversationId: row['conversation_id']! as String,
        senderId: row['sender_id']! as String,
        content: row['content']! as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(row['timestamp']! as int),
        direction: MessageDirection.values.byName(row['direction']! as String),
        status: MessageStatus.values.byName(row['status']! as String),
        readAt: row['read_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['read_at']! as int)
            : null,
        deliveredAt: row['delivered_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['delivered_at']! as int)
            : null,
        failureReason: row['failure_reason'] as String?,
        isDeleted: (row['is_deleted'] as int?) == 1,
        replyToId: row['reply_to_id'] as String?,
      );
}

/// Lightweight row returned by [MessageDatabase.loadConversations].
class ConversationRow {
  const ConversationRow({
    required this.peerUsername,
    required this.unreadCount,
    required this.createdAt,
    this.lastMessageId,
    this.lastMessageSender,
    this.lastMessageContent,
    this.lastMessageTimestamp,
    this.lastMessageDirection,
    this.lastMessageStatus,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
  });

  factory ConversationRow.fromRow(Map<String, Object?> row) => ConversationRow(
        peerUsername: row['peer_username']! as String,
        unreadCount: (row['unread_count'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (row['created_at'] as int?) ?? 0),
        lastMessageId: row['last_msg_id'] as String?,
        lastMessageSender: row['last_msg_sender'] as String?,
        lastMessageContent: row['last_msg_content'] as String?,
        lastMessageTimestamp: row['last_msg_ts'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['last_msg_ts']! as int)
            : null,
        lastMessageDirection: row['last_msg_dir'] != null
            ? MessageDirection.values.byName(row['last_msg_dir']! as String)
            : null,
        lastMessageStatus: row['last_msg_status'] != null
            ? MessageStatus.values.byName(row['last_msg_status']! as String)
            : null,
        isPinned: (row['is_pinned'] as int?) == 1,
        isMuted: (row['is_muted'] as int?) == 1,
        isArchived: (row['is_archived'] as int?) == 1,
      );

  final String peerUsername;
  final int unreadCount;
  final DateTime createdAt;
  final String? lastMessageId;
  final String? lastMessageSender;
  final String? lastMessageContent;
  final DateTime? lastMessageTimestamp;
  final MessageDirection? lastMessageDirection;
  final MessageStatus? lastMessageStatus;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
}
