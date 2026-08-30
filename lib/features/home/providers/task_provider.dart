import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/task_model.dart';
import '../data/task_repository.dart';
import 'package:goodloop/features/auth/providers/auth_provider.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository();
});

final activeTasksProvider = StreamProvider<List<TaskModel>>((ref) {
  final userAsync = ref.watch(currentUserProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);

  return userAsync.when(
    data: (user) {
      if (user == null) return Stream.value([]);

      return taskRepo.getGlobalDailyTasks().map((allTasks) {
        final completedIds = user.completedTaskIds;

        return allTasks.where((task) {
          return !completedIds.contains(task.id);
        }).toList();
      });
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

class TaskController extends StateNotifier<AsyncValue<void>> {
  final TaskRepository _taskRepository;
  final String userId;

  TaskController(this._taskRepository, this.userId)
      : super(const AsyncValue.data(null));

  // ✅ Metoda wywoływana z UI po kliknięciu "Complete"
  Future<void> completeTask(String taskId, int points) async {
    state = const AsyncValue.loading();
    try {
      await _taskRepository.completeGlobalTask(userId, taskId, points);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  // (Metoda createTask, jeśli używana do prywatnych zadań)
  Future<void> createTask({
    required String title,
    required String description,
    TaskCategory category = TaskCategory.other,
    DateTime? dueDate,
    int points = 10,
  }) async {
    state = const AsyncValue.loading();
    try {
      final task = TaskModel(
        id: '',
        userId: userId,
        title: title,
        description: description,
        category: category,
        points: points,
        createdAt: DateTime.now(),
        dueDate: dueDate,
      );
      await _taskRepository.createTask(task);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final taskControllerProvider =
    StateNotifierProvider.family<TaskController, AsyncValue<void>, String>((
  ref,
  userId,
) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  return TaskController(taskRepo, userId);
});
