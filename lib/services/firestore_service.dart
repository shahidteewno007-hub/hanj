import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/anime_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference? get _animeListRef {
    if (_uid == null) return null;
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('animeList');
  }

  // ── Add or Update Anime in List ────────────────────────────
  Future<void> addAnimeToList({
    required Anime anime,
    required String status,
    double? rating,
    int? currentEpisode,
    String? notes,
    List<String>? tags,
  }) async {
    if (_animeListRef == null) return;

    final data = {
      'animeId':      anime.id,
      'title':        anime.titleEnglish ?? anime.title,
      'imageUrl':     anime.imageUrl,
      'episodes':     anime.episodes,
      'averageScore': anime.averageScore,
      'genres':       anime.genres,
      'status':       status,
      'addedAt':      FieldValue.serverTimestamp(),
      'lastWatched':  FieldValue.serverTimestamp(),
    };

    if (rating != null) data['userRating'] = rating;
    if (currentEpisode != null) data['currentEpisode'] = currentEpisode;
    if (notes != null) data['notes'] = notes;
    if (tags != null) data['tags'] = tags;

    await _animeListRef!.doc(anime.id.toString()).set(data, SetOptions(merge: true));

    // Write activity event
    await writeActivity(
      type: status,
      animeId: anime.id,
      animeTitle: anime.titleEnglish ?? anime.title,
      imageUrl: anime.imageUrl,
      status: status,
    );
  }

  // ── Update Rating ──────────────────────────────────────────
  Future<void> updateRating(int animeId, double rating) async {
    if (_animeListRef == null) return;
    await _animeListRef!.doc(animeId.toString()).update({
      'userRating': rating,
      'ratedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Update Episode Progress ────────────────────────────────
  Future<void> updateEpisodeProgress(int animeId, int currentEpisode) async {
    if (_animeListRef == null) return;
    await _animeListRef!.doc(animeId.toString()).update({
      'currentEpisode': currentEpisode,
      'lastWatched': FieldValue.serverTimestamp(),
    });
  }

  // ── Update Notes ───────────────────────────────────────────
  Future<void> updateNotes(int animeId, String notes) async {
    if (_animeListRef == null) return;
    await _animeListRef!.doc(animeId.toString()).update({
      'notes': notes,
      'notesUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Update Tags ────────────────────────────────────────────
  Future<void> updateTags(int animeId, List<String> tags) async {
    if (_animeListRef == null) return;
    await _animeListRef!.doc(animeId.toString()).update({
      'tags': tags,
      'tagsUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Remove Anime from List ─────────────────────────────────
  Future<void> removeAnimeFromList(int animeId) async {
    if (_animeListRef == null) return;
    await _animeListRef!.doc(animeId.toString()).delete();
  }

  // ── Get All Anime in User's List ───────────────────────────
  Stream<QuerySnapshot> getAnimeList() {
    if (_animeListRef == null) {
      return const Stream.empty();
    }
    return _animeListRef!.orderBy('addedAt', descending: true).snapshots();
  }

  // ── Get Anime by Status ────────────────────────────────────
  Stream<QuerySnapshot> getAnimeByStatus(String status) {
    if (_animeListRef == null) {
      return const Stream.empty();
    }
    return _animeListRef!
        .where('status', isEqualTo: status)
        .snapshots();
  }

  // ── Get Anime by Tag ───────────────────────────────────────
  Stream<QuerySnapshot> getAnimeByTag(String tag) {
    if (_animeListRef == null) {
      return const Stream.empty();
    }
    return _animeListRef!
        .where('tags', arrayContains: tag)
        .snapshots();
  }

  // ── Check if Anime is in List ──────────────────────────────
  Future<String?> getAnimeStatus(int animeId) async {
    if (_animeListRef == null) return null;
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      return (doc.data() as Map<String, dynamic>)['status'] as String?;
    }
    return null;
  }

  // ── Get User Rating ────────────────────────────────────────
  Future<double?> getUserRating(int animeId) async {
    if (_animeListRef == null) return null;
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['userRating'] as num?)?.toDouble();
    }
    return null;
  }

  // ── Get Episode Progress ───────────────────────────────────
  Future<int?> getEpisodeProgress(int animeId) async {
    if (_animeListRef == null) return null;
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return data['currentEpisode'] as int?;
    }
    return null;
  }

  // ── Get Notes ──────────────────────────────────────────────
  Future<String?> getNotes(int animeId) async {
    if (_animeListRef == null) return null;
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return data['notes'] as String?;
    }
    return null;
  }

  // ── Get Tags ───────────────────────────────────────────────
  Future<List<String>> getTags(int animeId) async {
    if (_animeListRef == null) return [];
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    }
    return [];
  }

  // ── Get All User Tags ──────────────────────────────────────
  Future<Set<String>> getAllUserTags() async {
    if (_animeListRef == null) return {};
    final snapshot = await _animeListRef!.get();
    final allTags = <String>{};
    
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final tags = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
      allTags.addAll(tags);
    }
    
    return allTags;
  }

  // ── Get Anime Details ──────────────────────────────────────
  Future<Map<String, dynamic>?> getAnimeDetails(int animeId) async {
    if (_animeListRef == null) return null;
    final doc = await _animeListRef!.doc(animeId.toString()).get();
    if (doc.exists) {
      return doc.data() as Map<String, dynamic>;
    }
    return null;
  }

  // ── Get Stats ──────────────────────────────────────────────
  Future<Map<String, dynamic>> getStats() async {
    if (_animeListRef == null) {
      return {
        'totalAnime': 0,
        'completionRate': 0.0,
        'averageRating': 0.0,
        'totalEpisodes': 0,
      };
    }

    final snapshot = await _animeListRef!.get();
    int totalAnime = snapshot.docs.length;
    int completed = 0;
    double totalRating = 0;
    int ratedCount = 0;
    int totalEpisodes = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      
      if (data['status'] == 'COMPLETED') completed++;
      
      if (data['userRating'] != null) {
        totalRating += (data['userRating'] as num).toDouble();
        ratedCount++;
      }

      if (data['status'] == 'COMPLETED' && data['episodes'] != null) {
        totalEpisodes += (data['episodes'] as int);
      } else if (data['currentEpisode'] != null) {
        totalEpisodes += (data['currentEpisode'] as int);
      }
    }

    return {
      'totalAnime': totalAnime,
      'completionRate': totalAnime > 0 ? (completed / totalAnime * 100) : 0.0,
      'averageRating': ratedCount > 0 ? (totalRating / ratedCount) : 0.0,
      'totalEpisodes': totalEpisodes,
    };
  }

  // ── Write Activity Event ───────────────────────────────────
  Future<void> writeActivity({
    required String type,     // 'WATCHING', 'COMPLETED', 'RATED', 'DROPPED', 'PLAN_TO_WATCH'
    required String animeId,
    required String animeTitle,
    String? imageUrl,
    double? rating,
    String? status,
  }) async {
    if (_uid == null) return;
    // Deterministic id so the same action on the same anime updates a single
    // doc instead of creating duplicates every time status is re-confirmed.
    final docId = '${type}_$animeId';
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('activity')
        .doc(docId)
        .set({
      'type': type,
      'animeId': animeId,
      'animeTitle': animeTitle,
      'imageUrl': imageUrl,
      'rating': rating,
      'status': status,
      'uid': _uid,
      'displayName': _auth.currentUser?.displayName ?? 'Anime Fan',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Get My Activity Feed ───────────────────────────────────
  Stream<QuerySnapshot> getMyActivity({int limit = 20}) {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('activity')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Get Activity Feed for a User ───────────────────────────
  Stream<QuerySnapshot> getUserActivity(String uid, {int limit = 20}) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('activity')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ── Get Following List ─────────────────────────────────────
  Future<List<String>> getFollowing() async {
    if (_uid == null) return [];
    final doc = await _firestore.collection('users').doc(_uid).get();
    if (!doc.exists) return [];
    final data = doc.data() as Map<String, dynamic>;
    return (data['following'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  // ── Get Friends Activity Feed (merged) ─────────────────────
  Future<List<Map<String, dynamic>>> getFriendsActivity({int limit = 30}) async {
    if (_uid == null) return [];
    final following = await getFollowing();
    // Friends feed = people you follow only (NOT your own activity —
    // that lives on the "My Activity" tab).
    final uids = following.where((u) => u != _uid).toList();
    if (uids.isEmpty) return [];

    final List<Map<String, dynamic>> allActivity = [];
    for (final uid in uids) {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('activity')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['uid'] = uid;
        allActivity.add(data);
      }
    }

    // Sort by createdAt
    allActivity.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return allActivity.take(limit).toList();
  }

  // ── Import Pending ─────────────────────────────────────────
  Future<bool> getImportPending() async {
    if (_uid == null) return false;
    final doc = await _firestore.collection('users').doc(_uid).get();
    if (!doc.exists) return false;
    final data = doc.data() as Map<String, dynamic>;
    return data['importPending'] == true;
  }

  Future<void> dismissImportBanner() async {
    if (_uid == null) return;
    await _firestore.collection('users').doc(_uid).set(
      {'importPending': false},
      SetOptions(merge: true),
    );
  }

  // ── Get Wrapped Data for a Year ────────────────────────────
  Future<Map<String, dynamic>> getWrappedData(int year) async {
    if (_animeListRef == null) return {};

    final snapshot = await _animeListRef!.get();
    final docs = snapshot.docs;

    int completedThisYear = 0;
    int totalEpisodesThisYear = 0;
    double totalRating = 0;
    int ratedCount = 0;
    Map<String, int> genreCounts = {};
    Map<String, int> studioCount = {};
    Map<String, int> monthlyCount = {};
    String? topAnimeTitle;
    double topAnimeRating = 0;
    String? topAnimeImage;
    List<Map<String, dynamic>> completedAnime = [];

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final addedAt = (data['addedAt'] as Timestamp?)?.toDate();
      if (addedAt == null || addedAt.year != year) continue;

      if (data['status'] == 'COMPLETED') {
        completedThisYear++;
        final eps = data['episodes'] as int? ?? 0;
        totalEpisodesThisYear += eps;
        completedAnime.add(data);

        // Month tracking
        final month = addedAt.month.toString().padLeft(2, '0');
        monthlyCount[month] = (monthlyCount[month] ?? 0) + 1;
      }

      if (data['userRating'] != null) {
        final r = (data['userRating'] as num).toDouble();
        totalRating += r;
        ratedCount++;
        if (r > topAnimeRating) {
          topAnimeRating = r;
          topAnimeTitle = data['title'] as String?;
          topAnimeImage = data['imageUrl'] as String?;
        }
      }

      final genres = data['genres'] as List<dynamic>?;
      if (genres != null) {
        for (final g in genres) {
          genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        }
      }
    }

    final topGenres = (genreCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .map((e) => e.key)
        .toList();

    final watchTimeHours = (totalEpisodesThisYear * 24 / 60).round();

    // Sort so highest-rated anime appears first (used by Top Series page)
    completedAnime.sort((a, b) {
      final aR = (a['userRating'] as num?)?.toDouble() ?? 0;
      final bR = (b['userRating'] as num?)?.toDouble() ?? 0;
      return bR.compareTo(aR);
    });

    return {
      'year': year,
      'completedCount': completedThisYear,
      'totalEpisodes': totalEpisodesThisYear,
      'watchTimeHours': watchTimeHours,
      'averageRating': ratedCount > 0 ? (totalRating / ratedCount) : 0.0,
      'topGenres': topGenres,
      'genreCounts': genreCounts,
      'topAnimeTitle': topAnimeTitle,
      'topAnimeRating': topAnimeRating,
      'topAnimeImage': topAnimeImage,
      'monthlyCount': monthlyCount,
      'completedAnime': completedAnime,
    };
  }
}