import 'package:dio/dio.dart';
import 'package:goodloop/core/network/api_exception.dart';

import 'friend_models.dart';

/// Cienka warstwa nad `/api/v1/friends/*`. Każda metoda mapuje błędy Dio na
/// [ApiException] z komunikatem po polsku.
class FriendsRepository {
  FriendsRepository(this._dio);

  final Dio _dio;

  Future<List<UserSearchResult>> search(String query) => _run(() async {
        final res = await _dio.get<List<dynamic>>(
          '/friends/search',
          queryParameters: {'q': query},
        );
        return (res.data ?? [])
            .map((e) => UserSearchResult.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<FriendSummary>> listFriends() => _run(() async {
        final res = await _dio.get<List<dynamic>>('/friends');
        return (res.data ?? [])
            .map((e) => FriendSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<FriendRequestSummary>> listRequests() => _run(() async {
        final res = await _dio.get<List<dynamic>>('/friends/requests');
        return (res.data ?? [])
            .map((e) => FriendRequestSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<PublicUser>> listBlocked() => _run(() async {
        final res = await _dio.get<List<dynamic>>('/friends/blocks');
        return (res.data ?? [])
            .map((e) => PublicUser.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<void> sendRequest(String userId) =>
      _run(() => _dio.post('/friends/requests', data: {'userId': userId}));

  Future<void> acceptRequest(String requestId) =>
      _run(() => _dio.post('/friends/requests/$requestId/accept'));

  Future<void> rejectRequest(String requestId) =>
      _run(() => _dio.post('/friends/requests/$requestId/reject'));

  Future<void> cancelRequest(String requestId) =>
      _run(() => _dio.delete('/friends/requests/$requestId'));

  Future<void> removeFriend(String userId) =>
      _run(() => _dio.delete('/friends/$userId'));

  Future<void> block(String userId) =>
      _run(() => _dio.post('/friends/blocks', data: {'userId': userId}));

  Future<void> unblock(String userId) =>
      _run(() => _dio.delete('/friends/blocks/$userId'));

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw toApiException(e);
    }
  }
}
