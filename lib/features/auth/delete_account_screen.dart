import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Account Deletion Screen
//
// Play Store / App Store require an in-app account deletion flow. This:
//   1. Shows a clear warning about what's deleted
//   2. Re-authenticates the user (Firebase requires recent auth for deletion)
//   3. Deletes all Firestore subcollections (animeList, alerts, cards, etc.)
//   4. Deletes the user's auth account
//   5. Pops to the login screen
// ─────────────────────────────────────────────────────────────────────────────

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _busy        = false;
  bool _confirmed   = false;
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _busy = true);

    try {
      // 1. Re-authenticate (Firebase requires recent auth for delete)
      final providers = user.providerData.map((p) => p.providerId).toList();

      if (providers.contains('password')) {
        if (_passwordCtrl.text.trim().isEmpty) {
          _showSnackbar('Enter your password to confirm');
          setState(() => _busy = false);
          return;
        }
        final credential = EmailAuthProvider.credential(
          email:    user.email!,
          password: _passwordCtrl.text.trim(),
        );
        await user.reauthenticateWithCredential(credential);
      }
      // For Google/Apple/etc. sign-in, recent auth is usually fresh enough.
      // If not, FirebaseAuth throws 'requires-recent-login' and we surface that.

      // 2. Delete Firestore data (all subcollections + main doc)
      await _wipeUserData(user.uid);

      // 3. Delete the FCM token if any (best-effort)
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {}

      // 4. Delete the auth account
      await user.delete();

      // 5. Pop back to root — AuthWrapper will redirect to login
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'wrong-password':
          msg = 'Incorrect password';
          break;
        case 'requires-recent-login':
          msg = 'Please sign out and sign back in, then try again';
          break;
        default:
          msg = 'Could not delete account: ${e.message ?? e.code}';
      }
      _showSnackbar(msg);
    } catch (e) {
      _showSnackbar('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Recursively delete all subcollections under users/{uid}, then the user doc
  Future<void> _wipeUserData(String uid) async {
    final db   = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);

    // Known subcollections — explicit list so nothing is missed
    const subcollections = [
      'animeList',
      'alerts',
      'cards',
      'pinnedCards',
      'activity',
      'followers',
      'following',
      'firedAlerts',
    ];

    for (final sub in subcollections) {
      final snap = await userRef.collection(sub).get();
      // Batch deletes in chunks of 400 (Firestore limit is 500)
      for (var i = 0; i < snap.docs.length; i += 400) {
        final batch = db.batch();
        final chunk = snap.docs.skip(i).take(400);
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }

    // Delete the main user doc last
    await userRef.delete();
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.surfaceLight,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.dropped),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final hasPassword = user?.providerData
        .any((p) => p.providerId == 'password') ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Delete Account',
          style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Warning banner ─────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.dropped.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.dropped.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_rounded,
                        color: AppTheme.dropped, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This action is permanent and cannot be undone.',
                        style: AppTheme.sans(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          weight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── What gets deleted ──────────────────────────────────
              Text(
                'What will be deleted',
                style: AppTheme.mono(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 12),
              _bullet('Your anime list and ratings'),
              _bullet('Your watch history and progress'),
              _bullet('All your Hanj cards and points'),
              _bullet('Your alerts and notification preferences'),
              _bullet('Your followers and following list'),
              _bullet('Your profile and account credentials'),

              const SizedBox(height: 28),

              // ── Confirmation checkbox ──────────────────────────────
              GestureDetector(
                onTap: _busy
                    ? null
                    : () => setState(() => _confirmed = !_confirmed),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _confirmed
                            ? AppTheme.dropped
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _confirmed
                              ? AppTheme.dropped
                              : AppTheme.border,
                          width: 1.5,
                        ),
                      ),
                      child: _confirmed
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I understand this is permanent',
                        style: AppTheme.sans(
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Password (only if email/password user) ─────────────
              if (hasPassword) ...[
                const SizedBox(height: 24),
                Text(
                  'Confirm with password',
                  style: AppTheme.mono(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: true,
                  enabled: !_busy,
                  style: AppTheme.sans(fontSize: 14, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: AppTheme.sans(fontSize: 14, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.dropped),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // ── Delete button ──────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (!_confirmed || _busy) ? null : _deleteAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.dropped,
                    disabledBackgroundColor:
                        AppTheme.dropped.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Delete my account',
                          style: AppTheme.sans(
                              fontSize: 15,
                              color: Colors.white,
                              weight: FontWeight.w600),
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Cancel ────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                        weight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, right: 12),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppTheme.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTheme.sans(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
