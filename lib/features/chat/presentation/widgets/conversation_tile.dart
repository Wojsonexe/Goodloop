import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:goodloop/shared/user_avatar.dart';

import '../../data/chat_models.dart';

class ConversationTile extends ConsumerWidget {
  final Conversation conversation;
  const ConversationTile({super.key, required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authStateProvider).value?.uid ?? '';
    final other = conversation.other(me);
    final unread = conversation.unread;

    return ListTile(
      leading: UserAvatar(photoUrl: other?.photoUrl, radius: 24),
      title: Text(other?.displayName ?? 'Użytkownik',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        conversation.lastText ?? 'Rozpocznij rozmowę',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.normal),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastAt != null)
            Text(_short(conversation.lastAt!),
                style: Theme.of(context).textTheme.bodySmall),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: Colors.redAccent, shape: BoxShape.circle),
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
        ],
      ),
      onTap: () => context.push('/chat/${conversation.id}'),
    );
  }

  String _short(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}.${d.month}';
  }
}
