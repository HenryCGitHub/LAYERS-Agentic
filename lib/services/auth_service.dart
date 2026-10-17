import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal() {
    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        _currentUser = user;
        notifyListeners();
      });
    } catch (_) {}
  }

  User? _currentUser;
  User? get currentUser {
    try {
      return _currentUser ?? FirebaseAuth.instance.currentUser;
    } catch (_) {
      return _currentUser;
    }
  }
  bool get isLoggedIn => currentUser != null;

  String? _lastError;
  String? get lastError => _lastError;

  Future<UserCredential?> signInWithGoogle() async {
    _lastError = null;
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      googleProvider.addScope('profile');

      final userCredential =
          await FirebaseAuth.instance.signInWithPopup(googleProvider);
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Error: ${e.code} - ${e.message}');
      if (e.code == 'unauthorized-domain') {
        _lastError =
            'Please add henrycgithub.github.io to Authorized Domains in Firebase Console.';
      } else {
        _lastError = e.message ?? e.code;
      }
      return null;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      _lastError = e.toString();
      return null;
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}
