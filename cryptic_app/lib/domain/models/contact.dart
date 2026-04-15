/// Contact domain model.
///
/// Represents a user contact.
library;

/// Contact status enum.
enum ContactStatus {
  /// Contact is online.
  online,

  /// Contact is offline.
  offline,

  /// Contact status is unknown.
  unknown,
}

/// Contact entity.
///
/// Represents a user in the contact list.
class Contact {
  /// Creates a contact.
  const Contact({
    required this.username,
    this.displayName,
    this.status = ContactStatus.unknown,
    this.lastSeenAt,
    this.hasSession = false,
    this.isVerified = false,
    this.isTrusted = false,
    this.addedAt,
  });

  /// The contact's username.
  final String username;

  /// The contact's display name (if set).
  final String? displayName;

  /// The contact's online status.
  final ContactStatus status;

  /// When the contact was last seen online.
  final DateTime? lastSeenAt;

  /// Whether there's an active session with this contact.
  final bool hasSession;

  /// Whether the contact's identity has been verified.
  final bool isVerified;

  /// Whether this contact is marked as trusted.
  final bool isTrusted;

  /// When the contact was added.
  final DateTime? addedAt;

  /// Get the display name (display name or username).
  String get name => displayName ?? username;

  /// Whether the contact is online.
  bool get isOnline => status == ContactStatus.online;

  /// Create a copy with updated fields.
  Contact copyWith({
    String? username,
    String? displayName,
    ContactStatus? status,
    DateTime? lastSeenAt,
    bool? hasSession,
    bool? isVerified,
    bool? isTrusted,
    DateTime? addedAt,
  }) => Contact(
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      hasSession: hasSession ?? this.hasSession,
      isVerified: isVerified ?? this.isVerified,
      isTrusted: isTrusted ?? this.isTrusted,
      addedAt: addedAt ?? this.addedAt,
    );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Contact &&
          runtimeType == other.runtimeType &&
          username == other.username;

  @override
  int get hashCode => username.hashCode;

  @override
  String toString() =>
      'Contact(username: $username, status: $status, verified: $isVerified)';
}
