enum AchievementType {
  firstTask,
  weekStreak,
  tenTasks,
  fiftyTasks,
  hundredTasks,
  socialButterfly,
  helper,
  legend,
  earlyBird,
  nightOwl,
}

class AchievementModel {
  final String id;
  final AchievementType type;
  final String title;
  final String description;
  final String icon;
  final int points;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const AchievementModel({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    this.points = 50,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  AchievementModel copyWith({bool? isUnlocked, DateTime? unlockedAt}) {
    return AchievementModel(
      id: id,
      type: type,
      title: title,
      description: description,
      icon: icon,
      points: points,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
    );
  }

  /// Statyczna definicja osiągnięcia po id. Zwraca null dla nieznanego id.
  static AchievementModel? byId(String id) {
    for (final a in getAllAchievements()) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Pełny katalog osiągnięć — statyczne dane aplikacji. Stan odblokowania
  /// trzymany jest osobno w `users/{uid}.achievements` i nakładany przez
  /// [copyWith] przy wyświetlaniu.
  static List<AchievementModel> getAllAchievements() {
    return const [
      AchievementModel(
        id: 'first_task',
        type: AchievementType.firstTask,
        title: 'Pierwsze kroki',
        description: 'Ukończ swoje pierwsze zadanie',
        icon: '🎯',
        points: 10,
      ),
      AchievementModel(
        id: 'week_streak',
        type: AchievementType.weekStreak,
        title: 'Tygodniowy wojownik',
        description: 'Wykonuj zadania przez 7 dni z rzędu',
        icon: '🔥',
        points: 50,
      ),
      AchievementModel(
        id: 'ten_tasks',
        type: AchievementType.tenTasks,
        title: 'Pomocnik',
        description: 'Ukończ 10 zadań',
        icon: '⭐',
        points: 30,
      ),
      AchievementModel(
        id: 'fifty_tasks',
        type: AchievementType.fiftyTasks,
        title: 'Mistrz Dobroci',
        description: 'Ukończ 50 zadań',
        icon: '🏆',
        points: 100,
      ),
      AchievementModel(
        id: 'hundred_tasks',
        type: AchievementType.hundredTasks,
        title: 'Legenda',
        description: 'Ukończ 100 zadań',
        icon: '👑',
        points: 200,
      ),
      AchievementModel(
        id: 'early_bird',
        type: AchievementType.earlyBird,
        title: 'Ranny ptaszek',
        description: 'Ukończ zadanie przed 8:00',
        icon: '🌅',
        points: 25,
      ),
      AchievementModel(
        id: 'night_owl',
        type: AchievementType.nightOwl,
        title: 'Nocny marek',
        description: 'Ukończ zadanie po 22:00',
        icon: '🦉',
        points: 25,
      ),
    ];
  }
}
