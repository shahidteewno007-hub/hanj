import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'notification_service.dart';

class SignUpResult {
  final bool isSuccess;
  final String? errorMessage;
  final bool needsVerification;

  SignUpResult.success({this.needsVerification = false})
      : isSuccess = true,
        errorMessage = null;

  SignUpResult.failure(this.errorMessage)
      : isSuccess = false,
        needsVerification = false;
}

class AuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  bool get needsEmailVerification {
    final user = _auth.currentUser;
    if (user == null) return false;
    final providers = user.providerData.map((p) => p.providerId).toList();
    if (providers.contains('google.com')) return false;
    return !user.emailVerified;
  }

  /// Web Client ID from android/app/google-services.json
  /// (oauth_client entry where client_type == 3)
  static const String _googleServerClientId =
      '572595796065-gu6s6tq1hv5s1rhp25bfegqateqlgo6o.apps.googleusercontent.com';

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
    _googleInitialized = true;
  }

  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      NotificationService.instance.saveTokenForCurrentUser();
      return cred;
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(username.trim());

      try {
        await cred.user?.sendEmailVerification();
      } catch (_) {}

      NotificationService.instance.saveTokenForCurrentUser();
      return SignUpResult.success(needsVerification: true);
    } on FirebaseAuthException catch (e) {
      return SignUpResult.failure(_handleError(e));
    } catch (e) {
      return SignUpResult.failure('Something went wrong. Please try again.');
    }
  }

  /// Sign in with Google using google_sign_in ^7.x API.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      // v7 API: authenticate() replaces signIn()
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      // authentication is now a sync getter, not async
      final googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);

      if (userCred.additionalUserInfo?.isNewUser == true) {
        final displayName = googleUser.displayName;
        if (displayName != null && displayName.isNotEmpty) {
          await userCred.user?.updateDisplayName(displayName);
        }
      }

      NotificationService.instance.saveTokenForCurrentUser();
      return userCred;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null; // user cancelled — don't throw
      }
      throw 'Google sign-in failed: ${e.description ?? e.code.name}';
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    } catch (e) {
      throw 'Google sign-in failed. Please try again.';
    }
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    await user.sendEmailVerification();
  }

  Future<bool> checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> signOut() async {
    try {
      if (_googleInitialized) {
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {}
    await _auth.signOut();
    notifyListeners();
  }

  String _handleError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email under a different sign-in method.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
