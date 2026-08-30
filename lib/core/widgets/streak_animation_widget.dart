import 'package:flutter/material.dart';
import 'dart:math' as math;

class StreakAnimationWidget extends StatefulWidget {
  final int streakDays;
  final double size;

  const StreakAnimationWidget({
    super.key,
    required this.streakDays,
    this.size = 120,
  });

  @override
  State<StreakAnimationWidget> createState() => _StreakAnimationWidgetState();
}

class _StreakAnimationWidgetState extends State<StreakAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _flameController;
  late AnimationController _pulseController;
  late AnimationController _rotateController;

  late Animation<double> _flameAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();

    _flameController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _flameAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _flameController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotateController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _rotateAnimation = Tween<double>(
      begin: 0,
      end: 2 * math.pi,
    ).animate(_rotateController);
  }

  @override
  void dispose() {
    _flameController.dispose();
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  Color _getStreakColor() {
    if (widget.streakDays >= 30) return Colors.purple;
    if (widget.streakDays >= 14) return Colors.red;
    if (widget.streakDays >= 7) return Colors.orange;
    return Colors.amber;
  }

  String _getStreakEmoji() {
    if (widget.streakDays >= 30) return '👑';
    if (widget.streakDays >= 14) return '💎';
    if (widget.streakDays >= 7) return '🔥';
    return '⭐';
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStreakColor();

    return GestureDetector(
      onTap: _showStreakDialog,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _flameAnimation,
          _pulseAnimation,
          _rotateAnimation,
        ]),
        builder: (context, child) {
          return Transform.scale(
            scale: widget.streakDays >= 7 ? _pulseAnimation.value : 1.0,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    color.withValues(alpha: 0.3),
                    color.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rotating glow for high streaks
                  if (widget.streakDays >= 14)
                    Transform.rotate(
                      angle: _rotateAnimation.value,
                      child: Container(
                        width: widget.size * 0.9,
                        height: widget.size * 0.9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SweepGradient(
                            colors: [
                              color.withValues(alpha: 0.0),
                              color.withValues(alpha: 0.5),
                              color.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Main flame
                  Transform.scale(
                    scale: _flameAnimation.value,
                    child: Container(
                      width: widget.size * 0.6,
                      height: widget.size * 0.6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _getStreakEmoji(),
                          style: TextStyle(fontSize: widget.size * 0.35),
                        ),
                      ),
                    ),
                  ),

                  // Streak number
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '${widget.streakDays} dni',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showStreakDialog() {
    showDialog(
      context: context,
      builder: (context) => StreakDetailsDialog(streakDays: widget.streakDays),
    );
  }
}

// Dialog z detalami streak
class StreakDetailsDialog extends StatelessWidget {
  final int streakDays;

  const StreakDetailsDialog({super.key, required this.streakDays});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(_getStreakEmoji(), style: const TextStyle(fontSize: 60)),
            const SizedBox(height: 16),
            Text(
              '$streakDays dni z rzędu!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _getStreakMessage(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),

            // Milestones
            _buildMilestones(),

            const SizedBox(height: 24),

            // Motivation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStreakColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.tips_and_updates, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    'Nie przerywaj pasmy!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wykonaj dzisiaj chociaż jedno zadanie',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Close button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zamknij'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStreakColor() {
    if (streakDays >= 30) return Colors.purple;
    if (streakDays >= 14) return Colors.red;
    if (streakDays >= 7) return Colors.orange;
    return Colors.amber;
  }

  String _getStreakEmoji() {
    if (streakDays >= 30) return '👑';
    if (streakDays >= 14) return '💎';
    if (streakDays >= 7) return '🔥';
    return '⭐';
  }

  String _getStreakMessage() {
    if (streakDays >= 30) {
      return 'Jesteś absolutną legendą! Twoja konsekwencja jest niesamowita!';
    } else if (streakDays >= 14) {
      return 'Wow! Dwie tygodnie non-stop. To już nawyk!';
    } else if (streakDays >= 7) {
      return 'Świetnie! Cały tydzień działania. Tak trzymaj!';
    } else if (streakDays >= 3) {
      return 'Dobry początek! Jeszcze tylko kilka dni do tygodnia.';
    }
    return 'Każdy dzień się liczy. Nie poddawaj się!';
  }

  Widget _buildMilestones() {
    final milestones = [
      {'days': 3, 'emoji': '🌱', 'label': 'Początek'},
      {'days': 7, 'emoji': '🔥', 'label': 'Tydzień'},
      {'days': 14, 'emoji': '💎', 'label': '2 tygodnie'},
      {'days': 30, 'emoji': '👑', 'label': 'Miesiąc'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: milestones.map((milestone) {
        final days = milestone['days'] as int;
        final isAchieved = streakDays >= days;

        return Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isAchieved
                    ? _getStreakColor().withValues(alpha: 0.2)
                    : Colors.grey.shade200,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isAchieved ? _getStreakColor() : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: Center(
                child: Opacity(
                  opacity: isAchieved ? 1.0 : 0.3,
                  child: Text(
                    milestone['emoji'] as String,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              milestone['label'] as String,
              style: TextStyle(
                fontSize: 10,
                color: isAchieved ? _getStreakColor() : Colors.grey,
                fontWeight: isAchieved ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
