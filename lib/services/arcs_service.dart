import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────
// Arcs: watch-alongs (arcs redesign, 2026-11-14)
//
// An arc is people watching one show, or one stretch of it, together: a
// few episodes a week, one stop a week. The data lives where the gated
// arcs_screen.dart already put it (`arcs`, `posts`, `replies`), with a few
// fields added: `v: 2`, `anime`, `from`, `to`, `pace`, `startsOn` on the arc
// and `ep` on a post. Older arcs without them still read (show == null).
//
// No AniList calls: a show comes from the user's own list or from the
// Detail page it was started on.
//
// Every counter moves in the same batch as the document it counts, and
// names it (`countedPost`, `countedReply`), so firestore.rules can check
// that the document really appears or disappears in that batch. Until those
// rules are deployed, writes may be denied; every write here is awaited and
// caught, and comes back as an [ArcsFailure] the screen can show.
// ─────────────────────────────────────────────────────────────

/// Text limits, the same as firestore.rules enforces.
class ArcLimits {
  static const int name = 60;
  static const int about = 300;
  static const int title = 120;
  static const int body = 2000;
  static const int reply = 1000;
}

/// The show an arc watches.
class ArcShow {
  const ArcShow({
    required this.id,
    required this.title,
    this.cover,
    this.episodes,
  });

  final String id;
  final String title;
  final String? cover;

  /// The show's episode count, when known.
  final int? episodes;

  static ArcShow? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id == null || title is! String) return null;
    return ArcShow(
      id: '$id',
      title: title,
      cover: raw['cover'] as String?,
      episodes: (raw['episodes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cover': cover,
        'episodes': episodes,
      };
}

/// One week of an arc: the episodes it covers and the day it opens.
class ArcStop {
  const ArcStop({
    required this.index,
    required this.first,
    required this.last,
    required this.opens,
  });

  final int index;
  final int first;
  final int last;
  final DateTime opens;

  String get episodes => first == last ? '$first' : '$first–$last';

  bool holds(int ep) => ep >= first && ep <= last;
}

/// Where an arc's schedule stands on a given day.
enum ArcPhase { starting, running, finished }

class Arc {
  const Arc({
    required this.id,
    required this.name,
    required this.description,
    required this.show,
    required this.from,
    required this.to,
    required this.pace,
    required this.startsOn,
    required this.members,
    required this.memberCount,
    required this.postCount,
    required this.createdBy,
    required this.creatorName,
  });

  final String id;
  final String name;
  final String description;

  /// Null for an arc from before the redesign.
  final ArcShow? show;
  final int from;
  final int to;
  final int pace;

  /// Midnight of the first stop's day. Null for an arc from before the
  /// redesign.
  final DateTime? startsOn;
  final List<String> members;
  final int memberCount;
  final int postCount;
  final String createdBy;
  final String creatorName;

  factory Arc.fromDoc(String id, Map<String, dynamic> d) {
    final from = (d['from'] as num?)?.toInt() ?? 1;
    final to = (d['to'] as num?)?.toInt() ?? from;
    return Arc(
      id: id,
      name: d['name'] as String? ?? 'Unnamed arc',
      description: d['description'] as String? ?? '',
      show: ArcShow.fromMap(d['anime']),
      from: from,
      to: math.max(from, to),
      pace: math.max(1, (d['pace'] as num?)?.toInt() ?? 1),
      startsOn: (d['startsOn'] as Timestamp?)?.toDate(),
      members: ((d['members'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toList(),
      memberCount: (d['memberCount'] as num?)?.toInt() ?? 0,
      postCount: (d['postCount'] as num?)?.toInt() ?? 0,
      createdBy: d['createdBy'] as String? ?? '',
      creatorName: d['creatorName'] as String? ?? '',
    );
  }

  /// A watch-along with a show and a schedule (the redesign's shape).
  bool get scheduled => show != null && startsOn != null;

  bool hasMember(String? uid) => uid != null && members.contains(uid);

  int get stopCount => ((to - from + 1) / pace).ceil();

  ArcStop stop(int i) {
    final first = from + i * pace;
    final start = startsOn ?? DateTime(2000);
    return ArcStop(
      index: i,
      first: first,
      last: math.min(to, first + pace - 1),
      opens: DateTime(start.year, start.month, start.day + 7 * i),
    );
  }

  List<ArcStop> get stops => [for (var i = 0; i < stopCount; i++) stop(i)];

  /// The stop open on [now]'s day: -1 before the start, [stopCount] after the
  /// last stop's week.
  int stopOn(DateTime now) {
    final start = startsOn;
    if (start == null) return -1;
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(start).inDays;
    if (days < 0) return -1;
    return math.min(stopCount, days ~/ 7);
  }

  ArcPhase phaseOn(DateTime now) {
    final i = stopOn(now);
    if (i < 0) return ArcPhase.starting;
    if (i >= stopCount) return ArcPhase.finished;
    return ArcPhase.running;
  }

  /// The day after the last stop's week.
  DateTime get endsOn {
    final start = startsOn ?? DateTime(2000);
    return DateTime(start.year, start.month, start.day + 7 * stopCount);
  }
}

class ArcPost {
  const ArcPost({
    required this.id,
    required this.title,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.likes,
    required this.likeCount,
    required this.replyCount,
    required this.createdAt,
    required this.ep,
  });

  final String id;
  final String title;
  final String body;
  final String authorId;
  final String authorName;
  final List<String> likes;
  final int likeCount;
  final int replyCount;
  final DateTime? createdAt;

  /// The episode the post talks about. Null for a post from before the
  /// redesign; such a post is never sealed.
  final int? ep;

  factory ArcPost.fromDoc(String id, Map<String, dynamic> d) => ArcPost(
        id: id,
        title: d['title'] as String? ?? '',
        body: d['body'] as String? ?? '',
        authorId: d['authorId'] as String? ?? '',
        authorName: d['authorName'] as String? ?? 'Anonymous',
        likes: ((d['likes'] as List<dynamic>?) ?? const [])
            .whereType<String>()
            .toList(),
        likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
        replyCount: (d['replyCount'] as num?)?.toInt() ?? 0,
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
        ep: (d['ep'] as num?)?.toInt(),
      );

  /// Sealed for a reader on episode [progress]: tagged past it, and not
  /// theirs.
  bool sealedFor(String? uid, int progress) =>
      ep != null && ep! > progress && authorId != uid;
}

class ArcReply {
  const ArcReply({
    required this.id,
    required this.body,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
  });

  final String id;
  final String body;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;

  factory ArcReply.fromDoc(String id, Map<String, dynamic> d) => ArcReply(
        id: id,
        body: d['body'] as String? ?? '',
        authorId: d['authorId'] as String? ?? '',
        authorName: d['authorName'] as String? ?? 'Anonymous',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// A show on the user's own list, as the start sheet offers it.
class ArcListEntry {
  const ArcListEntry({
    required this.show,
    required this.status,
    required this.progress,
  });

  final ArcShow show;
  final String status;
  final int progress;
}

/// A write that didn't happen, in words a screen can show.
class ArcsFailure implements Exception {
  const ArcsFailure(this.message, {this.denied = false});

  final String message;

  /// The server's rules refused it (rules not deployed yet, or not allowed).
  final bool denied;

  @override
  String toString() => message;
}

class ArcsService {
  ArcsService._();
  static final ArcsService instance = ArcsService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _arcs =>
      _db.collection('arcs');

  DocumentReference<Map<String, dynamic>> _arc(String arcId) =>
      _arcs.doc(arcId);

  CollectionReference<Map<String, dynamic>> _posts(String arcId) =>
      _arc(arcId).collection('posts');

  CollectionReference<Map<String, dynamic>> _replies(
          String arcId, String postId) =>
      _posts(arcId).doc(postId).collection('replies');

  // ── Reads ──────────────────────────────────────────────────

  List<Arc> _arcList(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) Arc.fromDoc(d.id, d.data())];

  /// Every arc, most members first.
  Stream<List<Arc>> running() => _arcs
      .orderBy('memberCount', descending: true)
      .limit(30)
      .snapshots()
      .map(_arcList);

  /// The arcs [uid] has joined.
  Stream<List<Arc>> mine(String uid) => _arcs
      .where('members', arrayContains: uid)
      .limit(30)
      .snapshots()
      .map(_arcList);

  /// The arcs watching one show.
  Stream<List<Arc>> forShow(String animeId) => _arcs
      .where('anime.id', isEqualTo: animeId)
      .limit(10)
      .snapshots()
      .map(_arcList);

  Stream<Arc?> arc(String arcId) => _arc(arcId).snapshots().map(
      (d) => d.exists ? Arc.fromDoc(d.id, d.data() ?? const {}) : null);

  Stream<List<ArcPost>> posts(String arcId) => _posts(arcId)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => [for (final d in s.docs) ArcPost.fromDoc(d.id, d.data())]);

  Stream<ArcPost?> post(String arcId, String postId) =>
      _posts(arcId).doc(postId).snapshots().map((d) =>
          d.exists ? ArcPost.fromDoc(d.id, d.data() ?? const {}) : null);

  Stream<List<ArcReply>> replies(String arcId, String postId) =>
      _replies(arcId, postId)
          .orderBy('createdAt')
          .limit(200)
          .snapshots()
          .map((s) =>
              [for (final d in s.docs) ArcReply.fromDoc(d.id, d.data())]);

  /// How far [uid] has watched [animeId], from their own list: the episode
  /// they're on, every episode once completed, 0 when it isn't on the list
  /// or can't be read.
  Future<int> progress(String uid, String animeId) async {
    try {
      final d = await _db
          .collection('users')
          .doc(uid)
          .collection('animeList')
          .doc(animeId)
          .get();
      final data = d.data();
      if (data == null) return 0;
      if (data['status'] == 'COMPLETED') {
        return (data['episodes'] as num?)?.toInt() ?? 1 << 20;
      }
      return (data['currentEpisode'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The shows on [uid]'s list, watching first, then planned, then the rest.
  Future<List<ArcListEntry>> listShows(String uid) async {
    final QuerySnapshot<Map<String, dynamic>> s;
    try {
      s = await _db
          .collection('users')
          .doc(uid)
          .collection('animeList')
          .limit(300)
          .get();
    } on FirebaseException catch (e) {
      throw _failure(e, 'Couldn\'t read your list');
    }
    const order = ['WATCHING', 'PLAN_TO_WATCH', 'COMPLETED', 'DROPPED'];
    final out = <ArcListEntry>[];
    for (final d in s.docs) {
      final data = d.data();
      final title = data['title'];
      if (title is! String || title.isEmpty) continue;
      out.add(ArcListEntry(
        show: ArcShow(
          id: '${data['animeId'] ?? d.id}',
          title: title,
          cover: data['imageUrl'] as String?,
          episodes: (data['episodes'] as num?)?.toInt(),
        ),
        status: data['status'] as String? ?? '',
        progress: (data['currentEpisode'] as num?)?.toInt() ?? 0,
      ));
    }
    int rank(String s) {
      final i = order.indexOf(s);
      return i < 0 ? order.length : i;
    }

    out.sort((a, b) {
      final r = rank(a.status).compareTo(rank(b.status));
      return r != 0
          ? r
          : a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase());
    });
    return out;
  }

  Future<String> _myName(String uid) async {
    try {
      final d = await _db.collection('users').doc(uid).get();
      final name = d.data()?['displayName'] as String?;
      return (name == null || name.trim().isEmpty) ? 'Anonymous' : name;
    } catch (_) {
      return 'Anonymous';
    }
  }

  // ── Writes ─────────────────────────────────────────────────

  ArcsFailure _failure(Object e, String what) {
    if (e is ArcsFailure) return e;
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return ArcsFailure('$what: Arcs can\'t save this yet', denied: true);
      }
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        return ArcsFailure('$what: you\'re offline');
      }
    }
    return ArcsFailure('$what: something went wrong');
  }

  /// Starts an arc and returns its id. The maker is its first member.
  Future<String> create({
    required String uid,
    required ArcShow show,
    required String name,
    required String description,
    required int from,
    required int to,
    required int pace,
    required DateTime startsOn,
  }) async {
    final ref = _arcs.doc();
    try {
      final creator = await _myName(uid);
      await ref.set({
        'v': 2,
        'name': name.trim(),
        'description': description.trim(),
        'anime': show.toMap(),
        'from': from,
        'to': to,
        'pace': pace,
        'startsOn': Timestamp.fromDate(
            DateTime(startsOn.year, startsOn.month, startsOn.day)),
        'createdBy': uid,
        'creatorName': creator,
        'members': [uid],
        'memberCount': 1,
        'postCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } catch (e) {
      throw _failure(e, 'Couldn\'t start the arc');
    }
  }

  /// Joins or leaves, deciding from the arc as the server holds it, so a
  /// stale screen or a double tap can't send a move the rules refuse.
  Future<void> setMember(String arcId, String uid, {required bool join}) async {
    final ref = _arc(arcId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() ?? const <String, dynamic>{};
        final members = List<dynamic>.from(d['members'] as List? ?? const []);
        final count = (d['memberCount'] as num?)?.toInt() ?? members.length;
        final isIn = members.contains(uid);
        if (isIn == join) return;
        tx.update(ref, {
          'members': join
              ? [...members, uid]
              : (members..removeWhere((e) => e == uid)),
          'memberCount': join ? count + 1 : count - 1,
        });
      });
    } catch (e) {
      throw _failure(e, join ? 'Couldn\'t join' : 'Couldn\'t leave');
    }
  }

  /// Posts to an arc, and counts it in the same batch.
  Future<void> addPost({
    required String arcId,
    required String uid,
    required String title,
    required String body,
    required int ep,
  }) async {
    final ref = _posts(arcId).doc();
    try {
      final name = await _myName(uid);
      final batch = _db.batch()
        ..set(ref, {
          'title': title.trim(),
          'body': body.trim(),
          'ep': ep,
          'authorId': uid,
          'authorName': name,
          'likes': <String>[],
          'likeCount': 0,
          'replyCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        })
        ..update(_arc(arcId), {
          'postCount': FieldValue.increment(1),
          'countedPost': ref.id,
        });
      await batch.commit();
    } catch (e) {
      throw _failure(e, 'Couldn\'t post');
    }
  }

  Future<void> deletePost(String arcId, String postId) async {
    try {
      final batch = _db.batch()
        ..delete(_posts(arcId).doc(postId))
        ..update(_arc(arcId), {
          'postCount': FieldValue.increment(-1),
          'countedPost': postId,
        });
      await batch.commit();
    } catch (e) {
      throw _failure(e, 'Couldn\'t delete');
    }
  }

  /// Replies to a post, and counts it in the same batch.
  Future<void> addReply({
    required String arcId,
    required String postId,
    required String uid,
    required String body,
  }) async {
    final ref = _replies(arcId, postId).doc();
    try {
      final name = await _myName(uid);
      final batch = _db.batch()
        ..set(ref, {
          'body': body.trim(),
          'authorId': uid,
          'authorName': name,
          'likes': <String>[],
          'likeCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
        })
        ..update(_posts(arcId).doc(postId), {
          'replyCount': FieldValue.increment(1),
          'countedReply': ref.id,
        });
      await batch.commit();
    } catch (e) {
      throw _failure(e, 'Couldn\'t reply');
    }
  }

  Future<void> deleteReply(String arcId, String postId, String replyId) async {
    try {
      final batch = _db.batch()
        ..delete(_replies(arcId, postId).doc(replyId))
        ..update(_posts(arcId).doc(postId), {
          'replyCount': FieldValue.increment(-1),
          'countedReply': replyId,
        });
      await batch.commit();
    } catch (e) {
      throw _failure(e, 'Couldn\'t delete');
    }
  }

  /// Likes or unlikes a post, deciding from the post as the server holds it
  /// (the S3-4 fix in arcs_screen.dart's _toggleLike, reused).
  Future<void> toggleLike(String arcId, String postId, String uid) async {
    final ref = _posts(arcId).doc(postId);
    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final d = snap.data() ?? const <String, dynamic>{};
        final likes = List<dynamic>.from(d['likes'] as List? ?? const []);
        final count = (d['likeCount'] as num?)?.toInt() ?? 0;
        final liked = likes.contains(uid);
        tx.update(ref, {
          'likes': liked ? (likes..removeWhere((e) => e == uid)) : [...likes, uid],
          'likeCount': liked ? count - 1 : count + 1,
        });
      });
    } catch (e) {
      throw _failure(e, 'Couldn\'t like');
    }
  }

  /// Reports a post or reply by its path. Reports are create-only: nobody
  /// reads them in the app; they're read in the Firebase console.
  Future<void> report({
    required String uid,
    required String path,
    required String reason,
  }) async {
    try {
      await _db.collection('reports').add({
        'reporter': uid,
        'path': path,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw _failure(e, 'Couldn\'t report');
    }
  }

  static String postPath(String arcId, String postId) =>
      'arcs/$arcId/posts/$postId';

  static String replyPath(String arcId, String postId, String replyId) =>
      'arcs/$arcId/posts/$postId/replies/$replyId';
}
