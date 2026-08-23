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
      title: data['text'] ?? data['title'] ?? 'Zadanie dnia',
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

  Future<void> completeGlobalTask(
      String userId, String taskId, int points) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);

      await userRef.update({
        'completedTaskIds': FieldValue.arrayUnion([taskId]),
        'completedTasks': FieldValue.increment(1),
        'totalPoints': FieldValue.increment(points),
        'lastTaskCompletedDate': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
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
