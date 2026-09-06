class MemberInfo {
  final String displayName;
  final String? photoUrl;
  const MemberInfo({required this.displayName, this.photoUrl});

  factory MemberInfo.fromJson(Map<String, dynamic> j) => MemberInfo(
        displayName: j['displayName'] as String? ?? 'Użytkownik',
        photoUrl: j['photoUrl'] as String?,
      );
}

class ReplyPreview {
  final String id;
  final String senderId;
  final String text;
  const ReplyPreview({
    required this.id,
    required this.senderId,
    required this.text,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: j['id'] as String? ?? '',
        senderId: j['senderId'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool seen;
  final String? clientId;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final ReplyPreview? replyTo;
  final bool pending; // lokalne — optimistic UI
  final bool failed; // lokalne

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.seen = false,
    this.clientId,
    this.editedAt,
    this.deletedAt,
    this.replyTo,
    this.pending = false,
    this.failed = false,
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        conversationId: j['conversationId'] as String,
        senderId: j['senderId'] as String,
        text: j['text'] as String? ?? '',
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        seen: j['seen'] as bool? ?? false,
        clientId: j['clientId'] as String?,
        editedAt: DateTime.tryParse(j['editedAt'] as String? ?? '')?.toLocal(),
        deletedAt:
            DateTime.tryParse(j['deletedAt'] as String? ?? '')?.toLocal(),
        replyTo: j['replyTo'] is Map
            ? ReplyPreview.fromJson(
                (j['replyTo'] as Map).cast<String, dynamic>())
            : null,
      );

  ChatMessage copyWith({
    String? id,
    String? text,
    bool? seen,
    bool? pending,
    bool? failed,
    DateTime? editedAt,
    DateTime? deletedAt,
    ReplyPreview? replyTo,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId,
        senderId: senderId,
        text: text ?? this.text,
        createdAt: createdAt,
        seen: seen ?? this.seen,
        clientId: clientId,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        replyTo: replyTo ?? this.replyTo,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

class Conversation {
  final String id;
  final List<String> members;
  final Map<String, MemberInfo> memberInfo;
  final String? lastText;
  final String? lastSenderId;
  final DateTime? lastAt;
  final int unread;
  final DateTime updatedAt;

  const Conversation({
    required this.id,
    required this.members,
    required this.memberInfo,
    required this.updatedAt,
    this.lastText,
    this.lastSenderId,
    this.lastAt,
    this.unread = 0,
  });

  String otherId(String me) =>
      members.firstWhere((m) => m != me, orElse: () => me);
  MemberInfo? other(String me) => memberInfo[otherId(me)];

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final lm = j['lastMessage'] as Map<String, dynamic>?;
    return Conversation(
      id: j['id'] as String,
      members: (j['members'] as List).cast<String>(),
      memberInfo: (j['memberInfo'] as Map<String, dynamic>? ?? {}).map(
        (k, v) => MapEntry(
            k, MemberInfo.fromJson((v as Map).cast<String, dynamic>())),
      ),
      lastText: lm?['text'] as String?,
      lastSenderId: lm?['senderId'] as String?,
      lastAt: lm?['createdAt'] != null
          ? DateTime.tryParse(lm!['createdAt'] as String)?.toLocal()
          : null,
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

class TypingEvent {
  final String conversationId;
  final String userId;
  final bool typing;
  const TypingEvent(this.conversationId, this.userId, this.typing);
}

class ReadEvent {
  final String conversationId;
  final String userId;
  const ReadEvent(this.conversationId, this.userId);
}
