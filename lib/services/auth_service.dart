import 'package:flutter/foundation.dart' show kIsWeb;
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

  /// The OAuth client the browser identifies itself with.
  ///
  /// This is the project's existing client_type == 3 (Web) entry — the same
  /// one Android passes as serverClientId — so the idToken audience matches
  /// what Firebase already expects. Swap it here if a dedicated web client is
  /// preferred; whichever is used needs its Authorized JavaScript origins set
  /// (see WEB.md §2.3a).
  static const String _googleWebClientId = _googleServerClientId;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    // The two platforms take different parameters and the web plugin asserts
    // on the Android one: `serverClientId is not supported on Web`. On web the
    // clientId is mandatory — without it, initialize() asserts in debug and
    // throws a null check in release.
    if (kIsWeb) {
      await GoogleSignIn.instance.initialize(clientId: _googleWebClientId);
    } else {
      await GoogleSignIn.instance.initialize(
        serverClientId: _googleServerClientId,
      );
    }
    _googleInitialized = true;
  }

  /// Prepares the web sign-in flow and returns the stream of results.
  ///
  /// Web cannot call authenticate() — google_sign_in_web's
  /// supportsAuthenticate() is false and authenticate() throws
  /// UnimplementedError. Google Identity Services requires its own rendered
  /// button, so the credential arrives asynchronously on this stream instead
  /// of being returned by a call. The login screen renders the button and
  /// listens here.
  Future<Stream<GoogleSignInAuthenticationEvent>> webGoogleAuthEvents() async {
    await _ensureGoogleInitialized();
    return GoogleSignIn.instance.authenticationEvents;
  }

  /// Completes Firebase sign-in from a Google account produced by either
  /// platform's flow. Shared so the two paths cannot drift apart.
  Future<UserCredential> completeGoogleSignIn(GoogleSignInAccount user) async {
    final credential = GoogleAuthProvider.credential(
      idToken: user.authentication.idToken,
    );
    final userCred = await _auth.signInWithCredential(credential);

    if (userCred.additionalUserInfo?.isNewUser == true) {
      final displayName = user.displayName;
      if (displayName != null && displayName.isNotEmpty) {
        await userCred.user?.updateDisplayName(displayName);
      }
    }

    NotificationService.instance.saveTokenForCurrentUser();
    return userCred;
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
  ///
  /// Mobile only. On web the credential arrives via [webGoogleAuthEvents]
  /// instead — calling this there would reach the plugin's UnimplementedError,
  /// so it is turned into a message a user can act on rather than a crash.
  Future<UserCredential?> signInWithGoogle() async {
    if (kIsWeb) {
      throw 'Use the Google button to sign in on the web.';
    }
    try {
      await _ensureGoogleInitialized();

      // v7 API: authenticate() replaces signIn()
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      return await completeGoogleSignIn(googleUser);
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
