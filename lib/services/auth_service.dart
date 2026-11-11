import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  StreamSubscription<User?>? _authSubscription;

  AuthService._internal() {
    try {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
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

  /// Returns a valid Firebase ID token for authenticating against the LAYERS Cloud Function proxy.
  Future<String?> getValidIdToken({bool forceRefresh = false}) async {
    try {
      final user = currentUser;
      if (user == null) return null;
      return await user.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('Firebase getIdToken error: $e');
      return null;
    }
  }

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
    } finally {
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      _currentUser = null;
      _lastError = null;
    } catch (e) {
      debugPrint('Google Sign-Out Error: $e');
      _lastError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
