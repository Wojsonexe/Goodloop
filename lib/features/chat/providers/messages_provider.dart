import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_models.dart';
import 'chat_providers.dart';
import 'conversations_provider.dart';

/// Stan ekranu rozmowy: lista wiadomości + flagi paginacji wstecz.
class MessagesState {
  final List<ChatMessage> items;
  final bool hasMore;
  final bool loadingMore;
  const MessagesState(this.items,
      {this.hasMore = false, this.loadingMore = false});

  MessagesState copyWith({
    List<ChatMessage>? items,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      MessagesState(
        items ?? this.items,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    AsyncValue<MessagesState>, String>(
  (ref, conversationId) => MessagesNotifier(ref, conversationId),
);

class MessagesNotifier extends StateNotifier<AsyncValue<MessagesState>> {
  MessagesNotifier(this.ref, this.conversationId)
      : super(const AsyncValue.loading()) {
    final socket = ref.read(chatSocketProvider);
    _msgSub = socket.onMessageNew.listen((m) {
      if (m.conversationId == conversationId) _merge(m);
    });
    _readSub = socket.onMessageRead.listen((e) {
      if (e.conversationId != conversationId) return;
      _patch((cur) => [
            for (final m in cur) m.senderId == _me ? m.copyWith(seen: true) : m,
          ]);
    });
    load();
  }
  final Ref ref;
  final String conversationId;
  final _uuid = const Uuid();
  static const _pageSize = 30;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<ReadEvent>? _readSub;
  Timer? _typingStop;

  String get _me => ref.read(authStateProvider).value?.uid ?? '';

  List<ChatMessage> get _items => state.valueOrNull?.items ?? const [];

  void _patch(List<ChatMessage> Function(List<ChatMessage>) fn) {
    final cur = state.valueOrNull ?? const MessagesState([]);
    state = AsyncValue.data(cur.copyWith(items: fn(cur.items)));
  }

  Future<void> load() async {
    try {
      final msgs = await ref
          .read(chatSocketProvider)
          .listMessages(conversationId, limit: _pageSize);
      state = AsyncValue.data(
          MessagesState(msgs, hasMore: msgs.length >= _pageSize));
      _markRead();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Doładowanie starszych wiadomości (scroll w górę).
  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || cur.loadingMore || !cur.hasMore || cur.items.isEmpty) {
      return;
    }
    state = AsyncValue.data(cur.copyWith(loadingMore: true));
    try {
      final older = await ref.read(chatSocketProvider).listMessages(
            conversationId,
            limit: _pageSize,
            before: cur.items.first.createdAt,
          );
      final known = cur.items.map((m) => m.id).toSet();
      state = AsyncValue.data(MessagesState(
        [...older.where((m) => !known.contains(m.id)), ...cur.items],
        hasMore: older.length >= _pageSize,
        loadingMore: false,
      ));
    } catch (_) {
      state = AsyncValue.data(cur.copyWith(loadingMore: false));
    }
  }

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final clientId = _uuid.v4();
    final optimistic = ChatMessage(
      id: clientId,
      conversationId: conversationId,
      senderId: _me,
      text: trimmed,
      createdAt: DateTime.now(),
      clientId: clientId,
      pending: true,
    );
    _patch((cur) => [...cur, optimistic]);
    try {
      final saved = await ref
          .read(chatSocketProvider)
          .sendMessage(conversationId, trimmed, clientId);
      _replace(clientId, saved);
    } catch (e) {
      _replace(clientId, optimistic.copyWith(pending: false, failed: true));
      rethrow;
    }
  }

  void retry(ChatMessage failed) {
    _patch((cur) => cur.where((m) => m.id != failed.id).toList());
    send(failed.text);
  }

  void onInputChanged() {
    ref.read(chatSocketProvider).setTyping(conversationId, true);
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 3),
        () => ref.read(chatSocketProvider).setTyping(conversationId, false));
  }

  void _merge(ChatMessage m) {
    final cur = _items;
    if (cur.any((x) => x.id == m.id)) return;
    if (m.senderId == _me &&
        m.clientId != null &&
        cur.any((x) => x.clientId == m.clientId)) {
      _replace(m.clientId!, m);
      return;
    }
    _patch((c) => [...c, m]);
    if (m.senderId != _me) _markRead();
  }

  void _replace(String clientId, ChatMessage msg) {
    _patch((cur) => [for (final m in cur) m.clientId == clientId ? msg : m]);
  }

  void _markRead() {
    ref.read(chatSocketProvider).markRead(conversationId).catchError((_) {});
    ref.read(conversationsProvider.notifier).markReadLocal(conversationId);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _readSub?.cancel();
    _typingStop?.cancel();
    super.dispose();
  }
}
