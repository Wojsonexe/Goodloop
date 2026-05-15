import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:goodloop/logger.dart';
import '../models/task_model.dart';

class TaskRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<TaskModel>> getGlobalDailyTasks() {
    return _firestore.collection('dailyTasks').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();

        return TaskModel(
          id: doc.id,
          userId: 'global',
          title: data['text'] ?? data['title'] ?? 'Zadanie dnia',
          description: data['description'] ?? 'Wykonaj dzisiejsze wyzwanie!',
          category: TaskCategory.values.firstWhere(
            (e) => e.name == (data['category'] ?? 'other'),
            orElse: () => TaskCategory.other,
          ),
          points: ((data['difficulty'] ?? 1) as num).toInt() * 10,
          createdAt: DateTime.now(),
          isCompleted: false,
        );
      }).toList();
    });
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
