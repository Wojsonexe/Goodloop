import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:goodloop/shared/user_avatar.dart';

import '../providers/chat_providers.dart';
import '../providers/conversations_provider.dart';
import '../providers/messages_provider.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // reverse:true → starsze wiadomości są w stronę maxScrollExtent.
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(messagesProvider(widget.conversationId).notifier).loadMore();
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    try {
      await ref
          .read(messagesProvider(widget.conversationId).notifier)
          .send(text);
      _toBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nie wysłano: $e')));
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authStateProvider).value?.uid ?? '';
    final id = widget.conversationId;
    final msgsAsync = ref.watch(messagesProvider(id));
    final conv = ref.watch(conversationByIdProvider(id));
    final other = conv?.other(me);
    final typing = ref.watch(typingProvider(id));

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          UserAvatar(photoUrl: other?.photoUrl, radius: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(other?.displayName ?? 'Rozmowa',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: msgsAsync.when(
              data: (s) {
                final msgs = s.items;
                final showSpinner = s.hasMore || s.loadingMore;
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: msgs.length + (showSpinner ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= msgs.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final m = msgs[msgs.length - 1 - i];
                    return MessageBubble(
                      message: m,
                      isMine: m.senderId == me,
                      onRetry: () =>
                          ref.read(messagesProvider(id).notifier).retry(m),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Błąd: $e')),
            ),
          ),
          if (typing)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 16, bottom: 4),
                child: Text('pisze…',
                    style: TextStyle(fontStyle: FontStyle.italic)),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => ref
                        .read(messagesProvider(id).notifier)
                        .onInputChanged(),
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Wiadomość…',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                IconButton(onPressed: _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
