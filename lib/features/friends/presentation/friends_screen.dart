import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/core/constants/app_colors.dart';
import 'package:goodloop/core/network/api_exception.dart';
import 'package:goodloop/features/chat/providers/conversations_provider.dart';

import '../data/friend_models.dart';
import '../providers/friends_providers.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Akcje ─────────────────────────────────────────────────────────────────

  Future<void> _act(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (mounted && ok != null) _snack(ok);
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(
      String title, String message, String confirmLabel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(incomingRequestCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Znajomi'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Znajomi'),
            Tab(
              child: _TabLabel(
                text: 'Zaproszenia',
                badge: incoming > 0 ? incoming : null,
              ),
            ),
            const Tab(text: 'Szukaj'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FriendsTab(act: _act, confirm: _confirm),
          _RequestsTab(act: _act),
          _SearchTab(act: _act, controller: _searchController),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, this.badge});

  final String text;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    if (badge == null) return Text(text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: const BoxDecoration(
            color: AppColors.error,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: Text(
            '$badge',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ── Zakładka: Znajomi ───────────────────────────────────────────────────────

class _FriendsTab extends ConsumerWidget {
  const _FriendsTab({required this.act, required this.confirm});

  final Future<void> Function(Future<void> Function(), {String? ok}) act;
  final Future<bool> Function(String, String, String) confirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsListProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(friendsListProvider.future),
      child: friends.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrorView(
          message: e is ApiException ? e.message : 'Nie udało się wczytać.',
          onRetry: () => ref.invalidate(friendsListProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _Empty(
              icon: Icons.group_outlined,
              text:
                  'Nie masz jeszcze znajomych.\nZnajdź kogoś w zakładce „Szukaj".',
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final f = list[i];
              return ListTile(
                leading: _Avatar(user: f.user),
                title: Text(f.user.displayName),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    final actions = ref.read(friendActionsProvider);
                    if (value == 'message') {
                      try {
                        final convId = await ref
                            .read(conversationsProvider.notifier)
                            .openWith(f.user.id);

                        if (context.mounted) {
                          context.push('/chat/$convId');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    }
                    if (value == 'remove') {
                      if (await confirm(
                        'Usuń znajomego',
                        'Usunąć ${f.user.displayName} ze znajomych?',
                        'Usuń',
                      )) {
                        await act(() => actions.removeFriend(f.user.id),
                            ok: 'Usunięto ze znajomych.');
                      }
                    } else if (value == 'block') {
                      if (await confirm(
                        'Zablokuj',
                        'Zablokować ${f.user.displayName}? Zniknie ze znajomych '
                            'i nie będzie mógł wysłać Ci zaproszenia.',
                        'Zablokuj',
                      )) {
                        await act(() => actions.block(f.user.id),
                            ok: 'Zablokowano.');
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'message', child: Text('Napisz')),
                    PopupMenuItem(
                        value: 'remove', child: Text('Usuń znajomego')),
                    PopupMenuItem(value: 'block', child: Text('Zablokuj')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Zakładka: Zaproszenia ───────────────────────────────────────────────────

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.act});

  final Future<void> Function(Future<void> Function(), {String? ok}) act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(friendRequestsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(friendRequestsProvider.future),
      child: requests.when(
        loading: () => const _Loading(),
        error: (e, _) => _ErrorView(
          message: e is ApiException ? e.message : 'Nie udało się wczytać.',
          onRetry: () => ref.invalidate(friendRequestsProvider),
        ),
        data: (list) {
          final incoming = list
              .where((r) => r.direction == RequestDirection.incoming)
              .toList();
          final outgoing = list
              .where((r) => r.direction == RequestDirection.outgoing)
              .toList();

          if (incoming.isEmpty && outgoing.isEmpty) {
            return const _Empty(
              icon: Icons.mail_outline,
              text: 'Brak oczekujących zaproszeń.',
            );
          }

          final actions = ref.read(friendActionsProvider);
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (incoming.isNotEmpty) ...[
                const _SectionHeader('Do Ciebie'),
                for (final r in incoming)
                  ListTile(
                    leading: _Avatar(user: r.user),
                    title: Text(r.user.displayName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle,
                              color: AppColors.success),
                          tooltip: 'Przyjmij',
                          onPressed: () => act(() => actions.accept(r.id),
                              ok: 'Dodano do znajomych.'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined,
                              color: AppColors.error),
                          tooltip: 'Odrzuć',
                          onPressed: () => act(() => actions.reject(r.id)),
                        ),
                      ],
                    ),
                  ),
              ],
              if (outgoing.isNotEmpty) ...[
                const _SectionHeader('Wysłane'),
                for (final r in outgoing)
                  ListTile(
                    leading: _Avatar(user: r.user),
                    title: Text(r.user.displayName),
                    subtitle: const Text('Oczekuje'),
                    trailing: TextButton(
                      onPressed: () => act(() => actions.cancel(r.id)),
                      child: const Text('Anuluj'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ── Zakładka: Szukaj ────────────────────────────────────────────────────────

class _SearchTab extends ConsumerWidget {
  const _SearchTab({required this.act, required this.controller});

  final Future<void> Function(Future<void> Function(), {String? ok}) act;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(friendSearchQueryProvider);
    final results = ref.watch(friendSearchResultsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: controller,
            onChanged: (v) =>
                ref.read(friendSearchQueryProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Nazwa lub adres e-mail',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        ref.read(friendSearchQueryProvider.notifier).state = '';
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: switch ((query.trim().length, results)) {
            (< 2, _) => const _Empty(
                icon: Icons.search,
                text: 'Wpisz co najmniej 2 znaki.',
              ),
            (_, AsyncData(:final value)) when value.isEmpty => const _Empty(
                icon: Icons.person_off_outlined,
                text: 'Nikogo nie znaleziono.',
              ),
            (_, AsyncData(:final value)) => ListView.separated(
                itemCount: value.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _SearchResultTile(
                  result: value[i],
                  act: act,
                ),
              ),
            (_, AsyncError(:final error)) => _ErrorView(
                message: error is ApiException
                    ? error.message
                    : 'Nie udało się wyszukać.',
                onRetry: () => ref.invalidate(friendSearchResultsProvider),
              ),
            _ => const _Loading(),
          },
        ),
      ],
    );
  }
}

class _SearchResultTile extends ConsumerWidget {
  const _SearchResultTile({required this.result, required this.act});

  final UserSearchResult result;
  final Future<void> Function(Future<void> Function(), {String? ok}) act;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(friendActionsProvider);
    final user = result.user;

    final Widget trailing = switch (result.relation) {
      FriendRelation.friends => const Chip(
          label: Text('Znajomy'),
          avatar: Icon(Icons.check, size: 16),
        ),
      FriendRelation.outgoing => const TextButton(
          onPressed: null,
          child: Text('Wysłano'),
        ),
      FriendRelation.incoming => ElevatedButton(
          onPressed: () => act(
            () => _acceptByUser(ref, user.id),
            ok: 'Dodano do znajomych.',
          ),
          child: const Text('Przyjmij'),
        ),
      FriendRelation.blocked => TextButton(
          onPressed: () =>
              act(() => actions.unblock(user.id), ok: 'Odblokowano.'),
          child: const Text('Odblokuj'),
        ),
      FriendRelation.none => FilledButton.tonal(
          onPressed: () => act(() => actions.sendRequest(user.id),
              ok: 'Wysłano zaproszenie.'),
          child: const Text('Dodaj'),
        ),
    };

    return ListTile(
      leading: _Avatar(user: user),
      title: Text(user.displayName),
      trailing: trailing,
    );
  }

  /// Przyjęcie z poziomu wyszukiwarki — nie mamy id zaproszenia, więc
  /// wysłanie własnego zaproszenia po stronie serwera auto-akceptuje istniejące.
  Future<void> _acceptByUser(WidgetRef ref, String userId) {
    return ref.read(friendActionsProvider).sendRequest(userId);
  }
}

// ── Wspólne kawałki ─────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final PublicUser user;

  @override
  Widget build(BuildContext context) {
    final photo = user.photoUrl;
    return CircleAvatar(
      backgroundImage:
          photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
      child: photo == null || photo.isEmpty
          ? Text(
              user.displayName.isNotEmpty
                  ? user.displayName.characters.first.toUpperCase()
                  : '?',
            )
          : null,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off, size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
              onPressed: onRetry, child: const Text('Spróbuj ponownie')),
        ),
      ],
    );
  }
}
