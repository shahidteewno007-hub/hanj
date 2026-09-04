import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EmailVerificationScreen
//
// Blocks the user from accessing the app until they verify their email.
// Polls Firebase every 4 seconds to detect verification, then proceeds.
// Allows resending the email (with a 60s cooldown).
// ─────────────────────────────────────────────────────────────────────────────

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _pollTimer;
  Timer? _cooldownTimer;
  int _resendCooldown = 0;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final auth = Provider.of<AuthService>(context, listen: false);
    final verified = await auth.checkEmailVerified();
    if (verified && mounted) {
      _pollTimer?.cancel();
      // AuthWrapper will detect the change and proceed automatically
      // but we trigger a rebuild to be safe
      Provider.of<AuthService>(context, listen: false).notifyListeners();
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await auth.resendVerificationEmail();
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Verification email sent. Check your inbox.'),
            backgroundColor: AppTheme.surfaceLight,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    }
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendCooldown <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendCooldown = 0);
      } else {
        if (mounted) setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _signOut() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _signOut,
                  child: Text(
                    'Sign out',
                    style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),

              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_outlined,
                    color: AppTheme.primary,
                    size: 30,
                  ),
                ),
              ),

              const SizedBox(height: 28),

              Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: AppTheme.serif(fontSize: 26, weight: FontWeight.w700),
              ),

              const SizedBox(height: 12),

              Text.rich(
                TextSpan(
                  style: AppTheme.sans(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'We sent a verification link to\n'),
                    TextSpan(
                      text: email,
                      style: AppTheme.sans(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                        text: '\n\nTap the link in your inbox to continue.\n\nCan\'t find it? Check your spam folder.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              if (_checking)
                const Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2,
                    ),
                  ),
                ),

              const Spacer(),

              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _resendCooldown > 0 ? null : _resend,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _resendCooldown > 0
                        ? 'Resend in ${_resendCooldown}s'
                        : 'Resend email',
                    style: AppTheme.sans(
                      fontSize: 14,
                      weight: FontWeight.w600,
                      color: _resendCooldown > 0
                          ? AppTheme.textMuted
                          : AppTheme.primary,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _check,
                child: Text(
                  _checking ? 'Checking...' : "I've verified, refresh",
                  style: AppTheme.sans(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
