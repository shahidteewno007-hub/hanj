import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/anime_model.dart';
import '../features/anime_detail/anime_detail_screen.dart';
import '../features/social/social_screen.dart';
import '../features/stats/stats_screen.dart';
import 'anilist_service.dart';
import 'offline_cache_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Background handler — top-level, only runs on mobile (not used on web)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background: ${message.notification?.title}');
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Service — web-first, mobile-ready
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;

  // Stream that the UI can listen to for foreground toasts
  final _messageController =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Whether the phone's permission prompt opens at start-up, before sign-in
  /// (code batch 1, audit 4a, PF-20, TS-008). False: start-up only reads
  /// what was decided before, and the prompt opens the first time someone
  /// sets a bell or turns a reminder on ([askPermission]). True gives back
  /// the prompt at launch as it was.
  static const bool askAtLaunch = false;

  Future<void> init() async {
    // 1. Request permission
    final settings = askAtLaunch
        ? await _fcm.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          )
        : await _fcm.getNotificationSettings();

    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // 2. Get & save FCM token. Not yet asked: no token until the first bell
    // (askPermission), but the taps below are still heard.
    if (askAtLaunch ||
        settings.authorizationStatus != AuthorizationStatus.notDetermined) {
      await _saveToken();
      _listenForToken();
    }

    // 3. Foreground messages → broadcast to UI
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[FCM] Foreground: ${msg.notification?.title}');
      _messageController.add(msg);
    });

    // 4. Background handler (mobile only — web uses service worker)
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);
    }

    // 5. App opened from notification
    FirebaseMessaging.onMessageOpenedApp.listen(_handlePayload);

    // 6. App launched from terminated state via notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handlePayload(initial);
  }

  // ── Permission at the first bell ─────────────────────────────────────────

  bool _listeningForToken = false;

  void _listenForToken() {
    if (_listeningForToken) return;
    _listeningForToken = true;
    _fcm.onTokenRefresh.listen(_saveToken);
  }

  /// Opens the phone's permission prompt, once, when someone first asks for
  /// a notification: a bell set on Home, Detail, Calendar or Upcoming, or a
  /// reminder turned on in Notifications. A prompt already answered doesn't
  /// open again; the phone just reports the answer. On a yes the token is
  /// saved, as init() used to at launch. Never throws, so callers needn't
  /// await it (Crashlytics files an unhandled async error as fatal). With
  /// [askAtLaunch] on it does nothing, as before.
  Future<void> askPermission() async {
    if (askAtLaunch) return;
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await _saveToken();
      _listenForToken();
    } catch (e) {
      debugPrint('[FCM] Permission request failed: $e');
    }
  }

  // ── Token ─────────────────────────────────────────────────────────────────

  /// Call this after login/signup so the token is saved with the correct uid.
  /// Not yet asked ([askAtLaunch] off): nothing, since on the web asking for
  /// a token opens the browser's prompt, which waits for the first bell.
  Future<void> saveTokenForCurrentUser() async {
    if (!askAtLaunch) {
      try {
        final settings = await _fcm.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.notDetermined ||
            settings.authorizationStatus == AuthorizationStatus.denied) {
          return;
        }
      } catch (_) {
        return;
      }
    }
    return _saveToken();
  }

  Future<void> _saveToken([String? token]) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      token ??= await _fcm.getToken(
        vapidKey: kIsWeb
            ? 'BEbe0INX8v07UrFcfoWyvty35SqFweBhV5gWdo8CZMzV2QXOW1TAD5YWAqlFB84tIqHeuhxwIKw_b2zvwlsaigM'
            : null,
      );
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return;
    }

    if (token == null) return;
    debugPrint('[FCM] Token saved: ${token.substring(0, 20)}...');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  // ── Navigation on tap ─────────────────────────────────────────────────────

  // A tapped push lands on a screen that exists (AUDIT.md S2-1). MaterialApp
  // registers only /cards, /cadre and /tierlist, so the other four names
  // this used to push (/anime-detail, /social, /wrapped, /home) threw.
  // Screens are pushed the way the rest of the app pushes them, and
  // anything without a screen of its own goes Home.
  Future<void> _handlePayload(RemoteMessage message) async {
    try {
      // Only for someone AuthWrapper would let in: signed in, and verified
      // unless they came through Google. A cold start waits for Auth here.
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) return;
      final isGoogleUser =
          user.providerData.any((p) => p.providerId == 'google.com');
      if (!isGoogleUser && !user.emailVerified) return;

      final type    = message.data['type'] as String?;
      final animeId = message.data['animeId'] as String?;

      Route<void>? route;
      switch (type) {
        case 'episode_reminder':
          // Detail by id, as Home's airing rows open it: the cached copy,
          // else one fetch through AniList's queue. If neither, Home.
          if (animeId != null && animeId.isNotEmpty) {
            Anime? anime = await OfflineCacheService.instance
                .getCachedAnimeDetail(animeId);
            anime ??= await AnilistService().getAnimeById(animeId);
            if (anime != null) {
              final found = anime;
              route = MaterialPageRoute(
                  builder: (_) => AnimeDetailScreen(anime: found));
            }
          }
          break;
        case 'social':
          // Friends, as Profile opens it.
          route = MaterialPageRoute(builder: (_) => const SocialScreen());
          break;
        case 'weekly_recap':
          // Wrapped is one of the screens lost in the incident (AUDIT.md
          // §5-C); Stats is the nearest, as Profile opens it.
          route = MaterialPageRoute(builder: (_) => const StatsScreen());
          break;
        case 'card_unlock':
          // Registered: Achievements, or closes at once while they're
          // locked until Hanj+ (main.dart).
          final nav = await _navigator();
          nav?.pushNamed('/cards');
          return;
        // new_season (no show of its own), streak and anything unknown
        // go Home.
      }

      final nav = await _navigator();
      if (nav == null) return;
      if (route != null) {
        nav.push(route);
      } else {
        nav.popUntil((r) => r.isFirst);
      }
    } catch (e) {
      debugPrint('[FCM] Tap navigation failed: $e');
    }
  }

  // The app's navigator, after a frame, so a push tapped from a cold start
  // finds MaterialApp mounted (main.dart's handlers wait the same way).
  Future<NavigatorState?> _navigator() async {
    await WidgetsBinding.instance.endOfFrame;
    return NotificationNavigator.navigatorKey.currentState;
  }

  // ── Preferences (Firestore) ───────────────────────────────────────────────

  Future<Map<String, bool>> getPreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Map<String, bool>.from(_defaultPrefs);

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    final raw = (doc.data()?['notifPrefs'] as Map<dynamic, dynamic>?)
        ?.cast<String, dynamic>();
    if (raw == null) return Map<String, bool>.from(_defaultPrefs);

    return {
      for (final key in _defaultPrefs.keys)
        key: raw[key] as bool? ?? _defaultPrefs[key]!,
    };
  }

  Future<void> setPreference(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'notifPrefs': {key: value}}, SetOptions(merge: true));
  }

  static const _defaultPrefs = {
    'new_season':       true,
    'episode_reminder': true,
    'weekly_recap':     true,
    'social':           true,
    'streak':           true,
  };

  void dispose() => _messageController.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// Global navigator key — set this on your MaterialApp in main.dart
// ─────────────────────────────────────────────────────────────────────────────

class NotificationNavigator {
  static final navigatorKey = GlobalKey<NavigatorState>();
}
