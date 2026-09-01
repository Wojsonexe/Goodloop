import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_models.dart';
import 'chat_providers.dart';

final conversationsProvider = StateNotifierProvider<ConversationsNotifier,
    AsyncValue<List<Conversation>>>((ref) => ConversationsNotifier(ref));

final conversationByIdProvider =
    Provider.family<Conversation?, String>((ref, id) {
  final list = ref.watch(conversationsProvider).value ?? const [];
  for (final c in list) {
    if (c.id == id) return c;
  }
  return null;
});

final totalUnreadProvider = Provider<int>((ref) {
  final list = ref.watch(conversationsProvider).value ?? const [];
  return list.fold(0, (sum, c) => sum + c.unread);
});

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<Conversation>>> {
  ConversationsNotifier(this.ref) : super(const AsyncValue.loading()) {
    final socket = ref.read(chatSocketProvider);
    _connSub = socket.connectionState.listen((c) {
      if (c) load();
    });
    _updSub = socket.onConversationUpdated.listen(_upsert);
    if (socket.isConnected) load();
  }
  final Ref ref;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Conversation>? _updSub;

  Future<void> load() async {
    try {
      final list = await ref.read(chatSocketProvider).listConversations();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _upsert(Conversation c) {
    final cur = state.valueOrNull ?? const <Conversation>[];
    final next = [c, ...cur.where((x) => x.id != c.id)]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = AsyncValue.data(next);
  }

  /// Otwiera (lub pobiera) rozmowę 1:1 ze znajomym, zwraca jej id.
  Future<String> openWith(String friendUid) async {
    final conv = await ref.read(chatSocketProvider).openConversation(friendUid);
    _upsert(conv);
    return conv.id;
  }

  /// Lokalne zerowanie licznika po wejściu w rozmowę (serwer i tak przyśle update).
  void markReadLocal(String conversationId) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncValue.data([
      for (final c in cur) c.id == conversationId ? _copyUnread(c, 0) : c,
    ]);
  }

  Conversation _copyUnread(Conversation c, int unread) => Conversation(
        id: c.id,
        members: c.members,
        memberInfo: c.memberInfo,
        lastText: c.lastText,
        lastSenderId: c.lastSenderId,
        lastAt: c.lastAt,
        unread: unread,
        updatedAt: c.updatedAt,
      );

  @override
  void dispose() {
    _connSub?.cancel();
    _updSub?.cancel();
    super.dispose();
  }
}
