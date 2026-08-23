import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodloop/data/models/task_model.dart';
import 'package:goodloop/data/repositories/task_repository.dart';

void main() {
  group('TaskRepository.parseGlobalTask', () {
    test('handles a real global_tasks document shape without crashing', () {
      final task = TaskRepository.parseGlobalTask('task1', {
        'title': 'Poranny stretch',
        'description': 'Rozciągnij się przez 5 minut po przebudzeniu',
        'category': 'health',
        'difficulty': 'easy',
        'points': 10,
        'isActive': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      expect(task, isNotNull);
      expect(task!.title, 'Poranny stretch');
      expect(task.category, TaskCategory.health);
      expect(task.difficulty, 'easy');
      expect(task.points, 10);
      expect(task.createdAt, DateTime(2026, 1, 1));
    });

    test('difficulty as a string ("easy"/"medium"/"hard") never crashes', () {
      for (final value in ['easy', 'medium', 'hard']) {
        final task = TaskRepository.parseGlobalTask('t', {
          'title': 'x',
          'points': 5,
          'difficulty': value,
        });
        expect(task!.difficulty, value);
      }
    });

    test('points is read directly from the points field, not derived from difficulty', () {
      final task = TaskRepository.parseGlobalTask('t', {
        'title': 'x',
        'difficulty': 'hard',
        'points': 10,
      });
      expect(task!.points, 10);
    });

    test('unknown category value falls back to TaskCategory.other', () {
      final task = TaskRepository.parseGlobalTask('t', {
        'title': 'x',
        'category': 'this-category-does-not-exist',
      });
      expect(task!.category, TaskCategory.other);
    });

    test('isActive: false excludes the task', () {
      final task = TaskRepository.parseGlobalTask('t', {
        'title': 'x',
        'isActive': false,
      });
      expect(task, isNull);
    });

    test('missing isActive field defaults to active (included)', () {
      final task = TaskRepository.parseGlobalTask('t', {'title': 'x'});
      expect(task, isNotNull);
    });

    test('empty/missing data does not throw and falls back to safe defaults', () {
      expect(() => TaskRepository.parseGlobalTask('t', {}), returnsNormally);

      final task = TaskRepository.parseGlobalTask('t', {});
      expect(task, isNotNull);
      expect(task!.points, 10);
      expect(task.category, TaskCategory.other);
      expect(task.difficulty, isNull);
    });

    test('malformed points (wrong type) does not throw', () {
      expect(
        () => TaskRepository.parseGlobalTask('t', {
          'title': 'x',
          'points': 'not-a-number',
        }),
        returnsNormally,
      );
    });
  });
}
