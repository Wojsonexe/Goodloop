import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';
import 'package:goodloop/core/utils/logger.dart';

final achievementCheckerProvider = Provider<AchievementChecker>((ref) {
  return AchievementChecker(ref);
});

class AchievementChecker {
  AchievementChecker(this.ref);

  final Ref ref;

  /// Sprawdza warunki osiągnięć po ukończeniu zadania i zapisuje nowo
  /// odblokowane do `users/{uid}.achievements`. Dedup po [alreadyUnlocked]
  /// (lista, którą wołający i tak ma w [user.achievements]) — zero dodatkowych
  /// odczytów. Zwraca id świeżo odblokowanych (puste, gdy nic nowego).
  Future<List<String>> checkAfterTaskCompletion({
    required String userId,
    required Set<String> alreadyUnlocked,
    required int completedTasks,
    required int streakDays,
    required DateTime completionTime,
  }) async {
    final candidates = <String>{
      if (completedTasks >= 1) 'first_task',
      if (completedTasks >= 10) 'ten_tasks',
      if (completedTasks >= 50) 'fifty_tasks',
      if (completedTasks >= 100) 'hundred_tasks',
      if (streakDays >= 7) 'week_streak',
      if (completionTime.hour < 8) 'early_bird',
      if (completionTime.hour >= 22) 'night_owl',
    };

    final fresh = candidates.difference(alreadyUnlocked).toList();
    if (fresh.isEmpty) return const [];

    try {
      final repo = ref.read(userRepositoryProvider);
      for (final id in fresh) {
        await repo.addAchievement(userId, id);
      }
      return fresh;
    } catch (e) {
      logger.e('❌ Error saving achievements: $e');
      return const [];
    }
  }
}
