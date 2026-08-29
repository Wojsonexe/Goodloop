import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:goodloop/logger.dart';
import '../models/task_model.dart';

class TaskRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<TaskModel>> getGlobalDailyTasks() {
    return _firestore.collection('global_tasks').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => parseGlobalTask(doc.id, doc.data()))
          .whereType<TaskModel>()
          .toList();
    });
  }

  /// Pure mapping of a `global_tasks` document into a [TaskModel].
  ///
  /// Kept free of any Firestore dependency so it can be unit tested with
  /// plain maps. Returns null for tasks marked `isActive: false` — those
  /// should not reach the user.
  static TaskModel? parseGlobalTask(String id, Map<String, dynamic> data) {
    final isActiveRaw = data['isActive'];
    final isActive = isActiveRaw is bool ? isActiveRaw : true;
    if (!isActive) return null;

    final pointsRaw = data['points'];
    final points = pointsRaw is num ? pointsRaw.toInt() : 10;

    final difficultyRaw = data['difficulty'];
    final difficulty = difficultyRaw is String ? difficultyRaw : null;

    final categoryRaw = data['category'];
    final categoryName = categoryRaw is String ? categoryRaw : 'other';

    return TaskModel(
      id: id,
      userId: 'global',
      title: data['title'] as String? ?? 'Zadanie dnia',
      description: data['description'] ?? 'Wykonaj dzisiejsze wyzwanie!',
      category: TaskCategory.values.firstWhere(
        (e) => e.name == categoryName,
        orElse: () => TaskCategory.other,
      ),
      difficulty: difficulty,
      points: points,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isCompleted: false,
    );
  }

  /// Nowa wartość serii po ukończeniu zadania [now], przy poprzednim ukończeniu
  /// [lastCompletedAt] i obecnej serii [current]:
  /// - brak wcześniejszego ukończenia → 1
  /// - kolejne zadanie tego samego dnia → bez zmian
  /// - następny dzień → +1
  /// - dłuższa przerwa → reset do 1
  ///
  /// Firestore-free, żeby dało się testować jednostkowo.
  static int nextStreak(int current, DateTime? lastCompletedAt, DateTime now) {
    if (lastCompletedAt == null) return 1;
    final last =
        DateTime(lastCompletedAt.year, lastCompletedAt.month, lastCompletedAt.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(last).inDays;
    if (days <= 0) return current < 1 ? 1 : current;
    if (days == 1) return current + 1;
    return 1;
  }

  /// Zalicza użytkownikowi globalne zadanie dnia. Transakcja, bo `streakDays`
  /// zależy od aktualnego stanu, a `level` musi się zgadzać z `totalPoints`
  /// (walidacja regułą — patrz docs/firebase-schema.md).
  Future<void> completeGlobalTask(
      String userId, String taskId, int points) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final data = snap.data() ?? <String, dynamic>{};

        final completedIds =
            (data['completedTaskIds'] as List?)?.cast<String>() ?? const [];
        if (completedIds.contains(taskId)) return; // już zaliczone — no-op

        final currentStreak = (data['streakDays'] as num?)?.toInt() ?? 0;
        final lastDate =
            (data['lastTaskCompletedDate'] as Timestamp?)?.toDate();
        final newStreak = nextStreak(currentStreak, lastDate, DateTime.now());

        final newPoints =
            ((data['totalPoints'] as num?)?.toInt() ?? 0) + points;

        tx.update(userRef, {
          'completedTaskIds': FieldValue.arrayUnion([taskId]),
          'completedTasks': FieldValue.increment(1),
          'totalPoints': FieldValue.increment(points),
          'level': newPoints ~/ 100 + 1,
          'streakDays': newStreak,
          'lastCompletedTaskId': taskId,
          'lastTaskCompletedDate': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        });
      });

      logger.i('✅ Global task completed: $taskId for user $userId');
    } catch (e) {
      logger.e('❌ Error completing global task: $e');
      rethrow;
    }
  }

  CollectionReference _tasksCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('tasks');
  }

  Future<String> createTask(TaskModel task) async {
    try {
      final docRef = await _tasksCollection(task.userId).add(task.toMap());
      return docRef.id;
    } catch (e) {
      logger.e('❌ Error creating task: $e');
      rethrow;
    }
  }
}
