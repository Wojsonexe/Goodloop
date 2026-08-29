import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:confetti/confetti.dart';
import 'package:go_router/go_router.dart';
import 'package:goodloop/data/models/achievement_model.dart';
import 'package:goodloop/data/models/task_model.dart';
import 'package:goodloop/domain/providers/achievement_provider.dart';
import 'package:goodloop/features/friends/providers/friends_providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/providers/auth_provider.dart';
import '../../../domain/providers/task_provider.dart';
import '../../widgets/custom_button.dart';
import 'widgets/task_card.dart';
import 'widgets/progress_indicator.dart';
import 'widgets/streak_badge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late ConfettiController _confettiController;
  final _reflectionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _reflectionController.dispose();
    super.dispose();
  }

  Future<void> _completeTask(TaskModel task) async {
    final user = await ref.read(currentUserProvider.future);

    if (user == null) return;
    if (!mounted) return;

    final reflection = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share Your Experience'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Would you like to share how you completed this task? (Optional)',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reflectionController,
              decoration: const InputDecoration(
                hintText: 'I helped my friend with...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _reflectionController.text),
            child: const Text('Share'),
          ),
        ],
      ),
    );

    if (reflection == null) return;

    await ref
        .read(taskControllerProvider(user.id).notifier)
        .completeTask(task.id, task.points);

    if (!mounted) return;

    // Punkty + konfetti od razu.
    _confettiController.play();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 +${task.points} points! Amazing job!'),
        backgroundColor: AppColors.success,
      ),
    );

    // Sprawdź osiągnięcia. Liczbę ukończonych zadań liczymy lokalnie —
    // zapis w Firestore (increment) mógł się jeszcze nie rozpropagować,
    // więc ponowny odczyt zwróciłby starą wartość.
    final unlocked =
        await ref.read(achievementCheckerProvider).checkAfterTaskCompletion(
              userId: user.id,
              alreadyUnlocked: user.achievements.toSet(),
              completedTasks: user.completedTasks + 1,
              streakDays: user.streakDays,
              completionTime: DateTime.now(),
            );
    if (!mounted || unlocked.isEmpty) return;

    final newlyUnlocked = unlocked
        .map(AchievementModel.byId)
        .whereType<AchievementModel>()
        .toList();
    if (newlyUnlocked.isEmpty) return;

    await _showUnlockedDialog(newlyUnlocked);
  }

  Future<void> _showUnlockedDialog(List<AchievementModel> achievements) async {
    if (!mounted) return;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          achievements.length == 1
              ? 'Nowe osiągnięcie!'
              : 'Nowe osiągnięcia! (${achievements.length})',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in achievements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(a.icon, style: const TextStyle(fontSize: 32)),
                title: Text(a.title),
                subtitle: Text(a.description),
                trailing: Text(
                  '+${a.points}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Super!'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/achievements');
            },
            child: const Text('Zobacz wszystkie'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final activeTaskAsync = ref.watch(activeTasksProvider);

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: AppColors.primaryGradient),
          ),
          SafeArea(
            child: userAsync.when(
              data: (user) {
                if (user == null) {
                  return const Center(child: Text('User not found'));
                }
                return Column(
                  children: [
                    // Header (User Profile)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${user.displayName}! 👋',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Level ${user.level}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => context.push('/settings'),
                            child: CircleAvatar(
                              radius: 28,
                              backgroundImage: user.photoUrl != null
                                  ? NetworkImage(user.photoUrl!)
                                  : null,
                              child: user.photoUrl == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Stats Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(child: StreakBadge(streak: user.streak)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    '⭐',
                                    style: TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${user.points}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Points',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Main Content (Task Card)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                        ),
                        child: activeTaskAsync.when(
                          data: (tasks) {
                            // ✅ Jeśli lista jest pusta (po odfiltrowaniu zrobionych),
                            // oznacza to, że użytkownik wykonał już wszystko.
                            if (tasks.isEmpty) {
                              return _buildCompletedView(context);
                            }

                            // Pobieramy pierwsze dostępne zadanie
                            final currentTask = tasks.first;

                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Today\'s Task',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),
                                  TaskCard(task: currentTask),
                                  const SizedBox(height: 24),
                                  CustomButton(
                                    onPressed: () => _completeTask(currentTask),
                                    child: const Text('Mark as Complete'),
                                  ),
                                  const SizedBox(height: 16),
                                  CustomProgressIndicator(
                                    current: user.completedTasks,
                                    total: 100, // Tu możesz wstawić cel
                                  ),
                                ],
                              ),
                            );
                          },
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          error: (error, _) =>
                              Center(child: Text('Error: $error')),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),

          // Confetti Overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              particleDrag: 0.05,
              emissionFrequency: 0.05,
              numberOfParticles: 30,
              gravity: 0.2,
            ),
          ),
        ],
      ),

      // Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 0:
              break;
            case 1:
              context.push('/achievements');
              break;
            case 2:
              context.push('/friends');
              break;
            case 3:
              context.push('/settings');
              break;
          }
        },
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events),
            label: 'Achievements',
          ),
          BottomNavigationBarItem(
            icon: Badge.count(
              count: ref.watch(incomingRequestCountProvider),
              isLabelVisible: ref.watch(incomingRequestCountProvider) > 0,
              child: const Icon(Icons.group),
            ),
            label: 'Znajomi',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('✨', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 24),
            Text(
              'Great Job!',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve completed today\'s task',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            CustomButton(
              onPressed: () => context.push('/achievements'),
              child: const Text('Zobacz osiągnięcia'),
            ),
          ],
        ),
      ),
    );
  }
}
