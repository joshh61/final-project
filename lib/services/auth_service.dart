import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes (logged in/out)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email & password
  Future<String?> signUp({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null; // Success
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        return 'Password is too weak, use at least 6 characters';
      } else if (e.code == 'email-already-in-use') {
        return 'An account with that email already exists';
      } else if (e.code == 'invalid-email') {
        return 'Please enter a valid email address';
      }
      return 'Something went wrong. Please try again';
    } catch (e) {
      return 'Something went wrong. Please try again';
    }
  }

  // Sign in with email & password
  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return 'No account found with that email';
      } else if (e.code == 'wrong-password') {
        return 'Incorrect password, please try again';
      } else if (e.code == 'invalid-email') {
        return 'Please enter a valid email address';
      } else if (e.code == 'invalid-credential') {
        return 'Email or password is incorrect';
      } else if (e.code == 'too-many-requests') {
        return 'Too many attempts. Please try again later';
      } else if (e.code == 'user-disabled') {
        return 'This account has been disabled';
      }
      return 'Something went wrong. Please try again';
    } catch (e) {
      return 'Something went wrong. Please try again';
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
