import 'dart:convert';

enum CtrlTab { home, favorites, contacts, calls, settings }

extension CtrlTabX on CtrlTab {
  String get apiTab => switch (this) {
    CtrlTab.home => 'home',
    CtrlTab.favorites => 'favorites',
    CtrlTab.contacts => 'contacts',
    CtrlTab.calls => 'calls',
    CtrlTab.settings => 'home',
  };
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.lastSeenAt,
  });

  final int id;
  final String email;
  final String? username;
  final String displayName;
  final String? avatarUrl;
  final String bio;
  final String? lastSeenAt;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      email: (json['email'] ?? '') as String,
      username: json['username'] as String?,
      displayName: (json['displayName'] ?? '') as String,
      avatarUrl: json['avatarUrl'] as String?,
      bio: (json['bio'] ?? '') as String,
      lastSeenAt: json['lastSeenAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'lastSeenAt': lastSeenAt,
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: AuthUser.fromJson(
        (json['user'] ?? const {}) as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'user': user.toJson(),
    };
  }
}

class ChatPreferences {
  const ChatPreferences({
    required this.muted,
    required this.pinned,
    required this.favorite,
    required this.archived,
  });

  final bool muted;
  final bool pinned;
  final bool favorite;
  final bool archived;

  factory ChatPreferences.fromJson(Map<String, dynamic> json) {
    return ChatPreferences(
      muted: json['muted'] == true,
      pinned: json['pinned'] == true,
      favorite: json['favorite'] == true,
      archived: json['archived'] == true,
    );
  }
}

class ChatPeer {
  const ChatPeer({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.lastSeenAt,
  });

  final int id;
  final String? username;
  final String displayName;
  final String? avatarUrl;
  final String? lastSeenAt;

  factory ChatPeer.fromJson(Map<String, dynamic> json) {
    return ChatPeer(
      id: (json['id'] ?? 0) as int,
      username: json['username'] as String?,
      displayName: (json['displayName'] ?? 'Unknown') as String,
      avatarUrl: json['avatarUrl'] as String?,
      lastSeenAt: json['lastSeenAt'] as String?,
    );
  }
}

class ChatMessagePreview {
  const ChatMessagePreview({
    required this.id,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.senderId,
  });

  final String id;
  final String? text;
  final String type;
  final String createdAt;
  final int senderId;

  factory ChatMessagePreview.fromJson(Map<String, dynamic> json) {
    return ChatMessagePreview(
      id: (json['id'] ?? '') as String,
      text: json['text'] as String?,
      type: (json['type'] ?? 'text') as String,
      createdAt: (json['createdAt'] ?? '') as String,
      senderId: (json['senderId'] ?? 0) as int,
    );
  }
}

class ChatItem {
  const ChatItem({
    required this.id,
    required this.type,
    required this.title,
    required this.updatedAt,
    required this.preferences,
    required this.peer,
    required this.lastMessage,
  });

  final String id;
  final String type;
  final String title;
  final String updatedAt;
  final ChatPreferences preferences;
  final ChatPeer? peer;
  final ChatMessagePreview? lastMessage;

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    return ChatItem(
      id: (json['id'] ?? '') as String,
      type: (json['type'] ?? 'direct') as String,
      title: (json['title'] ?? 'Chat') as String,
      updatedAt: (json['updatedAt'] ?? '') as String,
      preferences: ChatPreferences.fromJson(
        (json['preferences'] ?? const {}) as Map<String, dynamic>,
      ),
      peer: json['peer'] == null
          ? null
          : ChatPeer.fromJson(json['peer'] as Map<String, dynamic>),
      lastMessage: json['lastMessage'] == null
          ? null
          : ChatMessagePreview.fromJson(
              json['lastMessage'] as Map<String, dynamic>,
            ),
    );
  }
}

class MessageReaction {
  const MessageReaction({required this.userId, required this.emoji});

  final int userId;
  final String emoji;

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: (json['userId'] ?? 0) as int,
      emoji: (json['emoji'] ?? '') as String,
    );
  }
}

class MessageSender {
  const MessageSender({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
  });

  final int id;
  final String? username;
  final String displayName;
  final String? avatarUrl;

  factory MessageSender.fromJson(Map<String, dynamic> json) {
    return MessageSender(
      id: (json['id'] ?? 0) as int,
      username: json['username'] as String?,
      displayName: (json['displayName'] ?? '') as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.sender,
    required this.text,
    required this.ciphertext,
    required this.type,
    required this.replyToId,
    required this.editedAt,
    required this.createdAt,
    required this.reactions,
  });

  final String id;
  final String chatId;
  final int senderId;
  final MessageSender sender;
  final String? text;
  final String? ciphertext;
  final String type;
  final String? replyToId;
  final String? editedAt;
  final String createdAt;
  final List<MessageReaction> reactions;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '') as String,
      chatId: (json['chatId'] ?? '') as String,
      senderId: (json['senderId'] ?? 0) as int,
      sender: MessageSender.fromJson(
        (json['sender'] ?? const {}) as Map<String, dynamic>,
      ),
      text: json['text'] as String?,
      ciphertext: json['ciphertext'] as String?,
      type: (json['type'] ?? 'text') as String,
      replyToId: json['replyToId'] as String?,
      editedAt: json['editedAt'] as String?,
      createdAt: (json['createdAt'] ?? '') as String,
      reactions: ((json['reactions'] ?? const <dynamic>[]) as List<dynamic>)
          .map(
            (entry) => MessageReaction.fromJson(entry as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class Contact {
  const Contact({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarUrl,
    required this.lastSeenAt,
  });

  final int id;
  final String? username;
  final String displayName;
  final String? avatarUrl;
  final String? lastSeenAt;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: (json['id'] ?? 0) as int,
      username: json['username'] as String?,
      displayName: (json['displayName'] ?? 'Unknown') as String,
      avatarUrl: json['avatarUrl'] as String?,
      lastSeenAt: json['lastSeenAt'] as String?,
    );
  }
}

class CallLog {
  const CallLog({
    required this.id,
    required this.peerName,
    required this.peerUsername,
    required this.peerAvatar,
    required this.direction,
    required this.status,
    required this.startedAt,
  });

  final String id;
  final String? peerName;
  final String? peerUsername;
  final String? peerAvatar;
  final String direction;
  final String status;
  final String startedAt;

  factory CallLog.fromJson(Map<String, dynamic> json) {
    return CallLog(
      id: (json['id'] ?? '') as String,
      peerName: json['peerName'] as String?,
      peerUsername: json['peerUsername'] as String?,
      peerAvatar: json['peerAvatar'] as String?,
      direction: (json['direction'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      startedAt: (json['startedAt'] ?? '') as String,
    );
  }
}

class StoredAccount {
  const StoredAccount({required this.session});

  final AuthSession session;

  Map<String, dynamic> toJson() => {'session': session.toJson()};

  factory StoredAccount.fromJson(Map<String, dynamic> json) {
    return StoredAccount(
      session: AuthSession.fromJson(
        (json['session'] ?? const {}) as Map<String, dynamic>,
      ),
    );
  }

  static List<StoredAccount> decodeList(String raw) {
    final jsonList = jsonDecode(raw) as List<dynamic>;
    return jsonList
        .map((entry) => StoredAccount.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<StoredAccount> accounts) {
    return jsonEncode(accounts.map((entry) => entry.toJson()).toList());
  }
}
