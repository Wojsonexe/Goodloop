import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:goodloop/shared/user_avatar.dart';

import '../data/chat_models.dart';
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
  ChatMessage? _replyingTo;
  ChatMessage? _editing;

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
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(messagesProvider(widget.conversationId).notifier).loadMore();
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

  void _cancelCompose() {
    setState(() {
      _replyingTo = null;
      _editing = null;
      _input.clear();
    });
  }

  void _openMenu(ChatMessage m, bool isMine) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Odpowiedz'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _editing = null;
                  _replyingTo = m;
                });
              },
            ),
            if (isMine) ...[
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edytuj'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingTo = null;
                    _editing = m;
                    _input.text = m.text;
                    _input.selection = TextSelection.fromPosition(
                        TextPosition(offset: _input.text.length));
                  });
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: const Text('Usuń'),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      content: const Text('Usunąć tę wiadomość?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Anuluj')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Usuń')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await ref
                        .read(messagesProvider(widget.conversationId).notifier)
                        .deleteMessage(m.id);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Nie usunięto: $e')));
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final notifier = ref.read(messagesProvider(widget.conversationId).notifier);
    try {
      if (_editing != null) {
        final id = _editing!.id;
        setState(() => _editing = null);
        _input.clear();
        await notifier.editMessage(id, text);
      } else {
        final replyId = _replyingTo?.id;
        setState(() => _replyingTo = null);
        _input.clear();
        await notifier.send(text, replyToId: replyId);
        _toBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nie wysłano: $e')));
      }
    }
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
                      onLongPress: () => _openMenu(m, m.senderId == me),
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
          if (_replyingTo != null || _editing != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(_editing != null ? Icons.edit : Icons.reply, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _editing != null
                          ? 'Edytujesz wiadomość'
                          : 'Odpowiedź: ${_replyingTo!.isDeleted ? 'usunięta wiadomość' : _replyingTo!.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _cancelCompose,
                  ),
                ],
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
                IconButton(
                  onPressed: _send,
                  icon: Icon(_editing != null ? Icons.check : Icons.send),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
