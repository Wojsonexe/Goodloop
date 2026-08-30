import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:goodloop/core/utils/logger.dart';
import 'user_model.dart';

class UserRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get _usersCollection => _firestore.collection('users');

  Future<void> createUser(UserModel user) async {
    try {
      await _usersCollection.doc(user.uid).set(user.toMap());
      logger.i('✅ User created: ${user.uid}');
    } catch (e) {
      logger.e('❌ Error creating user: $e');
      rethrow;
    }
  }

  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _usersCollection.doc(uid).get();

      if (!doc.exists) {
        logger.w('⚠️ User document does not exist: $uid');
        return null;
      }

      final data = doc.data();

      if (data == null) {
        logger.w('⚠️ User document data is null: $uid');
        return null;
      }

      if (data is! Map<String, dynamic>) {
        logger.e('❌ User document data is not a Map: ${data.runtimeType}');
        return null;
      }

      return UserModel.fromMap(data);
    } catch (e) {
      logger.e('❌ Error getting user: $e');
      return null;
    }
  }

  Stream<UserModel?> getUserStream(String uid) {
    return _usersCollection.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        logger.w('⚠️ User snapshot does not exist: $uid');
        return null;
      }

      final data = snapshot.data();

      if (data == null) {
        logger.w('⚠️ User snapshot data is null: $uid');
        return null;
      }

      if (data is! Map<String, dynamic>) {
        logger.e('❌ User snapshot data is not a Map: ${data.runtimeType}');
        return null;
      }

      return UserModel.fromMap(data);
    });
  }

  Future<void> updateUser(String uid, Map<String, dynamic> updates) async {
    try {
      await _usersCollection.doc(uid).update({
        ...updates,
        'lastActive': FieldValue.serverTimestamp(),
      });
      logger.i('✅ User updated: $uid');
    } catch (e) {
      logger.e('❌ Error updating user: $e');
      rethrow;
    }
  }

  Future<void> incrementCompletedTasks(String uid, int points) async {
    try {
      await _usersCollection.doc(uid).update({
        'completedTasks': FieldValue.increment(1),
        'totalPoints': FieldValue.increment(points),
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      logger.e('❌ Error incrementing tasks: $e');
      rethrow;
    }
  }

  Future<void> updateStreak(String uid, int days) async {
    try {
      await _usersCollection.doc(uid).update({
        'streakDays': days,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      logger.e('❌ Error updating streak: $e');
      rethrow;
    }
  }

  Future<void> addAchievement(String uid, String achievementId) async {
    try {
      await _usersCollection.doc(uid).update({
        'achievements': FieldValue.arrayUnion([achievementId]),
        // Pole pomocnicze walidowane regułą Firestore — musi lecieć razem
        // z arrayUnion (patrz docs/firebase-schema.md, isAchievementUnlock).
        'lastUnlockedAchievement': achievementId,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      logger.e('❌ Error adding achievement: $e');
      rethrow;
    }
  }

  Future<List<UserModel>> getTopUsers({int limit = 10}) async {
    try {
      final query = await _usersCollection
          .orderBy('totalPoints', descending: true)
          .limit(limit)
          .get();

      return query.docs
          .map((doc) {
            final data = doc.data();
            if (data is Map<String, dynamic>) {
              return UserModel.fromMap(data);
            }
            return null;
          })
          .where((user) => user != null)
          .cast<UserModel>()
          .toList();
    } catch (e) {
      logger.e('❌ Error getting top users: $e');
      return [];
    }
  }

  Future<void> deleteUser(String uid) async {
    try {
      await _usersCollection.doc(uid).delete();
      logger.i('✅ User deleted: $uid');
    } catch (e) {
      logger.e('❌ Error deleting user: $e');
      rethrow;
    }
  }
}
