import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/tier_list/tier_list_store.dart';
import '../models/achievements.dart';
import 'media_facts.dart';

/// What the page, Profile's row and the badge read: the record, the counts
/// behind its "next" lines, and the badge you show.
class AchievementsState {
  const AchievementsState({
    this.uid,
    this.known = false,
    this.record = AchievementRecord.empty,
    this.badge,
    this.totals,
    this.factsComplete = false,
  });

  static const signedOut = AchievementsState();

  final String? uid;

  /// Whether the record is known yet (from this phone's copy or the user
  /// document). Until then nothing is claimed about it, as Profile claims
  /// nothing about a list it hasn't read.
  final bool known;
  final AchievementRecord record;

  /// The mark you show on Profile (users/{uid}.badge.mark), only ever one
  /// in the record; null for none.
  final String? badge;

  /// The counts from the last evaluation; null until one has run.
  final AchievementTotals? totals;

  /// Whether AniList's facts were known for every finished show then.
  final bool factsComplete;

  /// Day one (decision g): the page opens on "Your record so far".
  bool get dayOne => record.dayOne;

  /// What the page marks New: dated after you last looked.
  Set<String> get newKeys => record.newKeys;

  /// Achievements, never marks: what every screen counts.
  int get count => record.count;

  /// The next level of each count, nearest first.
  List<NextStep> get next => totals == null
      ? const []
      : Achievements.nextSteps(totals!, record.marks.keys.toSet());
}

/// An achievement earned live: the mark your own action just decided.
class LiveEarn {
  const LiveEarn(this.key, this.mark);

  final String key;
  final RecordMark mark;

  MarkRef? get ref => Achievements.parse(key);
}

/// Keeps your achievements: works the record out from your list on the
/// phone (lib/models/achievements.dart) and writes what's new to
/// users/{uid}.achievements, once, like ink.
///
/// How it's fed (design §8.1):
/// - Profile and Home hand it the whole list after each snapshot
///   ([observeList], debounced here; never from inside build()).
/// - Detail's and Home's actions report the entry they changed
///   ([noteAction]); a new mark that entry decides is a live earn, on
///   [liveEarns], for the unlock slip. Ranking Cards reports a Top 9
///   ([noteTop9]) and the tier list editor a list ([noteTierList]).
/// - The Achievements page asks for everything ([refresh]): the activity
///   log (read at most once a day per phone), AniList's media facts, the
///   tier lists on this device, and once ever the Hanj Cards to carry.
///
/// The record is `{ since, cards, seen, marks: { key: { at, how, show?,
/// card?, n? } } }` on the user document (no new rule: you may write your
/// own document, and signed-in users can read it as they can read your
/// list), with a copy on the phone keyed by uid, as FounderService keys its
/// cache, so the page paints on its first frame and offline. Day one, the
/// first evaluation for an account, writes everything found in one write,
/// with `since`, and none of it is a live earn: a past event isn't
/// celebrated as if it had just happened.
class AchievementsService {
  AchievementsService._();
  static final instance = AchievementsService._();

  final _db = FirebaseFirestore.instance;

  final ValueNotifier<AchievementsState> _state =
      ValueNotifier(AchievementsState.signedOut);

  /// The record as it stands, for the page, Profile's row and the badge.
  ValueListenable<AchievementsState> get state => _state;

  final _live = StreamController<List<LiveEarn>>.broadcast();

  /// Live earns, highest carving first: several from one action arrive
  /// together, for one slip ("and 2 more"). Never day one, an import or
  /// another phone's.
  Stream<List<LiveEarn>> get liveEarns => _live.stream;

  /// How long after an action a new mark it decides still counts as live:
  /// the list snapshot can arrive before or after the action is reported.
  static const _liveWindow = Duration(minutes: 2);

  /// How long Profile's and Home's snapshots settle before an evaluation.
  static const _settle = Duration(seconds: 1);

  /// Date fields a write stamps with the server's time; an action's
  /// FieldValue in one of these is read as now.
  static const _dateFields = {
    'addedAt', 'lastWatched', 'ratedAt', 'tagsUpdatedAt', 'favouritedAt',
    'notesUpdatedAt',
  };

  String? _uid;
  Future<void>? _loaded;

  /// The list as last fed, by entry id; null until it has been.
  Map<String, Map<String, Object?>>? _entries;

  /// Whether the server has confirmed the whole list this session. Once it
  /// has, the phone's cache holds all of it, offline too.
  bool _listConfirmed = false;

  /// Dates your own actions stamped, by entry and field, kept until the
  /// snapshot carries the server's (a pending server timestamp reads null).
  final Map<String, Map<String, DateTime>> _stamped = {};

  /// What you've just changed, and when: entry ids, `user:top9`, `tier:<id>`.
  final Map<String, DateTime> _recent = {};

  // The user document's facts.
  bool _fromServer = false;
  List<String>? _top9;
  DateTime? _top9At;
  bool _isFounder = false;
  int? _founderNumber;
  DateTime? _founderJoinedAt;

  Map<String, DateTime?>? _activity;
  String? _activityDay;
  Map<String, DateTime?>? _cards;
  List<TierListFact>? _tierLists;
  Map<int, ShowFacts> _facts = const {};

  /// Keys being written now, so a second evaluation doesn't write them again.
  final Set<String> _writing = {};

  Timer? _debounce;
  Future<void> _chain = Future.value();
  DateTime? _dayOneTriedAt;

  // ── Feeding the record ──────────────────────────────────────────────────

  /// Loads the signed-in account's record into [state]: the phone's copy at
  /// once, then the user document. Reads nothing else; call it from a
  /// screen's initState, never from build().
  Future<void> load() async {
    if (_user() == null) return;
    await _loaded;
  }

  /// Profile's and Home's list snapshot: the whole list. Evaluated a moment
  /// later, once snapshots settle, never during a frame.
  void observeList(QuerySnapshot<Object?> snapshot) {
    observeEntries({
      for (final d in snapshot.docs)
        if (d.data() case final Map<String, dynamic> data) d.id: data,
    }, fromServer: !snapshot.metadata.isFromCache);
  }

  /// The same, from entries already read, by entry id. [fromServer] says
  /// the server confirmed them: until a list has been, nothing is written,
  /// because the phone's cache can hold part of a list (what an earlier
  /// filtered query fetched), and a mark written from part of it would keep
  /// the wrong date and show for good.
  void observeEntries(Map<String, Map<String, dynamic>> entries,
      {required bool fromServer}) {
    if (_user() == null) return;
    if (fromServer) _listConfirmed = true;
    _entries = _withStamps(entries);
    _debounce?.cancel();
    _debounce = Timer(_settle, () => _run(() => _evaluate()));
    if (!_listConfirmed) unawaited(_confirmList());
  }

  /// When the list confirmation was last asked of the server.
  DateTime? _confirmAskedAt;

  /// A list fed from the phone's cache never becomes confirmed by itself:
  /// the server's confirmation of a cached result is a metadata-only change,
  /// which Profile's and Home's streams never hear (found on the web in
  /// stage 3). So an unconfirmed list fed here is read once from the server,
  /// which is what confirms it. Offline the read fails at once and the
  /// record simply waits; a later feed asks again, at most once a minute.
  Future<void> _confirmList() async {
    final uid = _uid;
    final now = DateTime.now();
    final asked = _confirmAskedAt;
    if (uid == null || _listConfirmed) return;
    if (asked != null && now.difference(asked) < const Duration(minutes: 1)) return;
    _confirmAskedAt = now;
    try {
      final snap = await _userDoc(uid)
          .collection('animeList')
          .get(const GetOptions(source: Source.server));
      if (_uid != uid || _listConfirmed) return;
      observeEntries({for (final d in snap.docs) d.id: d.data()}, fromServer: true);
    } catch (_) {
      // Offline, or refused: the cached list stands, unconfirmed.
    }
  }

  /// [entries] as the rules read them, with your own actions' dates
  /// standing in for pending server timestamps (which read null) until the
  /// server's arrive.
  Map<String, Map<String, Object?>> _withStamps(Map<String, Map<String, dynamic>> entries) {
    final plain = <String, Map<String, Object?>>{};
    for (final e in entries.entries) {
      final data = _plain(e.value);
      final stamped = _stamped[e.key];
      if (stamped != null) {
        stamped.removeWhere((field, _) => data[field] != null);
        for (final s in stamped.entries) {
          data[s.key] = s.value;
        }
        if (stamped.isEmpty) _stamped.remove(e.key);
      }
      plain[e.key] = data;
    }
    return plain;
  }

  /// One entry you just changed, with the fields as written (a
  /// FieldValue.serverTimestamp() in a date field reads as now). Evaluated
  /// at once: a new mark this entry decides is a live earn.
  Future<void> noteAction(String entryId, Map<String, dynamic> fields) async {
    if (_user() == null) return;
    final now = DateTime.now();
    final patch = <String, Object?>{};
    final stamped = _stamped.putIfAbsent(entryId, () => {});
    for (final f in fields.entries) {
      final value = f.value;
      if (value is FieldValue) {
        // A stamp (or, for favouritedAt, a delete that goes with removing
        // the mark, which the rules then ignore) reads as now; any other
        // FieldValue is left for the snapshot to settle.
        if (_dateFields.contains(f.key)) {
          patch[f.key] = now;
          stamped[f.key] = now;
        }
        continue;
      }
      patch[f.key] = value is Timestamp ? value.toDate() : value;
    }
    _recent[entryId] = now;
    await _run(() async {
      await _ensureList();
      final entries = _entries;
      if (entries == null) return;
      entries[entryId] = {...?entries[entryId], ...patch};
      _debounce?.cancel();
      await _evaluate();
    });
    // A new finish brings its show's facts (one request, only for it), for
    // the five rules that need them.
    final id = int.tryParse(entryId);
    if (patch['status'] == 'COMPLETED' && id != null) unawaited(_lookUpFacts([id]));
  }

  /// Your Top 9 just saved (with top9At beside it), or cleared.
  Future<void> noteTop9(List<String>? ids) async {
    if (_user() == null) return;
    _top9 = ids;
    _top9At = ids == null ? null : DateTime.now();
    _recent['user:top9'] = DateTime.now();
    await _run(() => _evaluate());
  }

  /// A tier list just saved on this device.
  Future<void> noteTierList(String listId) async {
    if (_user() == null) return;
    _recent['tier:$listId'] = DateTime.now();
    await _run(() async {
      await _readTierLists();
      await _evaluate();
    });
  }

  /// Everything, for the Achievements page: the user document again, the
  /// list if it hasn't been fed, the activity log (once a day per phone),
  /// the tier lists, the cards (once ever) and AniList's facts. Never throws.
  Future<void> refresh() async {
    final uid = _user();
    if (uid == null) return;
    await _run(() async {
      await _loaded;
      await _readUser(uid);
      await _ensureList();
      await _readActivity(uid);
      await _readTierLists();
      if (!_state.value.record.cards) await _readCards(uid);
      await _evaluate();
    });
    await _lookUpFacts();
  }

  // ── What you do with the record ─────────────────────────────────────────

  /// You've looked at the page: what's New stops being new.
  Future<void> markSeen() async {
    final uid = _user();
    if (uid == null) return;
    await _loaded;
    final now = DateTime.now();
    final s = _state.value;
    if (!s.record.started) return;
    _publish(record: s.record.copyWith(seen: now));
    await _saveLocal(uid);
    try {
      await _userDoc(uid).set({
        'achievements': {'seen': Timestamp.fromDate(now)},
      }, SetOptions(merge: true));
    } catch (_) {
      // The phone's copy keeps it; the next look writes it again.
    }
  }

  /// Shows [markKey] on your profile, in the corner (decision c). Only a
  /// mark in your record, and never Founder (decision f: it has its stamp
  /// under your name); false when it isn't, or the write failed.
  ///
  /// The badge is shown at once (stage 5): offline, Firestore's write
  /// waits for the server, and Profile would wait with it. A refused write
  /// puts the badge you had back.
  Future<bool> setBadge(String markKey) async {
    final uid = _user();
    if (uid == null) return false;
    await _loaded;
    if (!_state.value.record.marks.containsKey(markKey) || !canShow(markKey)) return false;
    return _writeBadge(uid, markKey);
  }

  /// Takes your badge off your profile, at once. False when the write
  /// failed, and the badge is back.
  Future<bool> clearBadge() async {
    final uid = _user();
    if (uid == null) return false;
    await _loaded;
    return _writeBadge(uid, null);
  }

  /// Whether [markKey] may be shown on a profile: any mark but Founder's.
  static bool canShow(String markKey) =>
      Achievements.parse(markKey)?.achievement.id != 'founder';

  Future<bool> _writeBadge(String uid, String? markKey) async {
    final before = _state.value.badge;
    _publish(badge: markKey, clearBadge: markKey == null);
    await _saveLocal(uid);
    try {
      await _userDoc(uid).set({
        'badge': markKey == null
            ? FieldValue.delete()
            : {'mark': markKey, 'place': 'corner'},
      }, SetOptions(merge: true));
      return true;
    } catch (_) {
      // Put back what was there, unless the account or the badge has
      // changed since (a later choice stands).
      if (_uid == uid && _state.value.badge == markKey) {
        _publish(badge: before, clearBadge: before == null);
        await _saveLocal(uid);
      }
      return false;
    }
  }

  /// Delete Account: forgets this phone's copy of the account's record and
  /// its activity cache. The record on the user document goes with the
  /// document itself.
  Future<void> clearLocal([String? uid]) async {
    final who = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (who == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recordKey(who));
      await prefs.remove(_activityKey(who));
    } catch (_) {}
    if (who == _uid) _reset(null);
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  /// The signed-in uid, loading its record when the account changed.
  String? _user() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != _uid) {
      _reset(uid);
      if (uid != null) _loaded = _load(uid);
    }
    return uid;
  }

  void _reset(String? uid) {
    _uid = uid;
    _loaded = null;
    _entries = null;
    _listConfirmed = false;
    _stamped.clear();
    _recent.clear();
    _fromServer = false;
    _top9 = null;
    _top9At = null;
    _isFounder = false;
    _founderNumber = null;
    _founderJoinedAt = null;
    _activity = null;
    _activityDay = null;
    _cards = null;
    _tierLists = null;
    _facts = const {};
    _writing.clear();
    _debounce?.cancel();
    _dayOneTriedAt = null;
    _confirmAskedAt = null;
    _state.value = AchievementsState(uid: uid);
  }

  /// The phone's copy first (the first frame, offline), then the user
  /// document.
  Future<void> _load(String uid) async {
    await _restoreLocal(uid);
    await _readTierLists();
    try {
      _facts = await MediaFacts.instance.known();
    } catch (_) {}
    await _readUser(uid);
  }

  Future<void> _readUser(String uid) async {
    try {
      final snap = await _userDoc(uid).get();
      if (_uid != uid) return;
      final data = snap.data() ?? const <String, dynamic>{};
      final top9 = data['top9'];
      _top9 = top9 is List ? [for (final id in top9) '$id'] : null;
      _top9At = _date(data['top9At']);
      _isFounder = data['isFounder'] == true;
      final n = data['founderNumber'];
      _founderNumber = n is num ? n.toInt() : null;
      _founderJoinedAt = _date(data['founderJoinedAt']);
      final record = _recordFrom(data['achievements']);
      final badge = _badgeFrom(data['badge'], record);
      // A document read from the phone's cache may be older than the
      // server's, so it never decides that the record hasn't begun. Nor
      // does a read that crosses day one's write on its way: a record this
      // phone began stands until that write is refused (_write).
      final fromServer = !snap.metadata.isFromCache;
      if (fromServer) _fromServer = true;
      if (record.started || (fromServer && !_state.value.record.started)) {
        _publish(known: true, record: _withWriting(record), badge: badge, clearBadge: badge == null);
        await _saveLocal(uid);
      }
    } catch (_) {
      // Offline with nothing cached: the phone's copy stands.
    }
  }

  /// [record] with the marks being written now kept, so a server read in
  /// the middle of a write doesn't drop them.
  AchievementRecord _withWriting(AchievementRecord record) {
    if (_writing.isEmpty) return record;
    final current = _state.value.record.marks;
    return record.copyWith(marks: {
      for (final k in _writing)
        if (current[k] case final RecordMark m) k: m,
      ...record.marks,
    });
  }

  /// The list, read when nobody has fed one the server confirmed (an action
  /// reported before Profile or Home): the rules need the whole list, never
  /// part of it, or a first finish could be written for your fiftieth.
  Future<void> _ensureList() async {
    final uid = _uid;
    if (uid == null || (_entries != null && _listConfirmed)) return;
    try {
      final snap = await _userDoc(uid).collection('animeList').get();
      if (_uid != uid || _listConfirmed) return;
      _entries = _withStamps({for (final d in snap.docs) d.id: d.data()});
      if (!snap.metadata.isFromCache) _listConfirmed = true;
    } catch (_) {}
  }

  /// users/{uid}/activity, at most once a day per phone (design §8.2):
  /// about four docs a show.
  Future<void> _readActivity(String uid) async {
    final today = _day(DateTime.now());
    if (_activity != null && _activityDay == today) return;
    try {
      final snap = await _userDoc(uid).collection('activity').get();
      if (_uid != uid) return;
      _activity = {for (final d in snap.docs) d.id: _date(d.data()['createdAt'])};
      _activityDay = today;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activityKey(uid), jsonEncode({
        'day': today,
        'docs': {
          for (final e in _activity!.entries) e.key: e.value?.millisecondsSinceEpoch,
        },
      }));
    } catch (_) {}
  }

  /// users/{uid}/cards, once ever (design §8.6): the cards that carry into
  /// the record. The rest stay where they are, unshown (decision e).
  Future<void> _readCards(String uid) async {
    if (_cards != null) return;
    try {
      final snap = await _userDoc(uid).collection('cards').get();
      if (_uid != uid) return;
      _cards = {
        for (final d in snap.docs)
          (d.data()['id'] is String ? d.data()['id'] as String : d.id):
              _date(d.data()['unlockedAt']),
      };
    } catch (_) {}
  }

  /// The tier lists on this device ("Ranked a cast"): this phone's only,
  /// since tier lists live only where they were made.
  Future<void> _readTierLists() async {
    try {
      final lists = await TierListStore.instance.loadAll();
      _tierLists = [
        for (final l in lists)
          TierListFact(id: l.id, createdAt: l.createdAt, ranked: l.rankedCount),
      ];
    } catch (_) {}
  }

  /// AniList's facts for every finished show (or only [these]), asked for
  /// only where unknown or due, then the rules again with them.
  Future<void> _lookUpFacts([List<int>? these]) async {
    final uid = _uid;
    final entries = _entries;
    if (uid == null || entries == null) return;
    final ids = these ??
        [
          for (final e in entries.entries)
            if (e.value['status'] == 'COMPLETED') ?int.tryParse(e.key),
        ];
    try {
      await MediaFacts.instance.lookUp(ids);
      final known = await MediaFacts.instance.known();
      if (_uid != uid) return;
      _facts = known;
    } catch (_) {
      return;
    }
    await _run(() => _evaluate());
  }

  // ── Evaluating and writing ──────────────────────────────────────────────

  /// Runs [job] after any evaluation already under way.
  Future<void> _run(Future<void> Function() job) {
    final done = _chain.then((_) => job());
    _chain = done.then((_) {}, onError: (_) {});
    return done.catchError((_) {});
  }

  Future<void> _evaluate() async {
    final uid = _uid;
    if (uid == null) return;
    await _loaded;
    final entries = _entries;
    if (entries == null || !_listConfirmed || _uid != uid) return;
    var record = _state.value.record;
    final dayOne = !record.started;

    if (dayOne) {
      // Day one is written once for good, so it waits for what it needs:
      // the server's word that no record exists yet, and the cards to
      // carry. Tried again at most once a minute while it can't be had.
      final tried = _dayOneTriedAt;
      final now = DateTime.now();
      if (tried != null && now.difference(tried) < const Duration(minutes: 1)) return;
      if (!_fromServer) await _readUser(uid);
      record = _state.value.record;
      if (!record.started) {
        if (_fromServer) await _readCards(uid);
        if (!_fromServer || _cards == null) {
          _dayOneTriedAt = now;
          return;
        }
        await _readActivity(uid);
      }
      if (_uid != uid) return;
    }

    final now = DateTime.now();
    _recent.removeWhere((_, at) => now.difference(at) > _liveWindow);
    final result = Achievements.evaluate(AchievementInputs(
      entries: entries,
      now: now,
      activity: _activity,
      facts: _facts,
      top9: _top9,
      top9At: _top9At,
      isFounder: _isFounder,
      founderNumber: _founderNumber,
      founderJoinedAt: _founderJoinedAt,
      tierLists: _tierLists,
      cards: record.cards ? null : _cards,
      live: _recent.keys.toSet(),
    ));

    final fresh = Achievements.newOnly(record.marks, result.marks)
      ..removeWhere((key, _) => _writing.contains(key));
    final starting = !record.started;
    final next = record.copyWith(
      since: starting ? now : null,
      seen: starting ? now : null,
      cards: _cards != null ? true : null,
      marks: fresh.isEmpty
          ? null
          : {...record.marks, for (final f in fresh.values) f.key: f.mark},
    );
    _publish(known: true, record: next, totals: result.totals, facts: result.factsComplete);
    if (fresh.isEmpty && !starting && next.cards == record.cards) return;
    await _saveLocal(uid);

    // Live earns: new marks decided by what you just did. Never day one.
    if (!starting) {
      final live = [
        for (final f in fresh.values)
          if (f.decidedBy != null && _recent.containsKey(f.decidedBy)) LiveEarn(f.key, f.mark),
      ]..sort((a, b) => (b.ref?.carving ?? 0).compareTo(a.ref?.carving ?? 0));
      if (live.isNotEmpty) _live.add(live);
    }

    unawaited(_write(uid, fresh, starting ? next : null, cardsNow: next.cards && !record.cards));
  }

  /// Writes only the new marks, as a merge that leaves every other mark as
  /// it is; day one writes the record whole, with `since`. Awaited and
  /// caught: an unhandled failure would reach Crashlytics as a fatal. A
  /// refused write takes its marks back off the phone's copy, so the next
  /// evaluation tries them again.
  Future<void> _write(String uid, Map<String, FoundMark> fresh, AchievementRecord? dayOne,
      {required bool cardsNow}) async {
    _writing.addAll(fresh.keys);
    Object stamp(DateTime at) => Timestamp.fromDate(at);
    final marks = {for (final f in fresh.values) f.key: f.mark.toMap(stamp)};
    try {
      await _userDoc(uid).set({
        'achievements': {
          if (dayOne != null) ...{
            'since': stamp(dayOne.since!),
            'seen': stamp(dayOne.seen!),
          },
          if (cardsNow) 'cards': true,
          if (marks.isNotEmpty) 'marks': marks,
        },
      }, SetOptions(merge: true));
    } catch (_) {
      if (_uid == uid) {
        final record = _state.value.record;
        _publish(
          record: dayOne != null
              ? AchievementRecord.empty
              : record.copyWith(marks: {
                  for (final e in record.marks.entries)
                    if (!fresh.containsKey(e.key)) e.key: e.value,
                }),
        );
        await _saveLocal(uid);
      }
    } finally {
      _writing.removeAll(fresh.keys);
    }
  }

  void _publish({
    bool? known,
    AchievementRecord? record,
    String? badge,
    bool clearBadge = false,
    AchievementTotals? totals,
    bool? facts,
  }) {
    final s = _state.value;
    final r = record ?? s.record;
    var b = clearBadge ? null : (badge ?? s.badge);
    // Only an earned mark is ever shown.
    if (b != null && !r.marks.containsKey(b)) b = null;
    _state.value = AchievementsState(
      uid: s.uid,
      known: known ?? s.known,
      record: r,
      badge: b,
      totals: totals ?? s.totals,
      factsComplete: facts ?? s.factsComplete,
    );
  }

  // ── The phone's copy ────────────────────────────────────────────────────

  static String _recordKey(String uid) => 'achievements_record_$uid';
  static String _activityKey(String uid) => 'achievements_activity_$uid';

  Future<void> _restoreLocal(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recordKey(uid));
      if (raw != null && _uid == uid && !_state.value.known) {
        final stored = jsonDecode(raw);
        if (stored is Map) {
          final record = _recordFrom(stored['record']);
          _publish(known: true, record: record, badge: _badgeFrom(stored['badge'], record));
        }
      }
      final activity = prefs.getString(_activityKey(uid));
      if (activity != null && _uid == uid && _activity == null) {
        final stored = jsonDecode(activity);
        final docs = stored is Map ? stored['docs'] : null;
        if (docs is Map) {
          _activity = {for (final e in docs.entries) '${e.key}': _date(e.value)};
          _activityDay = stored['day'] is String ? stored['day'] as String : null;
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLocal(String uid) async {
    if (_uid != uid) return;
    final s = _state.value;
    final r = s.record;
    int millis(DateTime at) => at.millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recordKey(uid), jsonEncode({
        'record': {
          'since': ?r.since?.millisecondsSinceEpoch,
          'seen': ?r.seen?.millisecondsSinceEpoch,
          if (r.cards) 'cards': true,
          'marks': {for (final m in r.marks.entries) m.key: m.value.toMap(millis)},
        },
        'badge': ?s.badge,
      }));
    } catch (_) {
      // The copy is an optimisation only: the user document is the record.
    }
  }

  // ── Reading stored shapes ───────────────────────────────────────────────

  /// The record from users/{uid}.achievements, or the phone's copy of it.
  static AchievementRecord _recordFrom(Object? stored) {
    if (stored is! Map) return AchievementRecord.empty;
    final marks = <String, RecordMark>{};
    final storedMarks = stored['marks'];
    if (storedMarks is Map) {
      for (final e in storedMarks.entries) {
        final mark = RecordMark.fromMap(e.value, _date);
        if (mark != null) marks['${e.key}'] = mark;
      }
    }
    return AchievementRecord(
      since: _date(stored['since']),
      seen: _date(stored['seen']),
      cards: stored['cards'] == true,
      marks: marks,
    );
  }

  /// users/{uid}.badge's mark, when it's one you've earned and may show
  /// (never Founder, even if a modified app wrote it).
  static String? _badgeFrom(Object? stored, AchievementRecord record) {
    final mark = stored is Map ? stored['mark'] : stored;
    return mark is String && record.marks.containsKey(mark) && canShow(mark)
        ? mark
        : null;
  }

  /// A Firestore document's fields with Timestamps as DateTimes, as the
  /// rules read them. A pending server timestamp is already null.
  static Map<String, Object?> _plain(Map<String, dynamic> data) => {
        for (final e in data.entries)
          e.key: e.value is Timestamp ? (e.value as Timestamp).toDate() : e.value,
      };

  static DateTime? _date(Object? value) => switch (value) {
        Timestamp() => value.toDate(),
        DateTime() => value,
        int() => DateTime.fromMillisecondsSinceEpoch(value),
        _ => null,
      };

  static String _day(DateTime at) => '${at.year}-${at.month}-${at.day}';

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);
}
