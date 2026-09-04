// tomo_service.dart
//
// Talks to the chatWithTomo Cloud Function and persists nothing locally —
// history lives in Firestore (written by the function) and is loaded on open.
//
// SETUP: ensure cloud_functions is in pubspec.yaml:
//   cloud_functions: ^5.1.0
// Then: flutter pub get

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TomoMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  final int ts;
  const TomoMessage({required this.role, required this.text, required this.ts});

  bool get isUser => role == 'user';

  Map<String, dynamic> toApi() => {'role': role, 'text': text};

  factory TomoMessage.fromDoc(Map<String, dynamic> d) => TomoMessage(
        role: (d['role'] ?? 'assistant').toString(),
        text: (d['text'] ?? '').toString(),
        ts: (d['ts'] is int) ? d['ts'] as int : 0,
      );
}

class TomoReply {
  final String reply;
  final int remaining; // messages left today
  const TomoReply({required this.reply, required this.remaining});
}

class TomoService {
  TomoService._();
  static final TomoService instance = TomoService._();

  final _functions = FirebaseFunctions.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Load saved conversation (oldest first) so the screen can repopulate.
  Future<List<TomoMessage>> loadHistory({int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('companion_chat')
        .orderBy('ts', descending: true)
        .limit(limit)
        .get();
    final msgs = snap.docs
        .map((d) => TomoMessage.fromDoc(d.data()))
        .toList()
      ..sort((a, b) => a.ts.compareTo(b.ts)); // back to oldest-first
    return msgs;
  }

  /// Send a message. `history` is the recent on-screen turns (excluding the new
  /// message), used to give Tomo conversational memory.
  Future<TomoReply> send({
    required String message,
    required List<TomoMessage> history,
  }) async {
    final callable = _functions.httpsCallable(
      'chatWithTomo',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
    );

    final res = await callable.call<Map<String, dynamic>>({
      'message': message,
      'history': history.map((m) => m.toApi()).toList(),
    });

    final data = res.data;
    return TomoReply(
      reply: (data['reply'] ?? '').toString(),
      remaining: (data['remaining'] is int) ? data['remaining'] as int : 0,
    );
  }
}
