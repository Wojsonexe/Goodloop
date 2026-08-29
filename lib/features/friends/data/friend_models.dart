/// Relacja zalogowanego użytkownika do innej osoby (z wyników wyszukiwania).
enum FriendRelation { none, friends, outgoing, incoming, blocked }

FriendRelation friendRelationFrom(String? value) => switch (value) {
      'friends' => FriendRelation.friends,
      'outgoing' => FriendRelation.outgoing,
      'incoming' => FriendRelation.incoming,
      'blocked' => FriendRelation.blocked,
      _ => FriendRelation.none,
    };

enum RequestDirection { incoming, outgoing }

class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    this.photoUrl,
  });

  final String id;
  final String displayName;
  final String? photoUrl;

  factory PublicUser.fromJson(Map<String, dynamic> json) => PublicUser(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        photoUrl: json['photoUrl'] as String?,
      );
}

class FriendSummary {
  const FriendSummary({required this.user, required this.since});

  final PublicUser user;
  final DateTime since;

  factory FriendSummary.fromJson(Map<String, dynamic> json) => FriendSummary(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        since: DateTime.tryParse(json['since'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class FriendRequestSummary {
  const FriendRequestSummary({
    required this.id,
    required this.user,
    required this.direction,
    required this.createdAt,
  });

  final String id;
  final PublicUser user;
  final RequestDirection direction;
  final DateTime createdAt;

  factory FriendRequestSummary.fromJson(Map<String, dynamic> json) =>
      FriendRequestSummary(
        id: json['id'] as String,
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        direction: json['direction'] == 'incoming'
            ? RequestDirection.incoming
            : RequestDirection.outgoing,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

class UserSearchResult {
  const UserSearchResult({required this.user, required this.relation});

  final PublicUser user;
  final FriendRelation relation;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        user: PublicUser.fromJson(json['user'] as Map<String, dynamic>),
        relation: friendRelationFrom(json['relation'] as String?),
      );
}
