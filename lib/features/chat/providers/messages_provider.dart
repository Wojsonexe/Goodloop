import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_models.dart';
import 'chat_providers.dart';
import 'conversations_provider.dart';

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    AsyncValue<List<ChatMessage>>, String>(
  (ref, conversationId) => MessagesNotifier(ref, conversationId),
);

class MessagesNotifier extends StateNotifier<AsyncValue<List<ChatMessage>>> {
  MessagesNotifier(this.ref, this.conversationId)
      : super(const AsyncValue.loading()) {
    final socket = ref.read(chatSocketProvider);
    _msgSub = socket.onMessageNew.listen((m) {
      if (m.conversationId == conversationId) _merge(m);
    });
    _readSub = socket.onMessageRead.listen((e) {
      if (e.conversationId != conversationId) return;
      final cur = state.value ?? const <ChatMessage>[];
      state = AsyncValue.data([
        for (final m in cur) m.senderId == _me ? m.copyWith(seen: true) : m,
      ]);
    });
    load();
  }
  final Ref ref;
  final String conversationId;
  final _uuid = const Uuid();
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<ReadEvent>? _readSub;
  Timer? _typingStop;

  String get _me => ref.read(authStateProvider).value?.uid ?? '';

  Future<void> load() async {
    try {
      final msgs =
          await ref.read(chatSocketProvider).listMessages(conversationId);
      state = AsyncValue.data(msgs);
      _markRead();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
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
    state = AsyncValue.data([...(state.value ?? const []), optimistic]);
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
    final cur = state.value ?? const <ChatMessage>[];
    state = AsyncValue.data(cur.where((m) => m.id != failed.id).toList());
    send(failed.text);
  }

  void onInputChanged() {
    ref.read(chatSocketProvider).setTyping(conversationId, true);
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 3),
        () => ref.read(chatSocketProvider).setTyping(conversationId, false));
  }

  void _merge(ChatMessage m) {
    final cur = state.value ?? const <ChatMessage>[];
    if (cur.any((x) => x.id == m.id)) return;
    if (m.senderId == _me &&
        m.clientId != null &&
        cur.any((x) => x.clientId == m.clientId)) {
      _replace(m.clientId!, m);
      return;
    }
    state = AsyncValue.data([...cur, m]);
    if (m.senderId != _me) _markRead();
  }

  void _replace(String clientId, ChatMessage msg) {
    final cur = state.value ?? const <ChatMessage>[];
    state = AsyncValue.data(
        [for (final m in cur) m.clientId == clientId ? msg : m]);
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
