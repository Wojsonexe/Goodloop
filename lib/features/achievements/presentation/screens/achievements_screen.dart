import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/data/models/achievement_model.dart';
import 'package:goodloop/domain/providers/auth_provider.dart';
import 'widgets/achievement_card.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Osiągnięcia'),
        centerTitle: true,
        elevation: 0,
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Nie znaleziono użytkownika'));
          }

          final unlocked = user.achievements.toSet();
          final items = AchievementModel.getAllAchievements()
              .map((a) => a.copyWith(isUnlocked: unlocked.contains(a.id)))
              .toList()
            ..sort((a, b) {
              if (a.isUnlocked != b.isUnlocked) return a.isUnlocked ? -1 : 1;
              return 0;
            });
          final unlockedCount = items.where((a) => a.isUnlocked).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Odblokowano $unlockedCount z ${items.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AchievementCard(achievement: a),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Błąd: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}
