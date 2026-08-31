import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_providers.dart';
import '../providers/conversations_provider.dart';
import 'widgets/conversation_tile.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatConnectionProvider); // trzyma połączenie
    final async = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Wiadomości')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(conversationsProvider.notifier).load(),
        child: async.when(
          data: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Brak rozmów. Napisz do znajomego.')),
                ])
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      ConversationTile(conversation: list[i]),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Błąd: $e')),
        ),
      ),
    );
  }
}
