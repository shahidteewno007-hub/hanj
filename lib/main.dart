import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import 'core/theme/app_theme.dart';
import 'core/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'features/auth/login_screen.dart';
import 'features/main_screen.dart';
import 'features/auth/email_verification_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/cards/card_collection_screen.dart';
import 'features/cards/card_unlock_overlay.dart';
import 'cadre/screens/cadre_lobby_screen.dart';
import 'firebase_options.dart';

final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Route all Flutter framework errors to Crashlytics
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Route async/uncaught Dart errors to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Firebase error: $e');
  }

  if (!kIsWeb) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      debugPrint('Firestore settings error: $e');
    }
  }

  try {
    await ConnectivityService.instance.init();
  } catch (e) {
    debugPrint('Connectivity error: $e');
  }

  // Deliberately NOT awaited. init() opens the OS notification permission
  // dialog and does an FCM token round trip — measured at ~1.0 s on device,
  // the single largest phase before runApp() — and the first frame needs none
  // of it. Starting it here lets it run alongside runApp() instead of in front
  // of it. The catchError keeps failures handled: an unhandled async error
  // would be reported to Crashlytics as fatal (see PlatformDispatcher.onError
  // above), which is exactly what the old try/catch was preventing.
  NotificationService.instance.init().catchError((Object e) {
    debugPrint('Notification error: $e');
  });

  FirebaseMessaging.onMessage.listen((message) {
    final type  = message.data['type'] ?? '';

    // Card unlock — show the full-screen overlay
    if (type == 'card_unlock') {
      final cardId    = message.data['cardId']    ?? '';
      final rarity    = message.data['rarity']    ?? 'common';
      final title     = message.notification?.title ?? 'New card unlocked';
      final body      = message.notification?.body  ?? '';
      // Extract card name from notification title (strip emoji prefix)
      final cardName  = title.replaceAll(RegExp(r'^[^\w]+'), '').trim();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = NotificationNavigator.navigatorKey.currentContext;
        if (ctx != null) {
          showCardUnlockOverlay(ctx,
            cardId:          cardId,
            cardName:        cardName.isEmpty ? cardId : cardName,
            cardDescription: body,
            rarity:          rarity,
          );
        }
      });
      return;
    }

    // All other notifications — show snackbar
    final title = message.notification?.title ?? message.data['title'] ?? 'Hanj';
    final body  = message.notification?.body  ?? message.data['body']  ?? '';

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1A1612),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE8624A), width: 1),
        ),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE8624A).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_rounded,
                color: Color(0xFFE8624A),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFF5F0E8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(
                      body,
                      style: const TextStyle(
                        color: Color(0xFFF5F0E8),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  });

  // Background / terminated tap — navigate when user taps notification
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final type = message.data['type'] ?? '';
    if (type == 'card_unlock') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationNavigator.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => const CardCollectionScreen(),
        ));
      });
    }
  });

  // Check if app was opened from terminated state via notification
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null) return;
    final type = message.data['type'] ?? '';
    if (type == 'card_unlock') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationNavigator.navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => const CardCollectionScreen(),
        ));
      });
    }
  });

  runApp(const HanjApp());
}

class HanjApp extends StatelessWidget {
  const HanjApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthService()),
      ],
      child: Builder(
        builder: (context) {
          final themeProvider = context.watch<ThemeProvider>();
          return MaterialApp(
            title: 'Hanj',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            navigatorKey: NotificationNavigator.navigatorKey,
            scaffoldMessengerKey: _scaffoldMessengerKey,
            navigatorObservers: [
              FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
            ],
            routes: {
              '/cards': (_) => const CardCollectionScreen(),
              '/cadre': (_) => const CadreLobbyScreen(),
            },
            home: const AuthWrapper(),
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show plain dark screen while Firebase resolves auth state
          return const Scaffold(backgroundColor: Color(0xFF0D0B09));
        }

        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          // Block access if email is not verified (except for Google sign-in users).
          // We watch AuthService (ChangeNotifier) so that when the verification
          // screen confirms the email, this rebuilds and proceeds to MainScreen.
          return Consumer<AuthService>(
            builder: (context, _, _) {
              final current = FirebaseAuth.instance.currentUser;
              if (current == null) return const LoginScreen();
              final providers =
                  current.providerData.map((p) => p.providerId).toList();
              final isGoogleUser = providers.contains('google.com');
              if (!isGoogleUser && !current.emailVerified) {
                return const EmailVerificationScreen();
              }
              // Check onboarding completion before showing main app
              return _OnboardingGate(uid: current.uid);
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}

// Decides whether a signed-in, verified user still needs onboarding.
// Uses a live stream on the user doc so that completing onboarding
// (which sets onboardingComplete: true) flips this to MainScreen automatically.
class _OnboardingGate extends StatelessWidget {
  final String uid;
  const _OnboardingGate({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Color(0xFF0D0B09));
        }
        final data = snap.data?.data() as Map<String, dynamic>?;
        final done = data?['onboardingComplete'] == true;
        if (!done) return const OnboardingScreen();
        return const MainScreen();
      },
    );
  }
}
