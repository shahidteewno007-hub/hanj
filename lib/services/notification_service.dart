import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<void> init() async {
    // 1. Request permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // 2. Get & save FCM token
    await _saveToken();
    _fcm.onTokenRefresh.listen(_saveToken);

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

  // ── Token ─────────────────────────────────────────────────────────────────

  /// Call this after login/signup so the token is saved with the correct uid.
  Future<void> saveTokenForCurrentUser() => _saveToken();

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

  void _handlePayload(RemoteMessage message) {
    final nav = NotificationNavigator.navigatorKey.currentState;
    if (nav == null) return;

    final type    = message.data['type'] as String?;
    final animeId = message.data['animeId'] as String?;

    switch (type) {
      case 'new_season':
      case 'episode_reminder':
        if (animeId != null) {
          nav.pushNamed('/anime-detail', arguments: animeId);
        }
        break;
      case 'social':
        nav.pushNamed('/social');
        break;
      case 'weekly_recap':
        nav.pushNamed('/wrapped');
        break;
      case 'card_unlock':
        nav.pushNamed('/cards');
        break;
      case 'streak':
        nav.pushNamed('/home');
        break;
    }
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
