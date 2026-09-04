import 'package:cloud_firestore/cloud_firestore.dart';

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
  Future<FounderStatus> getStatus(String uid) async {
    try {
      final snap = await _userRef(uid).get();
      final data = snap.data();
      if (data == null || data['isFounder'] != true) {
        return const FounderStatus(isFounder: false);
      }
      return FounderStatus(
        isFounder: true,
        number: data['founderNumber'] as int?,
        joinedAt: (data['founderJoinedAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return const FounderStatus(isFounder: false);
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
