import 'package:cloud_firestore/cloud_firestore.dart';
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
        await _cacheStatus(status);
        return status;
      }
      final status = FounderStatus(
        isFounder: true,
        number: data['founderNumber'] as int?,
        joinedAt: (data['founderJoinedAt'] as Timestamp?)?.toDate(),
      );
      await _cacheStatus(status);
      return status;
    } catch (_) {
      return const FounderStatus(isFounder: false);
    }
  }

  // ── Local persistence ──────────────────────────────────────────────────
  // Founder status is immutable once granted: a user who holds a number keeps
  // it forever, and the rules are meant to prevent it being rewritten. That
  // makes a GRANTED status safe to trust from disk indefinitely, so the card
  // can paint on the first frame without a Firestore round trip.
  //
  // A NEGATIVE result is deliberately not final — someone who isn't a founder
  // yet may still claim one of the remaining slots — so it is cached only to
  // avoid a first-paint flicker, and callers must still run the claim.

  static const _kIsFounder = 'founder_is_founder';
  static const _kNumber    = 'founder_number';
  static const _kJoinedAt  = 'founder_joined_at';

  /// The last known status from disk, or null if we have never resolved one.
  Future<FounderStatus?> getCachedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kIsFounder)) return null;
      final millis = prefs.getInt(_kJoinedAt);
      return FounderStatus(
        isFounder: prefs.getBool(_kIsFounder) ?? false,
        number: prefs.getInt(_kNumber),
        joinedAt:
            millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheStatus(FounderStatus status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kIsFounder, status.isFounder);
      if (status.number != null) {
        await prefs.setInt(_kNumber, status.number!);
      }
      if (status.joinedAt != null) {
        await prefs.setInt(_kJoinedAt, status.joinedAt!.millisecondsSinceEpoch);
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
