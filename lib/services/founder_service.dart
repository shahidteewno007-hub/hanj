import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles claiming a Founder number for the first 50 users.
///
/// Founder numbers are assigned via a Firestore transaction against a single
/// counter document (`meta/founders`), which guarantees that no two users
/// ever receive the same number — even if they sign up at the exact same
/// moment. Once 50 are claimed, no further numbers are issued.
class FounderService {
  FounderService._();
  static final instance = FounderService._();

  static const int maxFounders = 50;

  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _counterRef =>
      _db.collection('meta').doc('founders');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Attempts to claim a founder number for [uid]. Idempotent: if the user
  /// already has a number, it returns that number without claiming another.
  /// Returns the founder number (1–50) on success, or null if founder slots
  /// are full or claiming failed.
  Future<int?> claimFounderNumber(String uid) async {
    try {
      return await _db.runTransaction<int?>((txn) async {
        final userSnap = await txn.get(_userRef(uid));

        // Already a founder? Return existing number, claim nothing new.
        final existing = userSnap.data()?['founderNumber'] as int?;
        if (existing != null) return existing;

        final counterSnap = await txn.get(_counterRef);
        final current = (counterSnap.data()?['count'] as int?) ?? 0;

        // Slots full — not a founder.
        if (current >= maxFounders) return null;

        final next = current + 1;

        // Atomically bump the counter…
        txn.set(_counterRef, {
          'count': next,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // …and stamp the user as a founder.
        txn.set(_userRef(uid), {
          'isFounder': true,
          'founderNumber': next,
          'founderJoinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return next;
      });
    } catch (e) {
      // Transaction conflict or network error — caller can retry later.
      return null;
    }
  }

  /// Reads a user's founder status without claiming (for displaying the card).
  /// A successful read is written to the local cache; a failed one is not, so
  /// a network error never overwrites a known-good answer with a false one.
  Future<FounderStatus> getStatus(String uid) async {
    try {
      final snap = await _userRef(uid).get();
      final data = snap.data();
      if (data == null || data['isFounder'] != true) {
        const status = FounderStatus(isFounder: false);
        await _cacheStatus(uid, status);
        return status;
      }
      final status = FounderStatus(
        isFounder: true,
        number: data['founderNumber'] as int?,
        joinedAt: (data['founderJoinedAt'] as Timestamp?)?.toDate(),
      );
      await _cacheStatus(uid, status);
      return status;
    } catch (_) {
      return const FounderStatus(isFounder: false);
    }
  }

  // ── Local persistence ──────────────────────────────────────────────────
  // One entry per account, keyed by its uid (D22). Builds before this kept a
  // single unkeyed entry, so a second account signed in on the same device
  // was shown the first account's Founder pill and card.
  //
  // Founder status is immutable once granted: a user who holds a number keeps
  // it forever, and the rules freeze founderNumber once it is set. That makes
  // a GRANTED status safe to trust from disk for the account that earned it,
  // so the card can paint on the first frame, offline too, without a
  // Firestore round trip. The uid key is what keeps that safe: an entry is
  // only ever written from a server read of that same account's document.
  //
  // A NEGATIVE result is deliberately not final — someone who isn't a founder
  // yet may still claim one of the remaining slots — so it is cached only to
  // avoid a first-paint flicker, and callers must still run the claim.

  static String _statusKey(String uid) => 'founder_status_$uid';

  // The unkeyed entry older builds wrote. Nothing says which account it
  // belongs to, so it is never read; the first keyed write removes it.
  static const _legacyKeys = [
    'founder_is_founder',
    'founder_number',
    'founder_joined_at',
  ];

  /// The signed-in account's last known status from disk, or null if this
  /// device has never resolved one for that account (or nobody is signed in).
  Future<FounderStatus?> getCachedStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statusKey(uid));
      if (raw == null) return null;
      final cached = jsonDecode(raw) as Map<String, dynamic>;
      final millis = cached['joinedAt'] as int?;
      return FounderStatus(
        isFounder: cached['isFounder'] == true,
        number: cached['number'] as int?,
        joinedAt:
            millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheStatus(String uid, FounderStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // One string per account, so an entry is always one whole answer.
      await prefs.setString(_statusKey(uid), jsonEncode({
        'isFounder': status.isFounder,
        'number': ?status.number,
        'joinedAt': ?status.joinedAt?.millisecondsSinceEpoch,
      }));
      for (final key in _legacyKeys) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {
      // Cache is an optimisation only — a failure here must not break display.
    }
  }

  /// How many founder slots remain (for a "X spots left" prompt, optional).
  Future<int> remainingSlots() async {
    try {
      final snap = await _counterRef.get();
      final count = (snap.data()?['count'] as int?) ?? 0;
      return (maxFounders - count).clamp(0, maxFounders);
    } catch (_) {
      return 0;
    }
  }
}

class FounderStatus {
  final bool isFounder;
  final int? number;
  final DateTime? joinedAt;

  const FounderStatus({required this.isFounder, this.number, this.joinedAt});
}
