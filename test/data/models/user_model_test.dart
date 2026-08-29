import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goodloop/data/models/user_model.dart';

void main() {
  group('UserModel.fromMap', () {
    test('reads the new photoUrl field', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'email': 'a@b.c',
        'displayName': 'Ala',
        'photoUrl': 'https://example.com/a.png',
      });
      expect(u.photoUrl, 'https://example.com/a.png');
    });

    test('falls back to the legacy photoURL during the migration window', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'email': 'a@b.c',
        'displayName': 'Ala',
        'photoURL': 'https://example.com/legacy.png',
      });
      expect(u.photoUrl, 'https://example.com/legacy.png');
    });

    test('new photoUrl wins over legacy photoURL when both are present', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'email': 'a@b.c',
        'displayName': 'Ala',
        'photoUrl': 'new',
        'photoURL': 'old',
      });
      expect(u.photoUrl, 'new');
    });

    test('missing lastCompletedTaskId / lastUnlockedAchievement default to empty', () {
      final u = UserModel.fromMap({
        'uid': 'u1',
        'email': 'a@b.c',
        'displayName': 'Ala',
      });
      expect(u.lastCompletedTaskId, '');
      expect(u.lastUnlockedAchievement, '');
    });

    test('empty map does not throw and yields safe defaults', () {
      expect(() => UserModel.fromMap({}), returnsNormally);
      final u = UserModel.fromMap({});
      expect(u.completedTasks, 0);
      expect(u.totalPoints, 0);
      expect(u.level, 1);
      expect(u.achievements, isEmpty);
      expect(u.completedTaskIds, isEmpty);
    });
  });

  group('UserModel.toMap', () {
    test('writes photoUrl (not photoURL) and the helper fields', () {
      final u = UserModel(
        uid: 'u1',
        email: 'a@b.c',
        displayName: 'Ala',
        photoUrl: 'https://example.com/a.png',
        createdAt: DateTime(2026, 1, 1),
        lastActive: DateTime(2026, 1, 2),
        level: 1,
        lastCompletedTaskId: 'task42',
        lastUnlockedAchievement: 'first_task',
      );
      final map = u.toMap();
      expect(map.containsKey('photoURL'), isFalse);
      expect(map['photoUrl'], 'https://example.com/a.png');
      expect(map['lastCompletedTaskId'], 'task42');
      expect(map['lastUnlockedAchievement'], 'first_task');
    });

    test('round-trips through fromMap', () {
      final original = UserModel(
        uid: 'u1',
        email: 'a@b.c',
        displayName: 'Ala',
        photoUrl: null,
        completedTasks: 3,
        streakDays: 2,
        totalPoints: 30,
        createdAt: DateTime(2026, 1, 1),
        lastActive: DateTime(2026, 1, 2),
        level: 1,
        achievements: const ['first_task'],
        completedTaskIds: const ['t1', 't2', 't3'],
        lastCompletedTaskId: 't3',
        lastUnlockedAchievement: 'first_task',
      );

      final restored = UserModel.fromMap(
        original.toMap().map((k, v) => MapEntry(k, v is Timestamp ? v : v)),
      );

      expect(restored, original);
    });
  });
}
