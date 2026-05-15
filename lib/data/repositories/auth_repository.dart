import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'user_repository.dart';
import '../../logger.dart';

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserRepository _userRepository = UserRepository();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw Exception('Failed to create Firebase user');
      }

      await firebaseUser.updateDisplayName(displayName);
      await firebaseUser.reload();

      final userModel = UserModel(
        uid: firebaseUser.uid,
        email: email,
        displayName: displayName,
        photoURL: firebaseUser.photoURL,
        createdAt: DateTime.now(),
        lastActive: DateTime.now(),
        level: 1,
      );

      await _userRepository.createUser(userModel);

      logger.i('✅ User registered: ${firebaseUser.uid}');
      return userModel;
    } on FirebaseAuthException catch (e) {
      logger.e('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      logger.e('❌ Sign up error: $e');
      rethrow;
    }
  }

  Future<UserModel?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = userCredential.user;
      if (firebaseUser == null) {
        throw Exception('Failed to sign in');
      }

      final userModel = await _userRepository.getUser(firebaseUser.uid);

      if (userModel == null) {
        logger.w('⚠️ User document missing, creating new one');
        final newUser = UserModel(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? email,
          displayName: firebaseUser.displayName ?? 'User',
          photoURL: firebaseUser.photoURL,
          createdAt: DateTime.now(),
          lastActive: DateTime.now(),
          level: 1,
        );
        await _userRepository.createUser(newUser);
        return newUser;
      }

      await _userRepository.updateUser(firebaseUser.uid, {
        'lastActive': DateTime.now(),
      });

      logger.i('✅ User signed in: ${firebaseUser.uid}');
      return userModel;
    } on FirebaseAuthException catch (e) {
      logger.e('❌ Firebase Auth Error: ${e.code} - ${e.message}');
      throw _handleAuthException(e);
    } catch (e) {
      logger.e('❌ Sign in error: $e');
      rethrow;
    }
  }

  Future<UserModel?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        logger.w('⚠️ Google sign in cancelled');
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) {
        throw Exception('Failed to sign in with Google');
      }

      UserModel? existingUser = await _userRepository.getUser(firebaseUser.uid);

      if (existingUser == null) {
        final newUser = UserModel(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName ?? 'User',
          photoURL: firebaseUser.photoURL,
          createdAt: DateTime.now(),
          lastActive: DateTime.now(),
          level: 1,
        );
        await _userRepository.createUser(newUser);
        logger.i('✅ New Google user created: ${firebaseUser.uid}');
        return newUser;
      } else {
        await _userRepository.updateUser(firebaseUser.uid, {
          'lastActive': DateTime.now(),
        });
        logger.i('✅ Existing Google user signed in: ${firebaseUser.uid}');
        return existingUser;
      }
    } catch (e) {
      logger.e('❌ Google sign in error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
      logger.i('✅ User signed out');
    } catch (e) {
      logger.e('❌ Sign out error: $e');
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      logger.i('✅ Password reset email sent to: $email');
    } on FirebaseAuthException catch (e) {
      logger.e('❌ Reset password error: ${e.code}');
      throw _handleAuthException(e);
    }
  }

  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _userRepository.deleteUser(user.uid);
        await user.delete();
        logger.i('✅ Account deleted');
      }
    } catch (e) {
      logger.e('❌ Delete account error: $e');
      rethrow;
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Nie znaleziono użytkownika z tym adresem email.';
      case 'wrong-password':
        return 'Nieprawidłowe hasło.';
      case 'email-already-in-use':
        return 'Ten adres email jest już zarejestrowany.';
      case 'invalid-email':
        return 'Nieprawidłowy format adresu email.';
      case 'weak-password':
        return 'Hasło jest zbyt słabe.';
      case 'operation-not-allowed':
        return 'Ta metoda logowania jest wyłączona.';
      case 'user-disabled':
        return 'To konto zostało zablokowane.';
      default:
        return 'Wystąpił błąd: ${e.message}';
    }
  }
}
