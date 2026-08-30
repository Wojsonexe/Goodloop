import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/core/network/dio_client.dart';

import '../data/friend_models.dart';
import '../data/friends_repository.dart';

final friendsRepositoryProvider = Provider<FriendsRepository>(
  (ref) => FriendsRepository(ref.watch(dioProvider)),
);

final friendsListProvider =
    FutureProvider.autoDispose<List<FriendSummary>>((ref) {
  return ref.watch(friendsRepositoryProvider).listFriends();
});

final friendRequestsProvider =
    FutureProvider.autoDispose<List<FriendRequestSummary>>((ref) {
  return ref.watch(friendsRepositoryProvider).listRequests();
});

final blockedUsersProvider =
    FutureProvider.autoDispose<List<PublicUser>>((ref) {
  return ref.watch(friendsRepositoryProvider).listBlocked();
});

/// Liczba przychodzących zaproszeń — do plakietki w nawigacji.
final incomingRequestCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(friendRequestsProvider).maybeWhen(
        data: (requests) => requests
            .where((r) => r.direction == RequestDirection.incoming)
            .length,
        orElse: () => 0,
      );
});

/// Aktualny tekst w polu wyszukiwania.
final friendSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Wyniki wyszukiwania z prostym debounce (350 ms). Puste dla < 2 znaków.
final friendSearchResultsProvider =
    FutureProvider.autoDispose<List<UserSearchResult>>((ref) async {
  final query = ref.watch(friendSearchQueryProvider).trim();
  if (query.length < 2) return const [];

  final repo = ref.watch(friendsRepositoryProvider);
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return repo.search(query);
});

final friendActionsProvider =
    Provider<FriendActions>((ref) => FriendActions(ref));

/// Mutacje + odświeżenie zależnych list. Rzuca [ApiException] w górę.
class FriendActions {
  FriendActions(this._ref);

  final Ref _ref;

  FriendsRepository get _repo => _ref.read(friendsRepositoryProvider);

  Future<void> sendRequest(String userId) async {
    await _repo.sendRequest(userId);
    _refresh();
  }

  Future<void> accept(String requestId) async {
    await _repo.acceptRequest(requestId);
    _refresh();
  }

  Future<void> reject(String requestId) async {
    await _repo.rejectRequest(requestId);
    _refresh();
  }

  Future<void> cancel(String requestId) async {
    await _repo.cancelRequest(requestId);
    _refresh();
  }

  Future<void> removeFriend(String userId) async {
    await _repo.removeFriend(userId);
    _refresh();
  }

  Future<void> block(String userId) async {
    await _repo.block(userId);
    _refresh();
  }

  Future<void> unblock(String userId) async {
    await _repo.unblock(userId);
    _refresh();
  }

  void _refresh() {
    _ref.invalidate(friendsListProvider);
    _ref.invalidate(friendRequestsProvider);
    _ref.invalidate(blockedUsersProvider);
    _ref.invalidate(friendSearchResultsProvider);
  }
}
