import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

import '../../core/theme/app_theme.dart';
import '../../widgets/anilist_saved_note.dart';
import '../../widgets/hanko_cover_colour.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_flight.dart';
import '../../widgets/hanko_print.dart';
import '../../widgets/hanko_reel.dart';
import '../../widgets/hanko_seal.dart';
import '../../core/responsive.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../services/offline_cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../models/anime_model.dart';
import '../../models/hanj_shelves.dart';
import '../../models/achievements.dart' show Achievements;
import '../../services/achievements_service.dart';
import '../achievements/achievements_screen.dart' show AchievementSlip;
import '../anime_detail/anime_detail_screen.dart';
import 'tonight_watch.dart';
import 'upcoming_anime.dart';
import '../calendar/anime_calendar_screen.dart';
import '../discovery/discovery_screen.dart';
import '../my_list/my_list_screen.dart';
import '../import/anilist_import_screen.dart';
import '../search/search_screen.dart';
import '../companion/tomo_screen.dart';
import '../companion/tomo_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _aniListService = AnilistService();
  final _firestoreService = FirestoreService();

  List<Anime> _seasonAnime = []; // Popular this season (was the trending list)
  List<Map<String, dynamic>> _continueWatching = [];
  List<Map<String, dynamic>> _planToWatch = [];
  List<Map<String, dynamic>> _entries = []; // the whole list, for the lede
  bool _listFailed = false; // the list couldn't be read: say so, with Retry
  Set<String> _reminderIds = {}; // persisted reminder animeIds
  Anime? _animeOfDay;
  List<Map<String, dynamic>> _recommendationRows = [];
  bool _isLoading = true;
  bool _isFromCache = false;
  bool _importPending = false;

  // ── Up next is hidden (question 45) ────────────────────────
  // Its strip of your watchlist repeated tonight's watchlist pick, a few
  // rows above it. The pick now ends with "See your watchlist (N)", which
  // opens the same filter Up next's "SEE ALL" did. The block is kept intact
  // in build(); don't set this to true while the pick shows the same list.
  static const bool _showUpNext = false;

  // "Because you loved" draws Hanko's poster strip (question 46). The
  // classic 140 px cards (_TrendingCard), with their rank and coral NEW
  // badges, are kept intact and switched off here.
  static const bool _classicRecs = false;

  // ── Print Room, stage P2 (DESIGN.md §9; Shahid chose it 2026-11-03) ──
  // Home in prints (§9.5, frame 02): the hero show's colour field from the
  // top of Home, its print beside the lede with your seal pressed on it;
  // Continue as a shelf of prints on mats of their own colour; and
  // tonight's pick on a band of its colour. Round seven's Home (the lede's
  // inline seal, the Continue rows and the art wash) is kept intact behind
  // this switch.
  static const bool _printRoom = true;

  /// The lede's size beside the hero print: 20, the mockup's, from 22, so
  /// the sentence keeps its words in the width the print leaves it.
  static const double _ledeBesidePrint = 20;

  /// A short title is kept whole only where it fits on a line (after P7's
  /// phone check, 2026-11-06). Kept whole and wider than the line, it was
  /// broken inside a word beside the print: "Today you sealed / Sparks of
  /// Tomorro / w" at 360 dp. Now it breaks between its words instead, as a
  /// long title does. False gives back the 18-character rule alone.
  static const bool _titleMustFit = true;

  // ── Start watching, on the watchlist band (Print Room P2-2) ──
  // The mockup's washi button under tonight's pick, built as a stage of its
  // own (Shahid, 2026-11-05: "go with your recommendations"). It puts the
  // pick on Watching, as the status sheet's "Watching" does, so the show
  // moves onto the Continue shelf. Off, the band is P2's as built.
  static const bool _startWatching = true;

  // ── Shelf to page (Print Room P6; DESIGN.md §9.3 A rule 5) ──
  // The print you tap flies into Detail's print as one Hero, and Detail
  // fades in over Home in the show's colour, which Home's mat or field has
  // already read, so it's there from the first frame (HankoFlightRoute,
  // 320 ms; instant with Remove animations on). From every print on Home:
  // Continue's shelf, the hero and the band. Off, each opens Detail with the
  // push it always had (MaterialPageRoute).
  static const bool _flight = true;

  /// A print's Hero tag on Home (P6): its place and its show, since one show
  /// can lie in two places at once (the hero's fallback is the shelf's first
  /// show). Null, no Hero, with the flight off.
  static Object? _printTag(String place, String id) =>
      _flight && _printRoom && id.isNotEmpty ? (place, id) : null;

  /// The route that opens [anime] from its print at [place] (P6): the flight,
  /// with the colour the place showed, read from the same cover; with the
  /// flight off, the push.
  static Route<void> _showRoute(BuildContext context, Anime anime,
      {required String place}) {
    final tag = _printTag(place, anime.id);
    if (tag == null) {
      return MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime));
    }
    final url = anime.imageUrl ?? '';
    final flight = HankoFlight(
      tag: tag,
      colour: url.isEmpty ? null : HankoCoverColour.peek(url),
    );
    return HankoFlightRoute(
      still: MediaQuery.disableAnimationsOf(context),
      builder: (_) => AnimeDetailScreen(anime: anime, flight: flight),
    );
  }

  /// The pick's Watching write is on its way: the button says so.
  bool _starting = false;

  /// Puts [entry] on Watching through the same write as the status sheet's
  /// "Watching" (FirestoreService.addAnimeToList: a merge of the status, its
  /// addedAt and lastWatched, and the entry's own facts, with the activity
  /// event), so nothing else on the entry changes. Awaited and caught: a
  /// refused write says so, and the list is read again either way, which
  /// moves the show onto the shelf, or leaves it on the band.
  Future<void> _start(Map<String, dynamic> entry) async {
    final id = entry['animeId']?.toString() ?? '';
    if (_starting || id.isEmpty) return;
    setState(() => _starting = true);
    try {
      await _firestoreService.addAnimeToList(
        anime: Anime(
          id: id,
          title: entry['title'] as String? ?? 'Unknown',
          imageUrl: entry['imageUrl'] as String?,
          episodes: entry['episodes'] as int?,
          averageScore: (entry['averageScore'] as num?)?.toDouble(),
          genres: [
            ...?(entry['genres'] as List<dynamic>?)?.whereType<String>(),
          ],
        ),
        status: 'WATCHING',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Couldn’t start it just now. Try again.'),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        _reloadList();
      }
    }
  }

  // ── The airing batch, lifted out of Coming up (Stage 2 item a) ──
  // One AniList request for every show you're watching: its next episode
  // and when it airs. Coming up lists the soonest three, and each Continue
  // row's reel shows the episodes that have aired since yours. Still one
  // request, sent on Home's first load, and again only when a show joins
  // Watching or the last one failed and you pull to refresh.
  Map<int, Map<String, dynamic>> _airing = {};
  Set<int> _airingAsked = {};
  bool _airingLoading = true;
  bool _airingFailed = false;
  int _airingRun = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    // No setState(_isLoading = true) here. _isLoading starts true, so the
    // first load still shows the spinner; a later call (pull-to-refresh, or
    // a Continue card completing a show) updates Home in place instead of
    // blanking the whole screen and rebuilding every section from scratch.

    final isOnline = ConnectivityService.instance.isOnline;

    // The chart loads beside your list, never in front of it (D19). It used
    // to be awaited first, so on a cold start whose saved copy was over an
    // hour old, the headline, Continue and the watchlist waited for AniList
    // to answer or time out (15 s per attempt). Not awaited: it sets its
    // own state when it lands.
    _loadChart();

    try {
      // Firestore — has built-in offline persistence, so these still work offline
      final results = await Future.wait([
        _readList(watchingOnly: true),
        _readList(),
      ]);

      final importPending = await _firestoreService.getImportPending();

      if (!mounted) return;

      final userSnapshot = results[1];

      // Offline with nothing on the device, the list arrives empty from the
      // cache, which can't tell "no list" from "no copy". Say it couldn't
      // load rather than greet someone with a list as a newcomer.
      if (userSnapshot.metadata.isFromCache &&
          userSnapshot.docs.isEmpty &&
          !ConnectivityService.instance.isOnline) {
        throw StateError('No copy of the list on this device');
      }

      final lists = _sortList(results[0], userSnapshot);

      // Load reminders
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final remSnap = await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('alerts')
              .get();
          _reminderIds = remSnap.docs.map((d) => d.id).toSet();
        } catch (_) {}
      }

      if (!mounted) return;
      // ── Render immediately with cached + Firestore data ──────────
      // Recommendations are fetched separately so a throttled AniList
      // call never blocks the whole screen from showing.
      setState(() {
        _continueWatching = lists.watching;
        _planToWatch = lists.planned;
        _entries = lists.entries;
        _listFailed = false;
        _isLoading = false;
        _isFromCache = !isOnline;
        _importPending = importPending;
      });
      _precacheLede();

      // Fire recommendations in the background (non-blocking)
      if (isOnline && userSnapshot.docs.isNotEmpty) {
        _loadRecommendations(userSnapshot);
      }
      _loadAiring(retryFailed: true);
      _feedAchievements(userSnapshot);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isFromCache = !isOnline;
        _airingLoading = false; // no list, so no batch to wait for
        // Only a list Home never managed to read is an error; a failed
        // refresh keeps what is on screen.
        if (_entries.isEmpty) _listFailed = true;
      });
    }
  }

  /// Works out Home's lists from one read of the list: Continue (minus any
  /// show already at its last episode, which it heals to COMPLETED in the
  /// background), the watchlist, and the whole list for the lede. Shared by
  /// the first load and the re-read on return (item c).
  ({
    List<Map<String, dynamic>> watching,
    List<Map<String, dynamic>> planned,
    List<Map<String, dynamic>> entries,
  }) _sortList(QuerySnapshot watchingSnapshot, QuerySnapshot userSnapshot) {
    final allWatching = watchingSnapshot.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((d) => d['animeId'] != null)
        .toList();

    // ── Auto-complete already-finished anime ──────────────────
    // Anything where currentEpisode has reached the total (e.g. a
    // 1-episode movie added at 1/1, or anything finished outside the
    // tap-to-increment flow) should be COMPLETED and drop out of
    // Continue arc. Heal Firestore in the background.
    final List<Map<String, dynamic>> continueWatching = [];
    final uidForHeal = FirebaseAuth.instance.currentUser?.uid;
    for (final d in allWatching) {
      final cur   = (d['currentEpisode'] as int?) ?? 0;
      final total = (d['episodes'] as int?) ?? 0;
      final finished = total > 0 && cur >= total;
      if (finished) {
        // Heal status → COMPLETED (fire-and-forget, don't block load)
        final id = d['animeId']?.toString();
        if (uidForHeal != null && id != null) {
          FirebaseFirestore.instance
              .collection('users').doc(uidForHeal)
              .collection('animeList').doc(id)
              .update({'status': 'COMPLETED'})
              .catchError((_) {});
        }
        continue; // exclude from Continue arc
      }
      continueWatching.add(d);
    }

    continueWatching.sort((a, b) {
      final aTime = a['lastWatched'] as Timestamp?;
      final bTime = b['lastWatched'] as Timestamp?;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    final entries = userSnapshot.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((d) => d['animeId'] != null)
        .toList();

    // ── Plan to Watch ──────────────────────────────────────
    final allDocs = entries
        .where((d) => d['status'] == 'PLAN_TO_WATCH')
        .toList();
    // Sort by most recently added
    allDocs.sort((a, b) {
      final aTime = a['addedAt'] as Timestamp?;
      final bTime = b['addedAt'] as Timestamp?;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return (watching: continueWatching, planned: allDocs, entries: entries);
  }

  // ── Reload on return (Hanko stage H4, item c) ──────────────
  // Coming back from a page Home opened (a show, Search, My List…), Home
  // re-reads your list so the headline, the rows and the watchlist are
  // right after you rate, log or change a status there. Before, nothing
  // reloaded on return, so the headline named your previous rating.

  /// Opens [route] from Home, then re-reads the list once the page has
  /// finished closing. TransitionRoute.completed lands after the pop
  /// animation, so the re-read never rebuilds Home mid-transition.
  Future<void> _open(Route<void> route) async {
    Navigator.push(context, route);
    if (route is TransitionRoute<void>) {
      await route.completed;
    } else {
      await route.popped;
    }
    if (mounted) _reloadList();
  }

  bool _reloading = false;

  /// Re-reads the list from the device's cache, with estimated server
  /// timestamps (Stage 2 item b). The cache already holds what you just
  /// saved on the show's page, and "estimate" fills in its ratedAt, which a
  /// normal read leaves null until the server confirms it, so the lede is
  /// right at once, offline too. No AniList request; the airing batch only
  /// goes out if a show joined Watching.
  ///
  /// The web keeps no persistent copy, so its cache can hold just part of
  /// the list. There the re-read goes to the server (with your pending
  /// writes applied), and an answer that came from the cache instead is
  /// ignored rather than shown as your whole list.
  Future<void> _reloadList() async {
    if (_isLoading || _reloading) return;
    if (_listFailed) {
      _loadData(); // nothing on screen to keep: a plain retry
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _reloading = true;
    try {
      final list = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('animeList');
      const options = GetOptions(
        source: kIsWeb ? Source.serverAndCache : Source.cache,
        serverTimestampBehavior: ServerTimestampBehavior.estimate,
      );
      final results = await Future.wait([
        list.where('status', isEqualTo: 'WATCHING').get(options),
        list.orderBy('addedAt', descending: true).get(options),
      ]);
      if (!mounted) return;
      if (kIsWeb && results.any((s) => s.metadata.isFromCache)) return;
      final lists = _sortList(results[0], results[1]);
      setState(() {
        _continueWatching = lists.watching;
        _planToWatch = lists.planned;
        _entries = lists.entries;
      });
      _precacheLede();
      _loadAiring();
      _feedAchievements(results[1]);
    } catch (_) {
      // The cache couldn't answer: keep what is on screen.
    } finally {
      _reloading = false;
    }
  }

  /// Achievements (stage 4): Home's whole-list read goes to the record too,
  /// as Profile's snapshot does, after the frame (the service evaluates a
  /// moment later, never during build). Nothing with the switch off.
  void _feedAchievements(QuerySnapshot snapshot) {
    if (!Achievements.replaceCards) return;
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => AchievementsService.instance.observeList(snapshot));
  }

  /// The chart and Tonight's Drop, from OfflineCacheService: memory, then a
  /// saved copy under an hour old, then AniList through the throttle, with
  /// the saved copy as the fallback when AniList fails. Since Hanko the
  /// chart is the season's most popular shows (item f), so Tonight's Drop,
  /// the pick for an empty watchlist, now comes from the season too.
  Future<void> _loadChart() async {
    try {
      final season = await OfflineCacheService.instance
          .getSeasonal(_currentSeason(), DateTime.now().year);
      if (!mounted) return;
      Anime? animeOfDay;
      if (season.isNotEmpty) {
        final dayOfYear = DateTime.now()
            .difference(DateTime(DateTime.now().year, 1, 1))
            .inDays;
        animeOfDay = season[dayOfYear % season.length];
      }
      setState(() {
        _seasonAnime = season;
        _animeOfDay = animeOfDay;
      });
    } catch (_) {
      // getSeasonal falls back to its saved copy on any network failure;
      // this only catches the device storage itself failing. Uncaught, it
      // would reach Crashlytics as fatal (main.dart).
    }
  }

  /// True for an entry imported from MyAnimeList before the D21 fix: it is
  /// keyed by its MyAnimeList id and keeps MyAnimeList's cover, so its id
  /// means nothing to AniList (or means another show).
  static bool _isMalImport(Map<String, dynamic> entry) =>
      ((entry['imageUrl'] as String?) ?? '')
          .startsWith('https://cdn.myanimelist.net/');

  /// AniList ids to ask the airing batch about. MyAnimeList imports are
  /// left out: asking AniList about their number would fetch another show's
  /// schedule, or none, so their rows show no new episodes (§6c).
  static Set<int> _airingIdsFor(List<Map<String, dynamic>> entries) => {
        for (final e in entries)
          if (!_isMalImport(e))
            ?int.tryParse((e['animeId'] ?? e['id'] ?? '').toString()),
      };

  /// Sends the airing batch when a watching show hasn't been asked about
  /// yet, or, with [retryFailed], when the last batch failed. Keeps what it
  /// had when a batch fails, so a bad moment never blanks Coming up.
  Future<void> _loadAiring({bool retryFailed = false}) async {
    final ids = _airingIdsFor(_continueWatching);
    final ask = ids.difference(_airingAsked).isNotEmpty ||
        (retryFailed && _airingFailed);
    if (!ask) {
      if (_airingLoading && mounted) setState(() => _airingLoading = false);
      return;
    }
    final run = ++_airingRun;
    final airing = await _fetchAiringBatch(ids.toList());
    if (!mounted || run != _airingRun) return;
    setState(() {
      if (airing != null) {
        _airing = airing;
        _airingAsked = ids;
      }
      _airingFailed = airing == null;
      _airingLoading = false;
    });
  }

  /// Episodes aired so far for a Continue row: the next episode to air,
  /// minus one. Null when the batch knows nothing about the show: it has
  /// finished or isn't scheduled (the batch only asks for the next
  /// episode), the batch failed or hasn't answered, or it is a MyAnimeList
  /// import whose id isn't an AniList id.
  int? _airedFor(Map<String, dynamic> data) {
    if (_isMalImport(data)) return null;
    final id = int.tryParse((data['animeId'] ?? data['id'] ?? '').toString());
    final next = (_airing[id]?['episode'] as num?)?.toInt();
    return next == null ? null : next - 1;
  }

  /// Coming up's three: the soonest next episodes among the shows you're
  /// watching, from the airing batch.
  List<Map<String, dynamic>> _comingUpItems() {
    final results = <Map<String, dynamic>>[];
    for (final data in _continueWatching) {
      if (_isMalImport(data)) continue;
      final id =
          int.tryParse((data['animeId'] ?? data['id'] ?? '').toString());
      final airing = id == null ? null : _airing[id];
      if (airing == null) continue;
      final episode = (airing['episode'] as num?)?.toInt();
      final airingAt = (airing['airingAt'] as num?)?.toInt();
      if (episode == null || airingAt == null) continue;
      results.add({
        'title': data['title'] as String? ?? 'Unknown',
        'animeId': id.toString(),
        'episode': episode,
        'date': DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
        'imageUrl': data['imageUrl'] as String? ?? '',
      });
    }
    results.sort(
        (a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return results.take(3).toList();
  }

  /// Fetches next-airing-episode for many anime in a single AniList
  /// request. Paginated (perPage 50) to cover large watching lists.
  /// Moved here from Coming up unchanged, except that a failure now returns
  /// null instead of an empty map, so Home can keep what it had.
  Future<Map<int, Map<String, dynamic>>?> _fetchAiringBatch(
      List<int> ids) async {
    if (ids.isEmpty) return {};
    final out = <int, Map<String, dynamic>>{};
    const url = 'https://graphql.anilist.co';
    const query = r'''
    query ($ids: [Int]) {
      Page(page: 1, perPage: 50) {
        media(id_in: $ids, type: ANIME) {
          id
          nextAiringEpisode { episode airingAt }
        }
      }
    }
    ''';

    try {
      // Same retry shape as AnilistService._post: up to 3 attempts, and
      // ONLY for 429. Anything else — including a 403 — returns on the
      // first attempt, so an outage is never hammered. This used to back
      // off correctly and then return without ever retrying, so a single
      // transient 429 silently cost the whole cycle of countdowns.
      http.Response? resp;
      for (var attempt = 0; attempt < 3; attempt++) {
        await AnilistService.throttle();
        try {
          resp = await http.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'variables': {'ids': ids}}),
          ).timeout(const Duration(seconds: 12));
        } catch (_) {
          AnilistService.noteStatus(0, 'home airing');
          rethrow;
        }

        AnilistService.noteStatus(resp.statusCode, 'home airing');
        AnilistService.noteLimits(resp.headers);
        if (resp.statusCode != 429) break;
        final retryAfter =
            int.tryParse(resp.headers['retry-after'] ?? '') ?? (3 * (attempt + 1));
        AnilistService.backoff(retryAfter);
      }
      if (resp == null || resp.statusCode != 200) return null;

      final body = jsonDecode(resp.body);
      final media = body['data']?['Page']?['media'] as List? ?? [];
      for (final m in media) {
        final id = m['id'] as int?;
        final airing = m['nextAiringEpisode'] as Map<String, dynamic>?;
        if (id != null && airing != null) out[id] = airing;
      }
    } catch (_) {
      return null;
    }
    return out;
  }

  /// Reads the list once, for this load.
  ///
  /// On Android the first snapshot comes from the device's persistent cache,
  /// which holds the whole list, so Home takes it as it always has. The web
  /// keeps no persistent copy, and a query's first snapshot there can be
  /// just the documents another query left in memory: seen on the emulators,
  /// the whole-list query answered with a test user's four WATCHING shows
  /// out of nine, so "Up next" came out empty, and the headline and the
  /// watchlist pick would miss every finished and planned show. On the web,
  /// get() waits for the server while online, and falls back to the cache
  /// only when it can't be reached.
  Future<QuerySnapshot> _readList({bool watchingOnly = false}) {
    if (!kIsWeb) {
      return watchingOnly
          ? _firestoreService.getAnimeByStatus('WATCHING').first
          : _firestoreService.getAnimeList().first;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.error(StateError('Not signed in'));
    final list = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('animeList');
    return watchingOnly
        ? list.where('status', isEqualTo: 'WATCHING').get()
        : list.orderBy('addedAt', descending: true).get();
  }

  /// Fetches recommendation rows after the screen has already rendered,
  /// so the throttled AniList call never delays first paint.
  Future<void> _loadRecommendations(dynamic userSnapshot) async {
    final userAnimeIds = userSnapshot.docs
        .map((d) => (d.data() as Map)['animeId'].toString())
        .toSet();
    final seedDocs = userSnapshot.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((d) =>
            (d['status'] == 'COMPLETED' || d['status'] == 'WATCHING') &&
            (d['genres'] as List?)?.isNotEmpty == true)
        .take(1)
        .toList();

    final List<Map<String, dynamic>> rows = [];
    for (final seed in seedDocs) {
      final genres = (seed['genres'] as List).cast<String>();
      final sourceTitle = seed['title'] as String? ?? 'your list';
      try {
        final recs = await _aniListService.searchAnime(
            '', genre: genres.first, sort: 'SCORE_DESC');
        final filtered =
            recs.where((a) => !userAnimeIds.contains(a.id)).take(10).toList();
        if (filtered.isNotEmpty) {
          rows.add({
            'genre': genres.first,
            'sourceTitle': sourceTitle,
            'anime': filtered,
          });
        }
      } catch (_) {}
    }

    if (mounted && rows.isNotEmpty) {
      setState(() => _recommendationRows = rows);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    if (hour < 21) return 'GOOD EVENING';
    return 'GOOD NIGHT';
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'MORNING';
    if (hour < 17) return 'AFTERNOON';
    if (hour < 21) return 'EVENING';
    return 'NIGHT';
  }

  // Hanko's dateline: "Tuesday, 27 October", a sentence rather than an
  // eyebrow, so it reads as the page's date the way a journal entry does.
  String _getTodayLabel() {
    return DateFormat('EEEE, d MMMM').format(DateTime.now());
  }

  Widget _buildDateline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 6, AppTheme.hankoGutter, 0),
      child: Text(
        _getTodayLabel(),
        style: AppTheme.hankoSans(
            fontSize: AppTheme.hankoMetaSize,
            // On the hero's field all text is washi: stone would fall to
            // about 2.5:1 on the lightest fields (Print Room, P2).
            color: _heroCover() != null
                ? AppTheme.hankoWashi
                : AppTheme.hankoStone,
            height: 1.3),
      ),
    );
  }

  /// The cover the hero prints and takes its colour from (Print Room, P2):
  /// the lede show's, or with no rating in 14 days the first show you're
  /// watching (DESIGN.md §9.5). Null, so no print and no field, with Print
  /// Room off, while the list loads or when it couldn't be read, and when
  /// that show has no cover.
  String? _heroCover() {
    if (!_printRoom || _isLoading || _listFailed) return null;
    final entry = _newestRating() ??
        (_continueWatching.isEmpty ? null : _continueWatching.first);
    final url = (entry?['imageUrl'] as String?)?.trim() ?? '';
    return url.isEmpty ? null : url;
  }

  /// The header on the hero's field (Print Room, P2): the colour runs from
  /// the top of Home and fades out under the lede, and comes from the cover
  /// itself, since list entries keep no AniList colour (HankoCoverColour).
  /// With no hero cover the field is clear, and the header is as before.
  Widget _heroField(Widget header) {
    if (!_printRoom) return header;
    return HankoField(coverUrl: _heroCover(), solidTo: 0.72, child: header);
  }

  /// Tonight's band on its show's colour (Print Room, P2; DESIGN.md §9.5):
  /// a flat field from [url]'s cover, the width of the page as the hero's
  /// is, fading in from the page over its first 56 dp and out at its foot,
  /// while [band] keeps the record's column (_PickBand). The band's buttons
  /// get a transparent Material of its own, so their press and focus washes
  /// show over the field: ink is drawn under a Material's children.
  Widget _bandField(String? url, Widget band) {
    if (!_printRoom) return band;
    return HankoField(
      coverUrl: url,
      solidTo: 0.75,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 56,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.hankoSumi,
                      AppTheme.hankoSumi.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Material(type: MaterialType.transparency, child: band),
        ],
      ),
    );
  }

  /// Item (i): on a wide window the record blocks (the lede, the Continue
  /// rows and tonight's pick) keep the phone's column instead of stretching:
  /// Responsive.proseMaxWidth, 440 px of text (WEB.md §9.3's one-column
  /// rule), plus the gutters. It hangs on the left edge that the wordmark,
  /// the section heads and the chart's first column share; PageWidth would
  /// centre it under none of them. Below 1024 it does nothing, so a phone
  /// keeps its layout in either orientation (WEB.md §9.2).
  Widget _recordColumn(Widget child) {
    if (!Responsive.isDesktop(context)) return child;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
        child: child,
      ),
    );
  }

  // Hanko's press: an 8% washi wash, no ripple, square corners.
  static const ButtonStyle _hankoIconButtonStyle = ButtonStyle(
    overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
    splashFactory: NoSplash.splashFactory,
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    )),
  );

  /// The top line (Hanko stage H4, item g): the coral mark beside "Hanj" in
  /// Shippori Mincho, and Search as a 48 dp button. At 20 the mark is its
  /// small cut, without the flash (MARK-SIZES.md §0).
  Widget _buildTopLine() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: AppTheme.hankoGutter),
          // One logo, so one label; it keeps its drawn size at any text
          // size, as the login wordmark does.
          Semantics(
            label: 'Hanj',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/hanj_cut_small.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 9),
                Text(
                  'Hanj',
                  textScaler: TextScaler.noScaling,
                  style: AppTheme.hankoSerif(
                      fontSize: 21, height: 1, letterSpacing: 0.2),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Loki is locked until Hanj+ ships: the entry is
          // compiled out while kLokiEnabled is false.
          if (kLokiEnabled) ...[
            // Tomo — AI anime companion
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const TomoScreen())),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF97316), Color(0xFFE8624A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  '友',
                  style: TextStyle(
                    color: Color(0xFF0A0A0A),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: () => _open(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
            tooltip: 'Search',
            icon: const Icon(Icons.search_sharp, size: 24),
            color: AppTheme.hankoWashi,
            style: _hankoIconButtonStyle,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // The top line and the date need no data, so they are there from the
      // first frame and stay put when the list arrives (§6c: no states).
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopLine(),
              _buildDateline(),
              const SizedBox(height: 48),
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppTheme.hankoWashi,
                    strokeWidth: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primary,
        backgroundColor: AppTheme.surfaceMid,
        child: CustomScrollView(
          slivers: [
            // ── Top line, date and headline ─────────────────
            SliverToBoxAdapter(
              key: const ValueKey('home-header'),
              child: _heroField(Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopLine(),
                    _buildDateline(),
                    _recordColumn(Padding(
                      // 10 under the date beside the print, the mockup's.
                      padding: const EdgeInsets.fromLTRB(AppTheme.hankoGutter,
                          _printRoom ? 10 : 6, AppTheme.hankoGutter, 0),
                      // Dynamic headline
                      child: _buildHeadline(),
                    )),
                  ],
                ),
              )),
            ),

            // ── Import Pending Banner ────────────────────────
            if (_importPending)
              SliverToBoxAdapter(
                key: const ValueKey('home-import-banner'),
                // The record's column on a wide window, like the lede above
                // it and the rows below (item i).
                child: _recordColumn(_ImportPendingBanner(
                  open: _open,
                  onDismiss: () async {
                    await _firestoreService.dismissImportBanner();
                    if (mounted) setState(() => _importPending = false);
                  },
                )),
              ),

            // ── Continue Watching ────────────────────────────
            // Hanko's rows (item b), right under the headline: the thing you
            // do most is the easiest to reach, so +1 sits in the top half of
            // the screen instead of below the fold. Three rows, then "See
            // all", which opens My List's Watching filter. With Print Room
            // (P2) it's a shelf of prints instead (_buildShelf).
            if (_continueWatching.isNotEmpty && _printRoom)
              SliverToBoxAdapter(
                key: const ValueKey('home-continue-row'),
                child: _buildShelf(),
              )
            else if (_continueWatching.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('home-continue-row'),
                child: _recordColumn(Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (index, data)
                          in _continueWatching.take(3).indexed) ...[
                        if (index > 0) const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.hankoGutter),
                          // Keyed by animeId, not index. This list is sorted
                          // by lastWatched, so bumping an episode reorders it
                          // — and _ContinueCardState holds _current, the
                          // episode number. Index-matched, the element keeps
                          // its old _current while receiving a different
                          // anime's data, and didUpdateWidget only resyncs
                          // when the incoming value differs from the
                          // *previous widget's* value, so two shows on the
                          // same episode leave the stale number on screen.
                          child: _ContinueCard(
                            key: ValueKey(data['animeId']?.toString() ??
                                'continue-$index'),
                            data: data,
                            firestoreService: _firestoreService,
                            // Finishing a show re-reads the list from the
                            // cache, so the row leaves with no AniList
                            // request (it used to re-run the whole load).
                            onUpdated: _reloadList,
                            aired: _airedFor(data),
                            open: _open,
                          ),
                        ),
                      ],
                      if (_continueWatching.length > 3)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppTheme.hankoGutter, 6, AppTheme.hankoGutter, 0),
                          child: _QuietLink(
                            label: 'See all ${_continueWatching.length}',
                            onTap: () => _open(
                                MaterialPageRoute(
                                    builder: (_) => const MyListScreen(initialStatus: 'WATCHING', showBackButton: true))),
                          ),
                        ),
                    ],
                  ),
                )),
              ),

            // ── From your watchlist tonight (item d) ─────────
            // Since round seven, the newest show on your watchlist (see
            // _watchlistPick), drawn as Home's feature band (_PickBand).
            // Tonight's Drop, the season pick for everyone, keeps the slot
            // only when the watchlist holds nothing the pick can show (empty,
            // or only entries with no title or cover: see _pickable). The
            // band runs edge to edge; its words keep the gutter.
            if (_pickable.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('home-watchlist-pick'),
                child: _bandField(_pickable.first['imageUrl'] as String?,
                    _recordColumn(Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Builder(builder: (context) {
                    final pick = _watchlistPick();
                    return _WatchlistPick(
                      entry: pick,
                      // Said only when it is true: the pick is the newest
                      // of two or more, with no newer entry passed over.
                      newest: _planToWatch.length > 1 &&
                          identical(pick, _planToWatch.first),
                      // Its print flies to the show's page (P6).
                      onOpen: () => _openEntry(pick, place: 'band'),
                      // Print Room's washi action (P2-2), on its band only.
                      onStart: _printRoom && _startWatching
                          ? () => _start(pick)
                          : null,
                      starting: _starting,
                      // Up next folds in here (question 45): the rest of
                      // your watchlist is one tap away, on My List's
                      // watchlist filter. Only when there is more than the
                      // pick, as Continue's "See all" shows only when there
                      // are more rows than Home has room for.
                      footer: _planToWatch.length > 1
                          ? _QuietLink(
                              label:
                                  'See your watchlist (${_planToWatch.length})',
                              onTap: () => _open(MaterialPageRoute(
                                  builder: (_) => const MyListScreen(
                                      initialStatus: 'PLAN_TO_WATCH',
                                      showBackButton: true))),
                            )
                          : null,
                    );
                  }),
                ))),
              )
            // ── Tonight's Drop / Anime of Day ────────────────
            else if (_animeOfDay != null)
              SliverToBoxAdapter(
                key: const ValueKey('home-anime-of-day'),
                child: _bandField(_animeOfDay!.imageUrl, _recordColumn(Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _TonightCard(anime: _animeOfDay!, open: _open),
                ))),
              ),

            // ── Tonight's Watch ──────────────────────────────
            // A Hanko section since item h, so it takes the sections' 24 px
            // above it; the old card had 16 and its own coral frame.
            const SliverToBoxAdapter(
              key: ValueKey('home-tonight-watch'),
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 24, 0, 0),
                child: TonightWatchCard(),
              ),
            ),

            // ── Plan to Watch ────────────────────────────────
            // Hidden (question 45, see _showUpNext); kept intact below.
            if (_showUpNext && _planToWatch.isNotEmpty) ...[
              SliverToBoxAdapter(
                key: const ValueKey('home-plan-header'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Up next',
                          style: AppTheme.serif(
                              fontSize: 20, weight: FontWeight.w600)),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _open(
                              MaterialPageRoute(
                                  builder: (_) => const MyListScreen(initialStatus: 'PLAN_TO_WATCH', showBackButton: true))),
                          child: Text(
                            'SEE ALL →',
                            style: AppTheme.mono(
                                fontSize: 11,
                                color: AppTheme.primary,
                                letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                key: const ValueKey('home-plan-row'),
                child: SizedBox(
                  // A 196 px cover, then a two-line title (Jost 11) and the
                  // episode count (Jost 9) at the reader's text size. Jost's
                  // own line is about 1.5 times its size here (1.47-1.55
                  // measured); 1.6 leaves room. Never under the 260 px it
                  // had: at 1.3x a card with a two-line title needed 262
                  // (196 + 6 + 42 + 18) and overflowed.
                  height: (202 +
                          MediaQuery.textScalerOf(context).scale(11) * 1.6 * 2 +
                          MediaQuery.textScalerOf(context).scale(9) * 1.6 +
                          2)
                      .clamp(260.0, double.infinity),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _planToWatch.length,
                    itemBuilder: (context, index) => _PlanCard(
                      data: _planToWatch[index],
                      open: _open,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],

            // ── Popular this season ──────────────────────────
            // Hanko's chart (item f): the season's most popular shows,
            // AniList's own calendar, instead of "Trending this week". The
            // same one request, behind the same one-hour cache and stale
            // fallback (OfflineCacheService.getSeasonal), inside the throttle.
            if (_seasonAnime.isNotEmpty) ...[
              // The one hairline the screen has: it sets the season's chart
              // off from your own record above it. 28 above it, as hanko.html
              // has: with Up next hidden it follows Tonight's watch, whose
              // mood tile it otherwise met 8 px below (question 45). Up next's
              // strip used to supply the rest of the gap.
              SliverToBoxAdapter(
                key: const ValueKey('home-chart-rule'),
                child: Container(
                  height: 1,
                  margin: EdgeInsets.fromLTRB(AppTheme.hankoGutter,
                      _showUpNext ? 8 : 28, AppTheme.hankoGutter, 0),
                  color: AppTheme.hankoHairline,
                ),
              ),
              SliverToBoxAdapter(
                key: const ValueKey('home-trending-header'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 20, AppTheme.hankoGutter, 12),
                  // A Wrap, not a Row (H2 QA S1): when the heading and its
                  // aside don't fit on one line, as at 1.3x text, the aside
                  // moves under the heading instead of squeezing it onto
                  // two lines, or at 2.0x breaking "Popular" mid-word.
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Popular this season',
                            style: AppTheme.hankoSerif(height: 1.3)),
                      ),
                      Text('${_seasonLabel()}, AniList score',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              color: AppTheme.hankoStone,
                              height: 1.3)),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: AnilistSavedNote()),

              // The chart lays out in columns on desktop. Below 1024
              // columnsFor is floored to 1 (see its domain note), so the
              // phone takes the SliverList branch it has always taken and
              // builds an identical tree in both orientations.
              //
              // The count comes from MediaQuery width, not from the width this
              // sliver is actually laid out in. Those differ — PageWidth caps
              // the content at 1400 and the rail takes ~117 px beside it — but
              // the answer does not, because columnsFor caps internally at the
              // same 1400 and the content is never wider than that. At 1024
              // with the rail it yields 2 columns of ~453 px, still above the
              // 350 px minimum the arithmetic is built from.
              //
              // That is an assumption, not an identity. If the cap, the rail
              // width or the column minimum ever change, this can start
              // over-counting; responsive_columns_test's boundary and
              // minimum-width cases are what catch it.
              if (Responsive.columnsFor(MediaQuery.of(context).size.width) ==
                  1)
                SliverList(
                  key: const ValueKey('home-trending-list'),
                  delegate: _chartDelegate(),
                )
              else
                SliverGrid(
                  key: const ValueKey('home-trending-grid'),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.columnsFor(
                        MediaQuery.of(context).size.width),
                    // _ChartRow is a fixed height by construction: 56 px,
                    // taller than its 48 px cover and its one-line title.
                    mainAxisExtent: _ChartRow.height,
                    crossAxisSpacing: 24,
                  ),
                  delegate: _chartDelegate(),
                ),
              SliverToBoxAdapter(
                key: const ValueKey('home-chart-more'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 4, AppTheme.hankoGutter, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _QuietLink(
                      label: 'More from this season',
                      onTap: () => _open(
                          MaterialPageRoute(builder: (_) => const DiscoveryScreen(initialTab: 'SEASONAL', showBackButton: true))),
                    ),
                  ),
                ),
              ),
            ],

            // ── Coming Up ─────────────────────────────────────
            // A Hanko section (question 46): a Mincho heading with the
            // calendar as a quiet link, no coral, and rows drawn like the
            // Continue rows above. It keeps the record's 440 px column on a
            // wide window, as the rows it continues do (item i).
            SliverToBoxAdapter(
              key: const ValueKey('home-section-a'),
              child: _recordColumn(Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text('Coming up',
                            style: AppTheme.hankoSerif(height: 1.3)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _QuietLink(
                      label: 'Calendar',
                      onTap: () => _open(MaterialPageRoute(
                          builder: (_) => const AnimeCalendarScreen())),
                    ),
                  ],
                ),
              )),
            ),
            SliverToBoxAdapter(
              key: const ValueKey('home-section-b'),
              child: _recordColumn(Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.hankoGutter),
                child: _ComingUpSection(
                    items: _comingUpItems(),
                    loading: _airingLoading,
                    open: _open,
                    reminderIds: _reminderIds,
                    onToggleReminder: (animeId, val) {
                      setState(() {
                        if (val) {
                          _reminderIds.add(animeId);
                        } else {
                          _reminderIds.remove(animeId);
                        }
                      });
                    }),
              )),
            ),

            // ── Recommendations ──────────────────────────────
            // "Because you loved" in Hanko (question 46): the eyebrow becomes
            // a sentence heading in Mincho, as the other sections are, and
            // its aside says what the row is: a genre search, highest AniList
            // score first (_loadRecommendations), not AniList's own
            // recommendations. The covers are a poster strip like This
            // season's. Same request, same shows, same taps.
            for (final row in _recommendationRows) ...[
              SliverToBoxAdapter(
                key: ValueKey('rec-header-${row['genre']}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Two lines, fading where a cut remains (H2 QA N3).
                      Semantics(
                        header: true,
                        child: _FadeTitle(
                          'Because you loved ${row['sourceTitle']}',
                          maxLines: 2,
                          style: AppTheme.hankoSerif(height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${row['genre']}, by AniList score',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoLabelSize,
                            color: AppTheme.hankoStone,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                key: ValueKey('rec-row-${row['genre']}'),
                child: SizedBox(
                  height: _classicRecs
                      ? 260
                      : _StripItem.heightFor(MediaQuery.textScalerOf(context)),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.hankoGutter),
                    physics: const BouncingScrollPhysics(),
                    itemCount: (row['anime'] as List<Anime>).length,
                    itemBuilder: (context, index) {
                      final anime = (row['anime'] as List<Anime>)[index];
                      final key = ValueKey('rec-${row['genre']}-${anime.id}');
                      // The classic card is kept, switched off.
                      return _classicRecs
                          ? _TrendingCard(
                              key: key,
                              anime: anime,
                              rank: index + 1,
                              open: _open,
                            )
                          : Padding(
                              key: key,
                              padding: const EdgeInsets.only(right: 10),
                              child: _StripItem(anime: anime, open: _open),
                            );
                    },
                  ),
                ),
              ),
            ],

            // ── Upcoming This Season ─────────────────────────
            // Keyed on purpose. The recommendation slivers above are inserted
            // later, when _loadRecommendations finishes. Without a key, the
            // sliver list is matched positionally — every entry is an unkeyed
            // SliverToBoxAdapter, so canUpdate() returns true — and this
            // sliver's element gets handed a recommendation row instead,
            // unmounting UpcomingAnimeRow and remounting it further down. That
            // cost a second identical AniList request on every Home load.
            //
            // It reads the same request as the season chart, so it starts
            // after the chart's shows instead of repeating them (question
            // 44). No request is added.
            SliverToBoxAdapter(
              key: const ValueKey('upcoming-this-season'),
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: UpcomingAnimeRow(skip: {
                  for (final anime in _seasonAnime.take(_chartLength)) anime.id,
                }),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  /// The chart's rows: five, as Hanko draws them. This season's strip
  /// starts after the same shows (question 44).
  static const int _chartLength = 5;

  /// Shared by the chart's SliverList and SliverGrid so the two branches
  /// cannot drift in what they build.
  SliverChildBuilderDelegate _chartDelegate() {
    return SliverChildBuilderDelegate(
      (context, index) {
        if (index >= _seasonAnime.length) return null;
        final anime = _seasonAnime[index];
        return Padding(
          key: ValueKey('chart-${anime.id}'),
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: _ChartRow(
            anime: anime,
            rank: index + 1,
            onOpen: () => _open(
                MaterialPageRoute(
                    builder: (_) => AnimeDetailScreen(anime: anime))),
          ),
        );
      },
      childCount: _seasonAnime.length.clamp(0, _chartLength),
    );
  }

  // ── Continue as a shelf (Print Room, P2; question 158) ─────
  // The shows you're watching as prints on mats of their own colour, in a
  // shelf that scrolls sideways (DESIGN.md §9.5, frame 02), under
  // "Continue" and their count. "See all" opens My List's Watching filter
  // once a phone's first screen can't show the whole shelf, as the rows'
  // "See all" did past three. Each print has its title under it, then
  // "9 of 12" and +1 (_ContinueCard). It runs the width of the page, as
  // Home's other strips do, rather than the record's column.
  Widget _buildShelf() {
    final count = _continueWatching.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  label: 'Continue, $count show${count == 1 ? '' : 's'}',
                  child: ExcludeSemantics(
                    child: Text.rich(
                      TextSpan(
                        // A Mincho space and a Jost one: about the
                        // mockup's gap before the count.
                        text: 'Continue ',
                        style: AppTheme.hankoSerif(height: 1.3),
                        children: [
                          TextSpan(
                            text: ' $count',
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              weight: FontWeight.w500,
                              color: AppTheme.hankoStone,
                              tabular: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (count > 2) ...[
                const SizedBox(width: 12),
                _QuietLink(
                  label: 'See all',
                  onTap: () => _open(MaterialPageRoute(
                      builder: (_) => const MyListScreen(
                          initialStatus: 'WATCHING', showBackButton: true))),
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: _ContinueCard.shelfHeight(MediaQuery.textScalerOf(context)),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            // 4 above and below: room for a focused print's outline, which
            // lies outside it (_PrintTap), inside the list's clip.
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.hankoGutter, vertical: 4),
            physics: const BouncingScrollPhysics(),
            itemCount: count,
            itemBuilder: (context, index) {
              final data = _continueWatching[index];
              return Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 12),
                // Keyed by animeId, not index, as the rows were: see there.
                child: _ContinueCard(
                  key: ValueKey(
                      data['animeId']?.toString() ?? 'continue-$index'),
                  data: data,
                  firestoreService: _firestoreService,
                  onUpdated: _reloadList,
                  aired: _airedFor(data),
                  open: _open,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// AniList's season for today, the way the rest of the app works it out.
  static String _currentSeason() {
    final month = DateTime.now().month;
    if (month <= 3) return 'WINTER';
    if (month <= 6) return 'SPRING';
    if (month <= 9) return 'SUMMER';
    return 'FALL';
  }

  /// "Fall 2026": AniList's season names, as the rest of the app uses them.
  static String _seasonLabel() {
    final s = _currentSeason();
    return '${s[0]}${s.substring(1).toLowerCase()} ${DateTime.now().year}';
  }

  // ── The lede (Hanko stage H4, item a) ──────────────────────
  // Home opens on a sentence about your newest verdict, with its day:
  // "Last night you finished DAN DA DAN, all twelve episodes, and sealed it
  // [8.5]", the seal in coral because it's yours. Under 14 days old only
  // (§6c); then it gives way to what you're watching. Imported ratings have
  // no ratedAt, so they never pose as your latest. The whole sentence is one
  // button that opens the show.

  /// The newest rating made in the app, if it is under 14 days old.
  Map<String, dynamic>? _newestRating() {
    Map<String, dynamic>? newest;
    DateTime? newestAt;
    for (final entry in _entries) {
      final at = (entry['ratedAt'] as Timestamp?)?.toDate();
      if (at == null || entry['userRating'] is! num) continue;
      if (newestAt == null || at.isAfter(newestAt)) {
        newest = entry;
        newestAt = at;
      }
    }
    if (newestAt == null || _daysBefore(newestAt) >= 14) return null;
    return newest;
  }

  /// Whole days between [t] and today on the device's own calendar, so a
  /// rating at 23:50 is "last night" ten minutes later. A clock running
  /// ahead of the server's can't make it negative.
  static int _daysBefore(DateTime t) {
    final now = DateTime.now();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(t.year, t.month, t.day))
        .inDays;
    return days < 0 ? 0 : days;
  }

  /// "Today", "Last night" (yesterday from 18:00), "Yesterday", "On
  /// Saturday" (2–6 days), "On 13 October" (7–13 days).
  static String _whenRated(DateTime t) {
    final days = _daysBefore(t);
    if (days == 0) return 'Today';
    if (days == 1) return t.hour >= 18 ? 'Last night' : 'Yesterday';
    if (days < 7) return 'On ${DateFormat('EEEE').format(t)}';
    return 'On ${DateFormat('d MMMM').format(t)}';
  }

  static const _numberWords = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
    'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const _tensWords = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
    'eighty', 'ninety',
  ];

  /// Counts in a sentence are words up to ninety-nine, as a journal writes
  /// them ("all twelve episodes"), and figures from 100 ("all 1,122").
  static String _inWords(int n) {
    if (n < 20) return _numberWords[n];
    if (n < 100) {
      final ones = n % 10;
      return _tensWords[n ~/ 10] + (ones == 0 ? '' : '-${_numberWords[ones]}');
    }
    return NumberFormat.decimalPattern().format(n);
  }

  /// Precaches the lede show's cover after the list loads: one image from
  /// AniList's image servers, not an API request, so the show's page has
  /// its picture in the first frame when you open it from the lede. Errors
  /// are swallowed here: reported, they would reach Crashlytics as fatal.
  void _precacheLede() {
    final url = _newestRating()?['imageUrl'] as String?;
    if (url == null || url.isEmpty || !mounted) return;
    precacheImage(CachedNetworkImageProvider(url), context,
        onError: (_, _) {});
  }

  /// The watchlist entries the pick can show, newest first: any with a
  /// title and a cover to show (round seven). Question 114 also kept old
  /// MyAnimeList imports out, since one opens nearly empty; Shahid's request
  /// on 2026-11-03 is the newest addition, whichever it is, so now only an
  /// entry with nothing to show is passed over. The entries are left as
  /// they are: the watchlist link counts them all, and My List shows them.
  List<Map<String, dynamic>> get _pickable =>
      [for (final e in _planToWatch) if (_canShow(e)) e];

  static bool _canShow(Map<String, dynamic> entry) =>
      ((entry['title'] as String?) ?? '').trim().isNotEmpty &&
      ((entry['imageUrl'] as String?) ?? '').trim().isNotEmpty;

  /// Tonight's watchlist pick: the newest entry it can show (round seven;
  /// Shahid, 2026-11-03: "it should also show the most recent anime added to
  /// watch list so when I open the app I'm seeing what I have planned to
  /// watch"). _planToWatch is newest first by addedAt, which every status
  /// change rewrites, so it is when the show last went onto the watchlist;
  /// an imported show's is the day of the import. Until round seven the
  /// pick was the day of the year modulo the list, a different entry each
  /// day, so it was seldom the one you had just planned.
  Map<String, dynamic> _watchlistPick() => _pickable.first;

  /// Opens [data]'s show; from its print at [place], the print flies (P6).
  void _openEntry(Map<String, dynamic> data, {String? place}) {
    final anime = Anime(
      id: data['animeId']?.toString() ?? '',
      title: data['title'] as String? ?? 'Unknown',
      imageUrl: data['imageUrl'] as String?,
      episodes: data['episodes'] as int?,
      genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
    );
    _open(place == null
        ? MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime))
        : _showRoute(context, anime, place: place));
  }

  Widget _buildHeadline() {
    final style = AppTheme.hankoSerif(
        fontSize: AppTheme.hankoLedeSize, height: 1.32);

    // The list couldn't be read: say so, naming no cause the app can't
    // verify (ANILIST-OFFLINE-0908-REPORT.md), instead of greeting someone
    // with a list as if it were empty. The line takes the typographic
    // apostrophe (question 126): Shippori draws the typewriter one as a
    // straight tick, as Profile's failure line found (question 109).
    if (_listFailed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Couldn’t load your list just now.", style: style),
          const SizedBox(height: 12),
          _TextTile(label: 'Retry', onTap: _loadData),
        ],
      );
    }

    final rated = _newestRating();
    if (rated != null) return _buildLede(rated, style);

    // count is how many WATCHING shows are on the list, not episodes that
    // aired, so the headline says that. The typographic apostrophe, as the
    // failure line above (question 154).
    final count = _continueWatching.length;
    final String line;
    if (count > 0) {
      line = 'You’re watching $count show${count > 1 ? 's' : ''}.';
    } else if (_entries.isNotEmpty) {
      line = 'All caught up.';
    } else {
      // An empty list keeps the discovery-led headline.
      line = 'Discover something new tonight.';
    }
    // Print Room (P2): with no rating in 14 days the hero takes the first
    // show you're watching, its print beside the line and its colour behind
    // (DESIGN.md §9.5's fallback). No seal: it isn't a verdict. The print
    // opens that show; the line, about all of them, isn't a button.
    final cover = _heroCover();
    if (cover != null && count > 0) {
      final first = _continueWatching.first;
      return _HeroRow(
        sentence: Text(line,
            style: style.copyWith(fontSize: _ledeBesidePrint)),
        url: cover,
        heroTag: _printTag('hero', first['animeId']?.toString() ?? ''),
        printLabel: (first['title'] as String? ?? '').trim(),
        onPrint: () => _openEntry(first, place: 'hero'),
      );
    }
    return Text(line, style: style);
  }

  Widget _buildLede(Map<String, dynamic> entry, TextStyle style) {
    final ratedAt = (entry['ratedAt'] as Timestamp).toDate();
    final lastWatched = (entry['lastWatched'] as Timestamp?)?.toDate();
    final rating = (entry['userRating'] as num).toDouble();
    final rawTitle = entry['title'] as String? ?? 'it';
    final episodes = entry['episodes'] as int?;

    // "Finished" only when the finishing happened with the rating: the list
    // keeps no completion date (question 27), but lastWatched is written by
    // the progress or status change that completed the show, so a completed
    // show updated within six hours of its rating was finished then.
    final finishedThen = entry['status'] == 'COMPLETED' &&
        lastWatched != null &&
        ratedAt.difference(lastWatched).inMinutes.abs() <= 6 * 60;

    // Print Room (P2) presses the seal onto the show's print, beside the
    // sentence, where the show has a cover to print (_heroCover).
    final cover = _heroCover();
    final onPrint = cover != null;

    final when = _whenRated(ratedAt);
    // The sentence, with three ways of keeping words together: a short
    // title on one line ([wholeTitle], as the mockup's no-break span does),
    // "you" with its verb ([bindVerb]), and always "sealed it" with the
    // seal, a no-break space before it as the mockup's &nbsp; does.
    String compose({required bool wholeTitle, bool bindVerb = false}) {
      final title =
          wholeTitle ? rawTitle.replaceAll(' ', ' ')
              // Nor at a hyphen: the phone broke "One-" / "Punch Man" in
              // P2's narrower lede. A word joiner after it forbids that
              // break and draws nothing.
              .replaceAll('-', '-\u2060')
          : rawTitle;
      final you = bindVerb ? 'you ' : 'you ';
      // On the print (Print Room) the seal leaves the sentence, so "sealed
      // it" keeps together instead, as the mockup's sealed&nbsp;it does.
      if (onPrint) {
        if (finishedThen && episodes != null && episodes >= 2) {
          return '$when ${you}finished $title, all ${_inWords(episodes)} '
              'episodes, and sealed it';
        } else if (finishedThen) {
          return '$when ${you}finished $title and sealed it';
        }
        return '$when ${you}sealed $title';
      }
      if (finishedThen && episodes != null && episodes >= 2) {
        return '$when ${you}finished $title, all ${_inWords(episodes)} '
            'episodes, and sealed it ';
      } else if (finishedThen) {
        return '$when ${you}finished $title and sealed it ';
      }
      return '$when ${you}sealed $title ';
    }

    final scaler = MediaQuery.textScalerOf(context);
    final score = HankoSeal.formatScore(rating);
    // The seal sits inline at the sentence's size: 32 x 28 with 14 px
    // numerals at 22 px, as the mockup's .seal--in. Its box follows the
    // text size setting; HankoSeal shrinks the numerals to fit. On the
    // print it's the print's, and the sentence sets at 20 beside it.
    final seal = onPrint ? null : Size(scaler.scale(32), scaler.scale(28));
    final sentenceStyle =
        onPrint ? style.copyWith(fontSize: _ledeBesidePrint) : style;
    Widget words() => LayoutBuilder(builder: (context, constraints) {
          // A short title is kept whole only if it fits on a line: wider,
          // Flutter would break it inside a word (_titleMustFit).
          final keepWhole = rawTitle.length <= 18 &&
              !(_titleMustFit &&
                  _breaksAWord(compose(wholeTitle: true), sentenceStyle,
                      scaler, seal, constraints.maxWidth));
          // Q54: a short title kept whole can leave the word before it
          // alone on a line. At 1.3x "On Monday you / finished / Cowboy
          // Bebop, all ..." left "finished" by itself. So the first of
          // these that leaves no word alone wins: the title whole; the
          // title whole with "you" kept by its verb; the title free to
          // break. A long title may always break, as before.
          final candidates = keepWhole
              ? [
                  compose(wholeTitle: true),
                  compose(wholeTitle: true, bindVerb: true),
                  compose(wholeTitle: false),
                ]
              : [compose(wholeTitle: false)];
          final sentence = candidates.firstWhere(
              (s) => !_leavesAWordAlone(
                  s, sentenceStyle, scaler, seal, constraints.maxWidth),
              orElse: () => candidates.first);
          return Text.rich(
            TextSpan(
              style: sentenceStyle,
              children: [
                TextSpan(text: sentence),
                if (seal != null)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: HankoSeal.score(
                      rating,
                      size: seal.height,
                      width: seal.width,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          );
        });
    // Its own semantics node (container), named by the sentence and its
    // seal, with the InkWell's tap and focus inside it (question 119, as
    // Profile's rows since dafb7c5). A tap given to the node over excluded
    // semantics let a screen reader press it but left out the InkWell's
    // focus, so on the web the node couldn't take focus. The sentence and
    // the seal are left out of the tree, since the label says them.
    return Semantics(
      container: true,
      button: true,
      label: '${compose(wholeTitle: false).replaceAll(' ', ' ').trim()} '
          '$score',
      onTapHint: 'open ${rawTitle.trim()}',
      child: _inkOnField(
        onPrint,
        InkWell(
          // On the print, the print flies (P6).
          onTap: () => _openEntry(entry, place: onPrint ? 'hero' : null),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: AppTheme.hankoTouch),
              // On the print (Print Room) the whole hero, the sentence and
              // the print with your seal, is the one button.
              child: onPrint
                  ? _HeroRow(
                      sentence: words(),
                      url: cover,
                      heroTag: _printTag(
                          'hero', entry['animeId']?.toString() ?? ''),
                      rating: rating)
                  : words(),
            ),
          ),
        ),
      ),
    );
  }

  /// [button] on a transparent Material of its own when it sits on a colour
  /// field ([onField]): ink is drawn under a Material's children, so on the
  /// page's Material the field would hide the press and focus washes, as
  /// _PickBand found. Off a field it's [button] as it was.
  static Widget _inkOnField(bool onField, Widget button) => onField
      ? Material(type: MaterialType.transparency, child: button)
      : button;

  /// Whether [sentence], followed by the seal and laid out at [maxWidth],
  /// leaves one word alone on a line before the last. Words joined by a
  /// no-break space count as more than one word, so a short title on a
  /// line of its own is fine. Each line's first character comes from x = 0
  /// on that line, as _FadeTitle finds it (getLineBoundary misreports a
  /// line's start on the web). With no [seal] (it's on the hero print),
  /// the sentence is laid out alone.
  bool _leavesAWordAlone(String sentence, TextStyle style, TextScaler scaler,
      Size? seal, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(style: style, children: [
        TextSpan(text: sentence),
        if (seal != null)
          const WidgetSpan(
              alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
      ]),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    );
    if (seal != null) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
            size: seal, alignment: PlaceholderAlignment.middle),
      ]);
    }
    painter.layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics();
    int startOf(LineMetrics line) => painter
        .getPositionForOffset(Offset(0, line.baseline - line.ascent / 2))
        .offset;
    var alone = false;
    for (var i = 0; i + 1 < lines.length && !alone; i++) {
      final start = startOf(lines[i]).clamp(0, sentence.length);
      final end = startOf(lines[i + 1]).clamp(start, sentence.length);
      final words = sentence.substring(start, end).trim();
      alone = words.isNotEmpty &&
          !words.contains(' ') &&
          !words.contains(' ');
    }
    painter.dispose();
    return alone;
  }

  /// Whether laying out [sentence], followed by the seal, at [maxWidth]
  /// breaks inside a word: whether a word, such as a short title kept whole
  /// with what is joined to it, is wider than the line. The widest word is
  /// measured on a layout of unbounded width, where nothing is broken: a
  /// layout made at [maxWidth] leaves out a word it had to break, so its
  /// minimum width can't show one.
  bool _breaksAWord(String sentence, TextStyle style, TextScaler scaler,
      Size? seal, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(style: style, children: [
        TextSpan(text: sentence),
        if (seal != null)
          const WidgetSpan(
              alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
      ]),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    );
    if (seal != null) {
      painter.setPlaceholderDimensions([
        PlaceholderDimensions(
            size: seal, alignment: PlaceholderAlignment.middle),
      ]);
    }
    painter.layout();
    final breaks = painter.minIntrinsicWidth > maxWidth;
    painter.dispose();
    return breaks;
  }
}

// A Hanko secondary tile with a word on it ("Retry"): sumi 3 with a 1 px
/// edge outline, Jost 600 15 washi, 48 dp tall. Its own semantics node
/// (container; question 102, as the Calendar's and Activity's tiles since
/// dd45bd1), so a screen reader finds one button named for its word, with
/// its own tap, wherever the tile is placed. Here the page already gave it
/// a node of its own (checked on 2026-10-30); in the Calendar's and
/// Activity's notes, a tile without it folded into the note, which then
/// read as one long button.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: AppTheme.hankoSans(
                      fontSize: 15, weight: FontWeight.w600, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Quick Add Sheet ──────────────────────────────────────────
Future<String?> _showQuickAddSheet(BuildContext context, Anime anime) {
  return showHanjListSheet(context: context, anime: anime);
}

// ── Unified Hanj List Sheet — used by home + anime detail ───
Future<String?> showHanjListSheet({
  required BuildContext context,
  required Anime anime,
  String? currentStatus,
}) {
  final firestoreService = FirestoreService();
  // Shelves picked before the show is on the list (round seven, see
  // _ShelfPicker). Made here, once per sheet, because the builder below can
  // run again while the sheet animates.
  final shelves = _ShelfDraft();

  // Hanko (question 46): each status is told by its sharp icon and its
  // word, as Detail's status button tells it, not by a colour of its own.
  // The four coloured tiles' labels measured 2.18-3.12:1, under AA. Now
  // every label is washi on sumi 3 (13.02:1), or sumi on washi once
  // chosen (15.34:1), and each tile's edge outline is 3.74:1 on the sheet.
  const statuses = [
    ('WATCHING',      'Watching',      Icons.play_circle_sharp),
    ('PLAN_TO_WATCH', 'Plan to watch', Icons.bookmark_sharp),
    ('COMPLETED',     'Completed',     Icons.check_circle_sharp),
    ('DROPPED',       'Dropped',       Icons.cancel_sharp),
  ];

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      String? selected = currentStatus;

      Widget tile((String, String, IconData) s, BuildContext ctx,
          StateSetter setLocal) {
        final isSelected = selected == s.$1;
        final ink = isSelected ? AppTheme.hankoSumi : AppTheme.hankoWashi;
        return Semantics(
          button: true,
          selected: isSelected,
          child: Material(
            color: isSelected ? AppTheme.hankoWashi : AppTheme.hankoSumi3,
            animationDuration: const Duration(milliseconds: 150),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              side: isSelected
                  ? BorderSide.none
                  : const BorderSide(color: AppTheme.hankoEdge),
            ),
            child: InkWell(
              onTap: () async {
                // 1. Highlight immediately
                setLocal(() => selected = s.$1);
                // 2. Close sheet and return result
                await Future.delayed(const Duration(milliseconds: 180));
                // Dismissed during those 180 ms: ctx is gone and the
                // caller already got null, so don't pop and don't save.
                if (!ctx.mounted) return;
                Navigator.pop(ctx, s.$1);
                // 3. Save to Firestore (fire and forget — UI already updated)
                // Caught: uncaught, a rejected write was a fatal Crashlytics report.
                firestoreService.addAnimeToList(anime: anime, status: s.$1)
                    .catchError((_) {});
                // Achievements (stage 4): the entry as these writes leave
                // it, the draft's shelf and favourite included, as one
                // action; the slip waits for the sheet to close, on the
                // screen that opened it.
                if (Achievements.replaceCards) {
                  final staged = shelves.staged.isNotEmpty || shelves.favourite == true;
                  if (context.mounted) {
                    AchievementSlip.expect(context,
                        feedback: AchievementSlip.sheetClosing);
                  }
                  AchievementsService.instance.noteAction(anime.id, {
                    'animeId': anime.id,
                    'title': anime.titleEnglish ?? anime.title,
                    'imageUrl': anime.imageUrl,
                    'episodes': anime.episodes,
                    'averageScore': anime.averageScore,
                    'genres': anime.genres,
                    'status': s.$1,
                    'addedAt': FieldValue.serverTimestamp(),
                    'lastWatched': FieldValue.serverTimestamp(),
                    if (staged) ...{
                      'tags': HanjShelves.tagsFor(
                          shelf: shelves.staged.firstOrNull,
                          favourite: shelves.favourite == true),
                      'tagsUpdatedAt': FieldValue.serverTimestamp(),
                    },
                    if (shelves.favourite == true)
                      'favouritedAt': FieldValue.serverTimestamp(),
                  }).catchError((Object _) {});
                }
                // 4. Shelves picked while the show wasn't on the list go on
                // its new entry, in a write of their own after it, with the
                // favourite mark if it was marked too (P7).
                final favourite = shelves.favourite == true;
                if (shelves.staged.isNotEmpty || favourite) {
                  await _saveDraftShelves(
                      context,
                      anime.id,
                      HanjShelves.tagsFor(
                          shelf: shelves.staged.firstOrNull,
                          favourite: favourite),
                      favourite: favourite);
                }
              },
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(s.$3, color: ink, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          s.$2,
                          style: AppTheme.hankoSans(
                              fontSize: 15,
                              weight: FontWeight.w500,
                              color: ink,
                              height: 1.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      // Two tiles side by side, as tall as the taller one when a label
      // wraps at large text.
      Widget pair(int first, BuildContext ctx, StateSetter setLocal) =>
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tile(statuses[first], ctx, setLocal)),
                const SizedBox(width: 8),
                Expanded(child: tile(statuses[first + 1], ctx, setLocal)),
              ],
            ),
          );

      // The sheet's head: the handle, and the show's cover beside its name,
      // on a wash of the cover's colours, as Home's feature band (round
      // seven).
      Widget head() => Stack(
            children: [
              Positioned.fill(
                child: _ArtWash(
                  url: anime.imageUrl,
                  base: AppTheme.hankoSumi2,
                  wordsFrom: AppTheme.hankoGutter + 48 + 12,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, 10, AppTheme.hankoGutter, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.hankoEdge.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // The show's cover beside its name, as the sheet's head
                    // in hanko.html draws it: pictures for what the show
                    // is. 48 x 68 since round seven's bigger posters, from
                    // 36 x 51.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HankoCover(url: anime.imageUrl, width: 48, height: 68),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Three lines, fading where a cut remains (H2
                              // QA W2). Shared with Detail. Set from the
                              // left now, beside the cover; it was centred.
                              _FadeTitle(
                                anime.titleEnglish ?? anime.title,
                                maxLines: 3,
                                textAlign: TextAlign.start,
                                style: AppTheme.hankoSerif(
                                    fontSize: 20, height: 1.15),
                              ),
                              const SizedBox(height: 4),
                              // Stone-hi: quiet words on a cover's wash.
                              Text(
                                'Where does this one live?',
                                style: AppTheme.hankoSans(
                                    fontSize: AppTheme.hankoLabelSize,
                                    color: AppTheme.hankoStoneHi,
                                    height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

      return StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          // hanko.html's sheet: sumi 2, 6 px top corners, the 20 px gutter.
          // Since round seven it scrolls, and rises above the keyboard while
          // a new shelf is named.
          decoration: const BoxDecoration(
            color: AppTheme.hankoSumi2,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppTheme.hankoSheetRadius)),
          ),
          clipBehavior: Clip.antiAlias,
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.hankoGutter),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pair(0, ctx, setLocal),
                      const SizedBox(height: 8),
                      pair(2, ctx, setLocal),
                      // Shelves (round seven): the sheet's one hairline sets
                      // them off from where the show lives.
                      const SizedBox(height: 20),
                      Container(height: 1, color: AppTheme.hankoHairline),
                      const SizedBox(height: 16),
                      _ShelfPicker(animeId: anime.id, draft: shelves),
                      if (currentStatus != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          button: true,
                          child: Material(
                            color: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.hankoRadius),
                              side: const BorderSide(color: AppTheme.hankoEdge),
                            ),
                            child: InkWell(
                              onTap: () => Navigator.pop(ctx, '__REMOVE__'),
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: AppTheme.hankoPressWash,
                              hoverColor: AppTheme.hankoPressWash,
                              borderRadius:
                                  BorderRadius.circular(AppTheme.hankoRadius),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                    minHeight: AppTheme.hankoTouch),
                                child: Center(
                                  child: Text(
                                    'Remove from list',
                                    textAlign: TextAlign.center,
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoBodySize,
                                        weight: FontWeight.w500,
                                        color: AppTheme.hankoStone,
                                        height: 1.2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Saves the shelf picked in the status sheet for a show that wasn't on the
/// list (round seven), once a status has been chosen for it: one update of
/// the new entry's tags, sent after the status write, so it lands after the
/// entry exists. Since 2026-11-05 [names] holds one shelf at most, and the
/// tags become exactly it (HanjShelves). Since P7 they can hold the
/// favourite mark too ([favourite]), which also stamps favouritedAt, the
/// time Profile orders favourites by. Awaited and caught: uncaught, a
/// refused write would reach Crashlytics as fatal. A failure says so on the
/// page the sheet was opened from, naming no cause; offline, the write
/// waits for the connection.
Future<void> _saveDraftShelves(
    BuildContext context, String animeId, List<String> names,
    {required bool favourite}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || animeId.isEmpty) return;
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('animeList')
        .doc(animeId)
        .update({
      'tags': names,
      'tagsUpdatedAt': FieldValue.serverTimestamp(),
      if (favourite) 'favouritedAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    if (!context.mounted) return;
    final shelf = names.any((n) => n != HanjShelves.favourites);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(!favourite
          ? 'Couldn’t save its shelves. Try again.'
          : shelf
              ? 'Couldn’t save its shelf and favourite. Try again.'
              : 'Couldn’t save that favourite. Try again.'),
    ));
  }
}

/// The shelf picked in the status sheet before the show is on the list
/// (round seven): kept for the sheet's life, then saved with the status.
/// One at most since 2026-11-05.
class _ShelfDraft {
  final Set<String> staged = {};

  /// The favourite mark as picked before the show is on the list (P7), or
  /// null while it hasn't been touched.
  bool? favourite;
}

/// Shelving, in the status sheet (round seven; Shahid, 2026-11-03: "I am
/// not able to shelve an anime"). A shelf is a name in the `tags` list on
/// the show's own entry, users/{uid}/animeList/{id}: the field Profile's
/// Shelves section reads (profile_screen.dart, _shelves) and
/// FirestoreService.updateTags writes. The rules let the owner write the
/// entry (firestore.rules, animeList), so no new rule is needed.
///
/// Since 2026-11-05 there are two shelves, Masterpiece and Favourites, and
/// a show sits on one at most (HanjShelves; Shahid: "masterpiece and
/// favourites should be the only shelves"). Picking one takes the show off
/// the other, and picking the one it's on takes it off, so it can sit on
/// neither. "New shelf" is switched off (_newShelves). On the list, a pick
/// is written at once: the entry's tags become that one name, or none, with
/// tagsUpdatedAt as updateTags stamps it, awaited and caught; a refused
/// write puts the chips back and says so. That write is also what cleans
/// an entry's names from before the rule, which are otherwise only read
/// (HanjShelves.shelfOf). Off the list there is no entry to tag yet, so the
/// pick waits in [draft] and is saved with the show when a status is
/// chosen (_saveDraftShelves), and the sheet says so.
///
/// It reads once, as the sheet opens: the show's entry, for its shelf and
/// whether it is on the list. Shelves are readable by any signed-in user,
/// as Profile says, so the sheet says it too.
///
/// Since P7 (HanjShelves.favouritesApart) the shelves are Masterpiece and
/// Hidden gems, and Favourite is a mark of its own above them, beside any
/// shelf (Shahid, 2026-11-06: "put favourite so users can show off their
/// favourites on the profile"). It is still the name "Favourites" in the
/// entry's tags, so each write sets the tags whole, the shelf and the mark
/// (HanjShelves.tagsFor), and either toggle keeps the other. Marking also
/// stamps favouritedAt, the time Profile orders favourites by; unmarking
/// clears it. Off the list the mark waits in [draft] with the shelf.
class _ShelfPicker extends StatefulWidget {
  const _ShelfPicker({required this.animeId, required this.draft});

  final String animeId;
  final _ShelfDraft draft;

  @override
  State<_ShelfPicker> createState() => _ShelfPickerState();
}

class _ShelfPickerState extends State<_ShelfPicker> {
  /// "New shelf" and its name field, switched off since there are only the
  /// two shelves (2026-11-05). Kept, as the app keeps its other unused
  /// parts.
  static const bool _newShelves = false;

  bool _loading = true;
  bool _failed = false;
  bool _onList = false;
  bool _naming = false;
  String? _error;

  /// This show's shelf, one at most: as saved, or as picked while it is
  /// off the list.
  final Set<String> _mine = {};

  /// Whether this show is one of your favourites (P7): as saved, or as
  /// marked while it is off the list.
  bool _favourite = false;

  /// Every shelf, in the order the chips show them.
  final List<String> _all = [];

  /// The number of the newest write, so a failed write only puts back
  /// chips that no later tap has changed.
  int _write = 0;

  final _name = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'new shelf name');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Opens the name field and gives it the keyboard. Asked for outright, not
  /// with autofocus: autofocus does nothing while anything else in the sheet
  /// has focus, and a chip that was just tapped can (seen on the web, where
  /// the tap focused the chip and Enter then took the shelf off again).
  void _startNaming() {
    setState(() => _naming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _naming) _nameFocus.requestFocus();
    });
  }

  CollectionReference<Map<String, dynamic>>? get _list {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('animeList');
  }

  /// A tags field's shelf names, as Profile reads them: strings, trimmed,
  /// empty ones left out.
  static Set<String> _names(Object? tags) => {
        if (tags is List)
          for (final t in tags.whereType<String>())
            if (t.trim().isNotEmpty) t.trim(),
      };

  /// Reads the show's entry. Called from initState, so it changes nothing
  /// before its first await; Retry sets the spinner. An entry tagged before
  /// the rule shows on the one shelf HanjShelves.shelfOf gives it, and
  /// nothing is written until a shelf is picked.
  Future<void> _load() async {
    final list = _list;
    if (list == null || widget.animeId.isEmpty) return;
    try {
      final entry = await list.doc(widget.animeId).get();
      if (!mounted) return;
      final tags = _names(entry.data()?['tags']);
      final saved = HanjShelves.shelfOf(tags);
      final staged = widget.draft.staged;
      setState(() {
        _onList = entry.exists;
        _mine
          ..clear()
          ..addAll(staged.isNotEmpty ? staged : {?saved});
        _favourite = widget.draft.favourite ?? HanjShelves.isFavourite(tags);
        _all
          ..clear()
          ..addAll(HanjShelves.all);
        _loading = false;
      });
    } catch (_) {
      // Offline with no copy on the device, or refused: say so, with Retry.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Puts the show on [name], or takes it off when it's there already. One
  /// shelf at a time, so the show leaves the other. On the list, its tags
  /// become just [name], or none, and the favourite mark if it has one (P7).
  Future<void> _toggle(String name) async {
    final before = {..._mine};
    final on = !_mine.contains(name);
    setState(() {
      _mine
        ..clear()
        ..addAll({if (on) name});
      if (!_all.contains(name)) _all.add(name);
      _error = null;
    });
    if (!_onList) {
      widget.draft.staged
        ..clear()
        ..addAll(_mine);
      return;
    }
    final list = _list;
    if (list == null) return;
    final write = ++_write;
    // Achievements (stage 4): a shelf can earn one (Named a masterpiece,
    // Hidden gem); its slip waits for this sheet to close.
    if (Achievements.replaceCards) {
      AchievementSlip.expect(context, feedback: AchievementSlip.sheetClosing);
      AchievementsService.instance.noteAction(widget.animeId, {
        'tags': HanjShelves.tagsFor(shelf: on ? name : null, favourite: _favourite),
        'tagsUpdatedAt': FieldValue.serverTimestamp(),
      }).catchError((Object _) {});
    }
    try {
      await list.doc(widget.animeId).update({
        'tags': HanjShelves.tagsFor(shelf: on ? name : null, favourite: _favourite),
        'tagsUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Refused, or the entry has gone: the chips go back unless a later
      // tap has changed them since, and the line says so, naming no cause.
      // Offline, the write waits for the connection and the chip stays.
      if (!mounted || _write != write) return;
      setState(() {
        _mine
          ..clear()
          ..addAll(before);
        _error = 'Couldn’t save that shelf. Try again.';
      });
    }
  }

  /// Marks the show as a favourite, or unmarks it (P7), keeping its shelf.
  /// On the list it is written at once, as a shelf is: the tags whole, and
  /// favouritedAt stamped or cleared; a refused write puts the chip back
  /// and says so. Off the list it waits in the draft for a status.
  Future<void> _toggleFavourite() async {
    final before = _favourite;
    final on = !before;
    setState(() {
      _favourite = on;
      _error = null;
    });
    if (!_onList) {
      widget.draft.favourite = on;
      return;
    }
    final list = _list;
    if (list == null) return;
    final write = ++_write;
    // Achievements (stage 4): the first Favourite earns one; its slip waits
    // for this sheet to close.
    if (Achievements.replaceCards) {
      AchievementSlip.expect(context, feedback: AchievementSlip.sheetClosing);
      AchievementsService.instance.noteAction(widget.animeId, {
        'tags': HanjShelves.tagsFor(shelf: _mine.firstOrNull, favourite: on),
        'tagsUpdatedAt': FieldValue.serverTimestamp(),
        'favouritedAt': on ? FieldValue.serverTimestamp() : FieldValue.delete(),
      }).catchError((Object _) {});
    }
    try {
      await list.doc(widget.animeId).update({
        'tags': HanjShelves.tagsFor(shelf: _mine.firstOrNull, favourite: on),
        'tagsUpdatedAt': FieldValue.serverTimestamp(),
        'favouritedAt': on ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });
    } catch (_) {
      if (!mounted || _write != write) return;
      setState(() {
        _favourite = before;
        _error = 'Couldn’t save that favourite. Try again.';
      });
    }
  }

  void _addNamed() {
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    _name.clear();
    setState(() => _naming = false);
    if (name.isEmpty) return;
    final existing = _all.firstWhere(
        (s) => s.toLowerCase() == name.toLowerCase(),
        orElse: () => name);
    if (!_mine.contains(existing)) _toggle(existing);
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // Signed out, or a show with no id: nothing to shelve.
    if (_list == null || widget.animeId.isEmpty) return const SizedBox.shrink();
    final quiet = AppTheme.hankoSans(
        fontSize: AppTheme.hankoLabelSize,
        color: AppTheme.hankoStone,
        height: 1.35);
    final said = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize, height: 1.35);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (HanjShelves.favouritesApart) ...[
          _favouriteRow(quiet),
          const SizedBox(height: 16),
        ],
        Semantics(
          header: true,
          child: Text('Shelves', style: AppTheme.hankoSerif(height: 1.3)),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.visibility_sharp,
                  size: 16, color: AppTheme.hankoStone),
            ),
            const SizedBox(width: 6),
            Expanded(
              // A favourite sits on the same entry as a shelf (P7), so the
              // line names both. A word joiner keeps "signed-in" whole at
              // large text, as the lede keeps a hyphenated title.
              child: Text(
                  HanjShelves.favouritesApart
                      ? 'Favourites and shelves are visible to signed-\u2060in '
                          'Hanj users.'
                      : 'Shelves are visible to signed-in Hanj users.',
                  style: quiet),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_loading)
          const SizedBox(
            height: AppTheme.hankoTouch,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AppTheme.hankoWashi, strokeWidth: 1.5),
              ),
            ),
          )
        else if (_failed)
          Row(
            children: [
              Expanded(
                child: Text('Couldn’t load your shelves just now.',
                    style: said),
              ),
              const SizedBox(width: 12),
              _TextTile(label: 'Retry', onTap: _retry),
            ],
          )
        else ...[
          // No spacing: each chip's focus ring leaves 4 dp round it, so the
          // chips stand 8 dp apart, and 12 between rows.
          Wrap(
            children: [
              for (final name in _all)
                _ShelfChip(
                  label: name,
                  selected: _mine.contains(name),
                  onTap: () => _toggle(name),
                ),
              if (_newShelves && !_naming)
                _ShelfChip(
                  label: 'New shelf',
                  icon: Icons.add_sharp,
                  onTap: _startNaming,
                ),
            ],
          ),
          if (_newShelves && _naming)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(child: _nameField()),
                  const SizedBox(width: 8),
                  _TextTile(label: 'Add', onTap: _addNamed),
                ],
              ),
            ),
          if (!_onList && (_mine.isNotEmpty || _favourite))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  !_favourite
                      ? 'Choose where it lives to save its shelf.'
                      : _mine.isNotEmpty
                          ? 'Choose where it lives to save its shelf and '
                              'favourite.'
                          : 'Choose where it lives to save it as a favourite.',
                  style: said),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, style: said),
            ),
        ],
      ],
    );
  }

  /// The favourite mark (P7): the sheet's own chip with a heart, first and
  /// apart from the shelves, beside what it does. Washi, not coral: coral is
  /// the seal. While the entry is read, or if it couldn't be, the chip keeps
  /// its place unseen, so nothing jumps and a favourite never shows as
  /// unmarked; the line under Shelves says when it failed.
  Widget _favouriteRow(TextStyle quiet) {
    final known = !_loading && !_failed;
    return Row(
      children: [
        ExcludeFocus(
          excluding: !known,
          child: Visibility(
            visible: known,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _ShelfChip(
              label: 'Favourite',
              icon: Icons.favorite_border_sharp,
              selected: _favourite,
              onTap: _toggleFavourite,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('Shown first on your profile.', style: quiet)),
      ],
    );
  }

  /// The new shelf's name: Hanko's field, sumi 3 with the edge outline and
  /// square corners, washi when focused. Forty characters at most, without
  /// a counter.
  Widget _nameField() {
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      borderSide: const BorderSide(color: AppTheme.hankoEdge),
    );
    return TextField(
      controller: _name,
      focusNode: _nameFocus,
      maxLength: 40,
      buildCounter: (_,
              {required currentLength, required isFocused, maxLength}) =>
          null,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _addNamed(),
      cursorColor: AppTheme.hankoWashi,
      style: AppTheme.hankoSans(fontSize: 15, height: 1.3),
      decoration: InputDecoration(
        hintText: 'Name the shelf',
        hintStyle: AppTheme.hankoSans(
            fontSize: 15, color: AppTheme.hankoStone, height: 1.3),
        filled: true,
        fillColor: AppTheme.hankoSumi3,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: edge,
        enabledBorder: edge,
        focusedBorder: edge.copyWith(
            borderSide: const BorderSide(color: AppTheme.hankoWashi)),
      ),
    );
  }
}

/// A shelf in the status sheet (round seven): Hanko's chip, drawn 36 dp tall
/// (AppTheme.hankoChipHeight) in a 48 dp target, square corners, Jost 500
/// 14. Off: sumi 3 with the edge outline; on: washi with a sumi label and a
/// check, as a chosen status tile; "New shelf" carries a plus instead, and
/// Favourite (P7) a heart while it's off. Its
/// own semantics node, a toggle named for the shelf, with the InkWell's tap
/// and focus inside it (question 119). The InkWell covers the whole target,
/// so the chip draws its own press and hover washes, as +1 does, and
/// keyboard focus draws a washi ring 2 dp outside it, which shows on a washi
/// chip as on a sumi one.
class _ShelfChip extends StatefulWidget {
  const _ShelfChip({
    required this.label,
    required this.onTap,
    this.selected,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;

  /// On or off for a shelf; null for "New shelf", an action.
  final bool? selected;
  final IconData? icon;

  @override
  State<_ShelfChip> createState() => _ShelfChipState();
}

class _ShelfChipState extends State<_ShelfChip> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected == true;
    final ink = on ? AppTheme.hankoSumi : AppTheme.hankoWashi;
    final base = on ? AppTheme.hankoWashi : AppTheme.hankoSumi3;
    final fill = _pressed || _hovered
        ? Color.alphaBlend(
            on ? const Color(0x1A121110) : AppTheme.hankoPressWash, base)
        : base;
    final mark = on ? Icons.check_sharp : widget.icon;
    return Semantics(
      container: true,
      button: true,
      toggled: widget.selected,
      label: widget.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: AppTheme.hankoTouch),
              child: Center(
                widthFactor: 1,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppTheme.hankoRadius + 2),
                    border: Border.all(
                        color: _focused
                            ? AppTheme.hankoWashi
                            : Colors.transparent,
                        width: 2),
                  ),
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(
                        minHeight: AppTheme.hankoChipHeight),
                    padding: EdgeInsets.fromLTRB(
                        mark == null ? 14 : 10, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius:
                          BorderRadius.circular(AppTheme.hankoRadius),
                      border: Border.all(
                          color: on ? AppTheme.hankoWashi : AppTheme.hankoEdge),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (mark != null) ...[
                          Icon(mark, size: 16, color: ink),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.hankoSans(
                                fontSize: 14,
                                weight: FontWeight.w500,
                                color: ink,
                                height: 1.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Import Pending Banner ─────────────────────────────────────
/// Home's way of opening a page: push it, then re-read the list once it has
/// closed (_HomeScreenState._open, item c).
typedef _Open = Future<void> Function(Route<void> route);

class _ImportPendingBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  final _Open open;
  const _ImportPendingBanner({required this.onDismiss, required this.open});

  @override
  Widget build(BuildContext context) {
    // Hanko (question 46): a raised sumi 2 note with square corners instead
    // of a coral-framed card, so it reads as a notice for you rather than
    // part of your record, without a colour of its own. "Import" is the
    // one washi tile, the main action; "Dismiss" is quiet.
    //
    // importPending only records the import you picked in onboarding. No
    // import runs on its own and nothing notifies anyone, so the note no
    // longer says "We'll notify you when it's ready": it says what is
    // true, and both taps do what they did.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 0, AppTheme.hankoGutter, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.hankoSumi2,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Finish your import',
                    style: AppTheme.hankoSerif(height: 1.3)),
              ),
              const SizedBox(height: 4),
              Text(
                "Bring your list over from AniList or MyAnimeList whenever "
                "you’re ready.",
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    color: AppTheme.hankoStone,
                    height: 1.4),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tile(
                    'Import',
                    main: true,
                    onTap: () => open(MaterialPageRoute(
                        builder: (_) => const AnilistImportScreen())),
                  ),
                  _tile('Dismiss', main: false, onTap: onDismiss),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// hanko.html's sheet buttons: the main tile in washi with a sumi label,
  /// the quiet one with no fill and a washi label. 48 dp tall, square
  /// corners, the 8% washi press. Each is its own semantics node
  /// (container; question 102), so a screen reader finds "Import" and
  /// "Dismiss" as two buttons, each with its own tap, apart from the note,
  /// wherever the note is placed. Here they already had nodes of their own
  /// (checked on 2026-10-30); the container keeps it so.
  static Widget _tile(String label,
      {required bool main, required VoidCallback onTap}) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: main ? AppTheme.hankoWashi : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: main ? const Color(0x14121110) : AppTheme.hankoPressWash,
          hoverColor: main ? const Color(0x14121110) : AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: AppTheme.hankoSans(
                    fontSize: 15,
                    weight: main ? FontWeight.w600 : FontWeight.w500,
                    color: main ? AppTheme.hankoSumi : AppTheme.hankoWashi,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tonight's Drop Card ──────────────────────────────────────
class _TonightCard extends StatefulWidget {
  final Anime anime;
  final _Open open;
  const _TonightCard({required this.anime, required this.open});

  @override
  State<_TonightCard> createState() => _TonightCardState();
}

class _TonightCardState extends State<_TonightCard>
    with SingleTickerProviderStateMixin {
  String? _savedStatus; // null = not saved
  late AnimationController _bookmarkCtrl;
  late Animation<double> _bookmarkScale;

  @override
  void initState() {
    super.initState();
    // Hanko's press: in to 1.06 and back in 120 ms, one small move of
    // feedback (it was 1.4 over 300 ms, which overlapped the card).
    _bookmarkCtrl = AnimationController(
      vsync: this,
      duration: AppTheme.hankoSealPress,
    );
    _bookmarkScale = TweenSequence([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: AppTheme.hankoSealPressScale),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: AppTheme.hankoSealPressScale, end: 1.0),
          weight: 50),
    ]).animate(CurvedAnimation(parent: _bookmarkCtrl, curve: Curves.easeOut));
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('animeList').doc(widget.anime.id)
          .get();
      if (mounted && doc.exists) {
        setState(() => _savedStatus = doc.data()?['status'] as String?);
      }
    } catch (_) {
      // Offline with no cached copy, get() throws `unavailable`. Uncaught, that
      // went to Crashlytics as fatal on every offline cold start (main.dart's
      // PlatformDispatcher.onError). The bookmark just stays unsaved.
    }
  }

  @override
  void dispose() {
    _bookmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _onBookmarkTap() async {
    final status = await _showQuickAddSheet(context, widget.anime);
    if (status != null && mounted) {
      setState(() => _savedStatus = status);
      // With "remove animations" on, the icon simply changes.
      if (!MediaQuery.disableAnimationsOf(context)) {
        _bookmarkCtrl.forward(from: 0);
      }
    }
  }

  // Hanko's sharp icons for a saved status: its shape, not a colour, says
  // which list the show is on.
  static const _hankoStatusIcon = {
    'WATCHING': Icons.play_circle_sharp,
    'PLAN_TO_WATCH': Icons.bookmark_sharp,
    'COMPLETED': Icons.check_circle_sharp,
    'DROPPED': Icons.cancel_sharp,
  };

  // The band's print flies to the show's page (P6).
  void _openShow() => widget.open(
      _HomeScreenState._showRoute(context, widget.anime, place: 'band'));

  @override
  Widget build(BuildContext context) {
    // Since Hanko (stage H4, item d) Tonight's Drop shows only when the
    // watchlist has nothing the pick can show. Since round seven it is
    // drawn as the pick is, on Home's feature band (_PickBand): no text on
    // the art, the crowd's score in indigo, and the bookmark as an outlined
    // 48 dp tile beside the band's button. The "Continue" pill went in H4:
    // it did what tapping the card does, and said "Continue" about a show
    // you haven't started.
    final anime = widget.anime;
    final title = anime.titleEnglish ?? anime.title;
    final score = anime.averageScore;
    final scoreText = score == null ? null : (score / 10).toStringAsFixed(1);
    final isSaved = _savedStatus != null;
    final icon = isSaved
        ? (_hankoStatusIcon[_savedStatus] ?? Icons.bookmark_sharp)
        : Icons.bookmark_border_sharp;
    final facts = [
      if (anime.genres.isNotEmpty) anime.genres.first,
      if (anime.episodes != null)
        anime.episodes == 1 ? '1 episode' : '${anime.episodes} episodes',
    ].join(' · ');

    return _PickBand(
      // The typographic apostrophe: Shippori draws the typewriter one as a
      // straight tick (questions 109 and 154).
      heading: 'Tonight’s drop',
      imageUrl: anime.imageUrl,
      title: title,
      facts: facts.isEmpty ? null : facts,
      score: scoreText,
      // Where it comes from, which the slot never said: Home's season
      // chart, a new place down it each day (_loadChart).
      note: 'From this season’s chart',
      onOpen: _openShow,
      heroTag: _HomeScreenState._printTag('band', anime.id),
      trailing: ScaleTransition(
        scale: _bookmarkScale,
        child: IconButton(
          onPressed: _onBookmarkTap,
          tooltip: isSaved ? 'On your list' : 'Add to your list',
          icon: Icon(icon, size: 20, color: AppTheme.hankoWashi),
          style: const ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(AppTheme.hankoSumi3),
            overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
            splashFactory: NoSplash.splashFactory,
            side: WidgetStatePropertyAll(BorderSide(color: AppTheme.hankoEdge)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
            )),
            fixedSize: WidgetStatePropertyAll(
                Size(AppTheme.hankoTouch, AppTheme.hankoTouch)),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
          ),
        ),
      ),
    );
  }
}

/// From your watchlist tonight (Hanko stage H4, item d; round seven): the
/// newest show on your own watchlist (_HomeScreenState._watchlistPick), in
/// the slot Tonight's Drop (the same season pick for everyone) used to
/// hold, drawn on Home's feature band (_PickBand). It shows what the entry
/// holds: its first genre, its episode count, and AniList's score as it was
/// when the show was added, left out for an old MyAnimeList import, whose
/// stored score is MyAnimeList's (Detail leaves it out too). "On your
/// watchlist since March" still waits for a date the list can vouch for
/// (question 27); "Newest on your watchlist" is said only when it is true.
/// The whole pick is one button that opens the show.
class _WatchlistPick extends StatelessWidget {
  const _WatchlistPick({
    required this.entry,
    required this.newest,
    required this.onOpen,
    this.onStart,
    this.starting = false,
    this.footer,
  });

  final Map<String, dynamic> entry;

  /// The pick is the watchlist's newest entry, of two or more.
  final bool newest;
  final VoidCallback onOpen;

  /// Puts the pick on Watching (Print Room P2-2). Null draws no button.
  final VoidCallback? onStart;

  /// [onStart]'s write is on its way.
  final bool starting;

  /// The watchlist link, under the pick.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final title = (entry['title'] as String? ?? '').trim();
    final episodes = entry['episodes'] as int?;
    final genres = [
      ...?(entry['genres'] as List<dynamic>?)?.whereType<String>(),
    ];
    final facts = [
      if (genres.isNotEmpty) genres.first,
      if (episodes != null) episodes == 1 ? '1 episode' : '$episodes episodes',
    ].join(' · ');
    final score = _HomeScreenState._isMalImport(entry)
        ? null
        : entry['averageScore'] as num?;
    final onStart = this.onStart;
    return _PickBand(
      heading: 'From your watchlist tonight',
      imageUrl: entry['imageUrl'] as String?,
      title: title,
      facts: facts.isEmpty ? null : facts,
      score: score == null ? null : (score / 10).toStringAsFixed(1),
      note: newest ? 'Newest on your watchlist' : null,
      onOpen: onOpen,
      heroTag: _HomeScreenState._printTag(
          'band', entry['animeId']?.toString() ?? ''),
      action: onStart == null
          ? null
          : _StartWatching(title: title, starting: starting, onTap: onStart),
      footer: footer,
    );
  }
}

/// Home's feature band (round seven): one show given room under a heading,
/// for tonight's watchlist pick and for Tonight's drop. Shahid, 2026-11-03:
/// "mostly everything is bland and just letters with black background".
/// Behind it, the show's own cover as a wash of its colours (_ArtWash); on
/// it, the cover as a print (_PickPrint), and beside the print the title in
/// Shippori, the facts, AniList's score in indigo (the crowd's colour), and
/// a note at the print's foot. Print and words are one button; a [trailing]
/// control (Tonight's drop's bookmark) sits beside it and a [footer] (the
/// watchlist link) under it, each its own button. The band runs the width
/// of its column, and its words keep the gutter.
class _PickBand extends StatelessWidget {
  const _PickBand({
    required this.heading,
    required this.imageUrl,
    required this.title,
    required this.onOpen,
    required this.heroTag,
    this.facts,
    this.score,
    this.note,
    this.trailing,
    this.action,
    this.footer,
  });

  final String heading;
  final String? imageUrl;
  final String title;
  final VoidCallback onOpen;

  /// Print Room's print's Hero tag, so it flies to the show's page (P6).
  final Object? heroTag;
  final String? facts;

  /// AniList's score out of 10, one decimal.
  final String? score;
  final String? note;
  final Widget? trailing;

  /// The band's own action (Print Room P2-2: Start watching), under the
  /// words and beside the print, as the mockup lays it. A button of its own,
  /// so it lies over the band's button, in room the words keep for it
  /// ([actionRoom]), never inside the button's excluded semantics.
  final Widget? action;
  final Widget? footer;

  /// The room under the words for [action]: its 48 dp target, 10 under the
  /// note, so the 40 dp button drawn in it sits 14 under, as the mockup's.
  static const double actionRoom = 10 + AppTheme.hankoTouch;

  /// The print: 96 × 136, from the old pick's 72 × 102.
  static const double printWidth = 96;
  static const double printHeight = 136;

  @override
  Widget build(BuildContext context) {
    // On the wash, quiet words are stone-hi, Hanko's colour for them on a
    // cover's tint; the panel behind them keeps 89% sumi under the words.
    // On Print Room's field (P2) every word is washi, 5.69:1 or better on
    // any field, where stone-hi falls to 3.96:1 on the lightest.
    final meta = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize,
        color: _HomeScreenState._printRoom
            ? AppTheme.hankoWashi
            : AppTheme.hankoStoneHi,
        height: 1.4);
    final facts = this.facts;
    final score = this.score;
    final note = this.note;
    final trailing = this.trailing;
    final footer = this.footer;
    if (_HomeScreenState._printRoom) {
      return _onField(meta, facts, score, note, trailing, footer);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: _ArtWash(url: imageUrl, base: AppTheme.hankoSumi),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(AppTheme.hankoGutter, 20,
              AppTheme.hankoGutter, footer == null ? 22 : 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(heading, style: AppTheme.hankoSerif(height: 1.3)),
              ),
              const SizedBox(height: 14),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // A darker panel behind the words: 70% sumi over the
                  // wash's 64%, 89% in all, which keeps stone-hi and the
                  // crowd's ai at AA whatever the cover. Its edge is a blur
                  // that ends under the print, so it draws no line, and it
                  // runs out to the band's right edge.
                  const Positioned(
                    left: printWidth - 4,
                    top: -20,
                    right: -AppTheme.hankoGutter,
                    bottom: -20,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                                color: Color(0xB3121110), blurRadius: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _row(meta, facts, score, note, trailing),
                ],
              ),
              if (footer != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: footer),
            ],
          ),
        ),
      ],
    );
  }

  /// Print Room's band (P2; DESIGN.md §9.5, frame 02): no art wash, since
  /// Home lays the show's own colour behind the band as a flat field the
  /// width of the page (_HomeScreenState._bandField), and the cover lies on
  /// it as a print. Every word on it is washi, so the darker panel goes;
  /// AniList's score is washi too, since the crowd's ai would fall to about
  /// 2.5:1 on the lightest fields.
  Widget _onField(TextStyle meta, String? facts, String? score, String? note,
      Widget? trailing, Widget? footer) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 20, AppTheme.hankoGutter, footer == null ? 22 : 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(heading, style: AppTheme.hankoSerif(height: 1.3)),
          ),
          const SizedBox(height: 14),
          _row(meta, facts, score, note, trailing),
          if (footer != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: footer),
        ],
      ),
    );
  }

  /// The print and the words, one button, and [trailing] beside them. An
  /// [action] lies over the words' foot, in the room they keep for it.
  Widget _row(TextStyle meta, String? facts, String? score, String? note,
      Widget? trailing) {
    final action = this.action;
    if (action != null) {
      return Stack(
        children: [
          _buttonRow(meta, facts, score, note, trailing),
          Positioned(
            left: printWidth + 16,
            right: 0,
            bottom: 0,
            child: Align(alignment: Alignment.bottomLeft, child: action),
          ),
        ],
      );
    }
    return _buttonRow(meta, facts, score, note, trailing);
  }

  Widget _buttonRow(TextStyle meta, String? facts, String? score,
      String? note, Widget? trailing) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // One semantics node (container) with the InkWell's tap and focus
          // inside it, as the lede (question 119; see
          // _HomeScreenState._buildLede); the print and words are left out
          // of the tree, since the label says them. The InkWell paints on a
          // transparent Material of its own: ink is drawn under a
          // Material's children, so on the page's Material the wash would
          // hide the press and focus washes.
          child: Semantics(
            container: true,
            button: true,
            label: [
              title,
              ?facts,
              if (score != null) 'AniList $score',
              ?note,
            ].join(', '),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onOpen,
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Print Room's print (P2): its shadow shows on the
                      // field, and it asks for the 460 px cover as
                      // _PickPrint did.
                      if (_HomeScreenState._printRoom)
                        HankoPrint(
                          url: imageUrl,
                          width: printWidth,
                          height: printHeight,
                          sharp: true,
                          heroTag: heroTag,
                        )
                      else
                        _PickPrint(url: imageUrl),
                      const SizedBox(width: 16),
                      Expanded(child: _words(meta, facts, score, note)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }

  /// The title, the facts, AniList's score and the note, at least the
  /// print's height, so the note sits at its foot, as Detail's caption.
  /// With an [action], the note keeps [actionRoom] under it for the action.
  Widget _words(TextStyle meta, String? facts, String? score, String? note) {
    final noteText = note == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              note,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  weight: FontWeight.w500,
                  color: _HomeScreenState._printRoom
                      ? AppTheme.hankoWashi
                      : AppTheme.hankoStoneHi,
                  height: 1.3),
            ),
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: printHeight),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FadeTitle(
                title,
                maxLines: 3,
                style: AppTheme.hankoSerif(
                    fontSize: AppTheme.hankoFeaturedSize, height: 1.15),
              ),
              if (facts != null) ...[
                const SizedBox(height: 6),
                Text(facts, style: meta),
              ],
              if (score != null) ...[
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: 'AniList ',
                    style: meta,
                    children: [
                      TextSpan(
                        text: score,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          weight: FontWeight.w500,
                          // Washi on Print Room's field (see _onField).
                          color: _HomeScreenState._printRoom
                              ? AppTheme.hankoWashi
                              : AppTheme.hankoAi,
                          height: 1.4,
                          tabular: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (action != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?noteText,
                const SizedBox(height: actionRoom),
              ],
            )
          else
            ?noteText,
        ],
      ),
    );
  }
}

/// "Start watching" (Print Room P2-2; Shahid, 2026-11-05: "go with your
/// recommendations"): the watchlist band's one main action, as the mockup
/// draws it, in washi with sumi words, Hanko's fill for a screen's one main
/// action (15.3:1). It puts the pick on Watching ([onTap]); while that write
/// is on its way it says "Starting…" and takes no taps.
///
/// Drawn 40 high inside a 48 dp target, as +1 is. The InkWell keeps the
/// whole target, so its tap and focus stay in the button's own node, and
/// the drawn button shows its own washes: sumi at 8% while pressed or
/// hovered, and for keyboard focus the seal's ring, a 2 px sumi line inside
/// its edge and a 2 px washi ring outside it (a washi outline alone would
/// only look like a bigger button).
class _StartWatching extends StatefulWidget {
  const _StartWatching({
    required this.title,
    required this.starting,
    required this.onTap,
  });

  /// The show's title, for what a screen reader hears.
  final String title;
  final bool starting;
  final VoidCallback onTap;

  @override
  State<_StartWatching> createState() => _StartWatchingState();
}

class _StartWatchingState extends State<_StartWatching> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final starting = widget.starting;
    final fill = _pressed || _hovered
        ? Color.alphaBlend(
            AppTheme.hankoSumi.withValues(alpha: 0.08), AppTheme.hankoWashi)
        : AppTheme.hankoWashi;
    return Semantics(
      container: true,
      button: true,
      enabled: !starting,
      label: starting
          ? 'Starting ${widget.title}'
          : 'Start watching ${widget.title}',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: starting ? null : widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ExcludeSemantics(
            child: SizedBox(
              height: AppTheme.hankoTouch,
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                // As wide as its words and 20 either side, the mockup's, not
                // the width of the room it lies in.
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius:
                        BorderRadius.circular(AppTheme.hankoRadius),
                    border: _focused
                        ? Border.all(color: AppTheme.hankoSumi, width: 2)
                        : null,
                    boxShadow: _focused
                        ? const [
                            BoxShadow(
                                color: AppTheme.hankoWashi, spreadRadius: 2),
                          ]
                        : null,
                  ),
                  // At very large text the words shrink to fit the room
                  // beside the print, rather than spill out of the button.
                  child: Center(
                    widthFactor: 1,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        starting ? 'Starting…' : 'Start watching',
                        maxLines: 1,
                        style: AppTheme.hankoSans(
                            fontSize: 15,
                            weight: FontWeight.w600,
                            color: AppTheme.hankoSumi,
                            height: 1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The feature band's print (round seven): 96 × 136 with Hanko's square
/// 2 px corners, a 1 px washi ring at 12% so a dark cover keeps its edge on
/// the wash (as Detail's print), and a shadow under it for depth. At this
/// size the 230 px cover an entry keeps would be soft on the CPH2573
/// (384 px), so for an AniList cover the 460 px one (AniList's extraLarge:
/// the same file under cover/large/ rather than cover/medium/) fades in
/// over it, as Detail's sharp cover does; if that one fails, the stored one
/// stays. The stored one is decoded at full size, as _HankoCover's, so
/// Detail opens on the same image.
class _PickPrint extends StatelessWidget {
  const _PickPrint({required this.url});

  final String? url;

  static const String _cover = 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/';

  /// AniList's 460 px cover for a stored 230 px one, or null.
  static String? sharpOf(String? url) =>
      url != null && url.startsWith('${_cover}medium/')
          ? '${_cover}large/${url.substring('${_cover}medium/'.length)}'
          : null;

  @override
  Widget build(BuildContext context) {
    final base = url;
    final sharp = sharpOf(base);
    Widget none(BuildContext _, String _, Object _) => const SizedBox.shrink();
    return Container(
      width: _PickBand.printWidth,
      height: _PickBand.printHeight,
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        boxShadow: [
          const BoxShadow(
              color: Color(0x8C000000), blurRadius: 18, offset: Offset(0, 8)),
          BoxShadow(
              color: AppTheme.hankoWashi.withValues(alpha: 0.12),
              spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: base == null || base.isEmpty
            ? const SizedBox.expand()
            : Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: base,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    errorWidget: none,
                  ),
                  if (sharp != null)
                    CachedNetworkImage(
                      imageUrl: sharp,
                      fit: BoxFit.cover,
                      fadeInDuration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: none,
                    ),
                ],
              ),
      ),
    );
  }
}

/// A cover's own colours as a field (round seven): the cover decoded 24 px
/// wide and stretched across the field, so it reads as a soft wash of the
/// art with no blur filter (blur is the app's most expensive raster effect,
/// PERF.md S2-2). Under 64% sumi, which keeps washi words on it at AA
/// whatever the cover (washi over white art: 4.7:1). With [wordsFrom] it
/// darkens from there to at least 88%, which keeps stone-hi and the crowd's
/// ai at AA too (ai over white art: 4.7:1); without it, whatever draws
/// quieter words on the field puts its own darker panel behind them, as
/// _PickBand does. It fades into [base] at the top and the bottom.
/// Decoration only: nothing in it reaches the semantics tree.
class _ArtWash extends StatelessWidget {
  const _ArtWash({
    required this.url,
    required this.base,
    this.wordsFrom,
  });

  final String? url;

  /// Where quiet words begin, from the left edge.
  final double? wordsFrom;

  /// The colour the field sits on and fades into: the page's or a sheet's.
  final Color base;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const SizedBox.shrink();
    // On the web the cached provider decodes through the browser at full
    // size whatever size is asked; Flutter's own NetworkImage decodes at the
    // size ResizeImage asks for, from the browser's cache.
    final ImageProvider art =
        kIsWeb ? NetworkImage(u) : CachedNetworkImageProvider(u);
    return ExcludeSemantics(
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final from = wordsFrom;
        final dark = from == null ? 1.0 : (from / width).clamp(0.0, 1.0);
        final lit = from == null ? 1.0 : ((from - 28) / width).clamp(0.0, dark);
        final words = from == null ? 0.64 : 0.88;
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage(art, width: 24),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    base.withValues(alpha: 0.64),
                    base.withValues(alpha: 0.64),
                    base.withValues(alpha: words),
                    base.withValues(alpha: from == null ? 0.64 : 0.9),
                  ],
                  stops: [0, lit, dark, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    base,
                    base.withValues(alpha: 0),
                    base.withValues(alpha: 0),
                    base,
                  ],
                  stops: const [0, 0.22, 0.78, 1],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// ── Print Room (stage P2) ────────────────────────────────────

/// The hero's row (Print Room, P2; DESIGN.md §9.5, frame 02): [sentence] in
/// the width the print leaves it, and beside it the show's print, 96 × 136,
/// lying on the field with the large shadow and a pool of its colour behind
/// it. Your [rating], if there is one, is pressed across the print's
/// lower-left corner as a 44 dp seal, beside the sentence's last words
/// ("sealed it"), so the layout finishes the sentence. Since P7 the seal is
/// 30 dp (_smallSeal).
///
/// The print asks for the 460 px cover (question 167: heroes only) and
/// shows the stored one until it arrives, or for good if it fails. With
/// [onPrint] the print is a button of its own named [printLabel];
/// otherwise it's part of whatever button holds the row.
class _HeroRow extends StatelessWidget {
  const _HeroRow({
    required this.sentence,
    required this.url,
    required this.heroTag,
    this.rating,
    this.printLabel,
    this.onPrint,
  });

  final Widget sentence;
  final String? url;

  /// The print's Hero tag, so it flies to the show's page (P6).
  final Object? heroTag;
  final double? rating;
  final String? printLabel;
  final VoidCallback? onPrint;

  static const double printWidth = 96;
  static const double printHeight = 136;

  /// The print sits 4 under the top of the sentence's first line.
  static const double printTop = 4;

  /// Between the sentence and the print; the seal hangs 18 of its 44 into it
  /// (12 of its 30 since P7).
  static const double gap = 24;

  /// Your seal on the hero print at 30 dp (Print Room P7; Shahid,
  /// 2026-11-06: "on home page doesn't the rating box look too big? I am
  /// not a big fan of these ratings bcz they are ours"), the size P5 gave
  /// the seals on Profile's prints, from P2's 44, with its number kept: the
  /// lede ends "and sealed it", and the seal is that moment. It hangs (12,
  /// 8) past the corner, P2's (18, 12) scaled, so it keeps 12 dp clear of
  /// the words instead of 6, and the sentence keeps its width and its line
  /// breaks. False gives back P2's 44.
  static const bool _smallSeal = true;

  /// The pool of colour: 240 × 220, centred 8 under the print's centre, as
  /// the mockup's radial glow.
  static const Size glow = Size(240, 220);

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;
    final onPrint = this.onPrint;
    Widget print = HankoPrint(
      url: url,
      width: printWidth,
      height: printHeight,
      lift: HankoPrintLift.large,
      sharp: true,
      seal: rating == null
          ? null
          : HankoSeal.score(rating, size: _smallSeal ? 30 : 44),
      sealCorner: Alignment.bottomLeft,
      sealOverhang: _smallSeal ? const Offset(12, 8) : const Offset(18, 12),
      heroTag: heroTag,
    );
    if (onPrint != null) {
      print = _PrintTap(label: printLabel ?? '', onTap: onPrint, child: print);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // First, so it lies under the words and the print, never over them.
        Positioned(
          right: printWidth / 2 - glow.width / 2,
          top: printTop + printHeight / 2 + 8 - glow.height / 2,
          width: glow.width,
          height: glow.height,
          child: IgnorePointer(
            child: _CoverColour(
              url: url,
              builder: (context, colour) => _Glow(colour: colour),
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: sentence),
            const SizedBox(width: gap),
            Padding(
              padding: const EdgeInsets.only(top: printTop),
              child: print,
            ),
          ],
        ),
      ],
    );
  }
}

/// A pool of a show's colour behind its print (Print Room, P2): the field
/// rule at its glow strength (AppTheme.hankoFieldGlowCap, for where no text
/// sits), fading out from the centre. It is HankoField's glow, placed by the
/// print rather than by the field's size, which grows with the lede. No
/// colour, no glow; a colour arriving fades in with the field's, in 240 ms,
/// or at once with Remove animations on.
class _Glow extends StatelessWidget {
  const _Glow({required this.colour});

  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final glow = AppTheme.hankoField(colour,
        cap: AppTheme.hankoFieldGlowCap, mix: AppTheme.hankoFieldGlowMix);
    final clear = (glow ?? AppTheme.hankoSumi).withValues(alpha: 0);
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        gradient: RadialGradient(colors: [glow ?? clear, clear]),
      ),
    );
  }
}

/// A cover's colour for Print Room (P2), read from the cover itself by
/// HankoCoverColour, since list entries keep no AniList colour, and handed
/// to [builder]: null until it's read, and for a grey cover or one that
/// can't be read (on the web, a cover served without CORS). A colour read
/// once is known at once after that, so a shelf scrolled back draws its
/// mats in the first frame. Nothing here can throw: HankoCoverColour never
/// does.
class _CoverColour extends StatefulWidget {
  const _CoverColour({required this.url, required this.builder});

  final String? url;
  final Widget Function(BuildContext context, Color? colour) builder;

  @override
  State<_CoverColour> createState() => _CoverColourState();
}

class _CoverColourState extends State<_CoverColour> {
  Color? _colour;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_CoverColour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _read();
  }

  void _read() {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      _colour = null;
      return;
    }
    if (HankoCoverColour.knows(url)) {
      _colour = HankoCoverColour.peek(url);
      return;
    }
    _colour = null;
    HankoCoverColour.ofUrl(url).then((colour) {
      if (!mounted || widget.url != url) return;
      setState(() => _colour = colour);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _colour);
}

/// A print that opens its show (Print Room, P2): one button named [label],
/// with the InkWell's tap and keyboard focus in its own node and the print
/// left out of the tree (question 119's pattern). An InkWell's washes are
/// drawn under its child, where the art would hide them, so they're drawn
/// over it instead: the 8% press wash while pressed or hovered, and for
/// keyboard focus a 2 px washi outline, as +1 draws its own. The outline
/// lies just outside the box, so it never cuts into a title's first letter;
/// whatever holds a _PrintTap leaves it 2 px of room.
class _PrintTap extends StatefulWidget {
  const _PrintTap({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PrintTap> createState() => _PrintTapState();
}

class _PrintTapState extends State<_PrintTap> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onHover: (v) => setState(() => _hovered = v),
        onFocusChange: (v) => setState(() => _focused = v),
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: ExcludeSemantics(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              color: _pressed || _hovered ? AppTheme.hankoPressWash : null,
              border: _focused
                  ? Border.all(
                      color: AppTheme.hankoWashi,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside)
                  : null,
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── Continue Watching Card ───────────────────────────────────
class _ContinueCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final FirestoreService firestoreService;
  final VoidCallback onUpdated;

  /// Episodes aired so far, from Home's airing batch (next episode − 1),
  /// or null when the batch knows nothing about this show.
  final int? aired;
  final _Open open;

  const _ContinueCard({
    super.key,
    required this.data,
    required this.firestoreService,
    required this.onUpdated,
    required this.aired,
    required this.open,
  });

  // ── As a print on Continue's shelf (Print Room, P2) ──
  /// The print, 108 × 154, on its mat: 120 wide in all, the mockup's.
  static const double printWidth = 108;
  static const double printHeight = 154;
  static const double itemWidth = printWidth + 2 * AppTheme.hankoMatPad;
  static const double titleSize = 14;
  static const double titleHeight = 1.25;

  /// Lines a shelf title may take: two at 1.0x text, three at 1.3x. A limit
  /// counted in lines grows with the text: held to two at 1.3x, "The
  /// Apothecary Diaries Season 3" lost words (P1's finding).
  static int titleLines(TextScaler scaler) =>
      math.max(2, (2 * scaler.scale(titleSize) / titleSize).round());

  /// Where a shelf item's row (the count and +1) starts: under the mat, 8,
  /// the title's lines and 4. Every item keeps room for all the lines, so
  /// the counts and +1s line up along the shelf.
  static double rowTop(TextScaler scaler) =>
      printHeight +
      2 * AppTheme.hankoMatPad +
      8 +
      titleLines(scaler) * scaler.scale(titleSize) * titleHeight +
      4;

  /// The shelf's height: the row's top, its 48 dp, 1 to spare for the
  /// title's line metrics, and the list's 4 above and below.
  static double shelfHeight(TextScaler scaler) =>
      rowTop(scaler) + AppTheme.hankoTouch + 1 + 2 * 4;

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  /// The reel after "9 of 12" (HankoReel), switched off. Shahid, 2026-11-05:
  /// "I don't like the episode count lines that show like how many episodes
  /// you have watched, remove that just have 9 of 12". The words then carry
  /// what a screen reader hears.
  static const bool _reel = false;

  late int _current;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _current = (widget.data['currentEpisode'] as int?) ?? 0;
  }

  @override
  void didUpdateWidget(_ContinueCard old) {
    super.didUpdateWidget(old);
    // Sync if the parent reloaded with a different value (e.g. set on detail screen).
    final incoming = (widget.data['currentEpisode'] as int?) ?? 0;
    final previous = (old.data['currentEpisode'] as int?) ?? 0;
    if (incoming != previous) {
      _current = incoming;
    }
  }

  Future<void> _bump(int total) async {
    final next = total > 0 ? (_current + 1).clamp(0, total) : _current + 1;
    if (next == _current) return; // already at the cap

    // Optimistic: update UI instantly.
    setState(() {
      _current = next;
      _saving = true;
    });

    final animeId = widget.data['animeId']?.toString() ?? '';
    if (animeId.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    // Achievements (stage 4): the +1 that finishes a show, reported as it
    // shows (offline the writes below wait); the slip waits for +1's dip,
    // which has no tick, so the slip's press gives it.
    if (Achievements.replaceCards && total > 0 && next >= total) {
      AchievementSlip.expect(context,
          feedback: const Duration(milliseconds: 200));
      AchievementsService.instance.noteAction(animeId, {
        'currentEpisode': next,
        'lastWatched': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
      }).catchError((Object _) {});
    }

    // Write in the background — no full refetch, so no stutter.
    try {
      await widget.firestoreService
          .updateEpisodeProgress(int.parse(animeId), next);
      // Keep the parent's cached map in sync without triggering a reload.
      widget.data['currentEpisode'] = next;

      // ── Auto-complete ────────────────────────────────────────
      // If the user just watched the final episode, flip status to
      // COMPLETED and remove the card from the Continue arc.
      if (total > 0 && next >= total) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('animeList')
              .doc(animeId)
              .update({'status': 'COMPLETED'});
        }
        widget.data['status'] = 'COMPLETED';
        // onUpdated triggers _loadData() in HomeScreen, which re-queries
        // getAnimeByStatus('WATCHING') — COMPLETED entries won't appear.
        widget.onUpdated();
      }
    } catch (_) {
      // Revert on failure.
      if (mounted) setState(() => _current = next - 1);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final title = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final total = data['episodes'] as int?;
    final animeId = data['animeId']?.toString() ?? '';
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasTotal = total != null && total > 0;
    final aired = widget.aired;

    // Hanko's Continue row (stage H4, item b; hanko.html, Home): the cover,
    // the English title on up to two lines, and progress as words plus the
    // reel. The reel's outlined ticks are the episodes that have aired and
    // wait for you, which is what "2 NEW" said. When the airing batch knows
    // nothing (finished, not scheduled, failed, offline, or a MyAnimeList
    // import), the reel claims nothing past your episode, and its spoken
    // label says only how far you are. Since 2026-11-05 the reel is off
    // (_reel): the words alone, "9 of 12" or "1 watched".
    final progressWords =
        hasTotal ? '$_current of $total' : '$_current watched';
    final spokenProgress = hasTotal ? '$progressWords watched' : progressWords;
    final progressStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoLabelSize,
      weight: FontWeight.w500,
      color: AppTheme.hankoStone,
      height: 1,
      tabular: true,
    );

    if (_HomeScreenState._printRoom) {
      return _buildShelfItem(
        title: title,
        imageUrl: imageUrl,
        total: total,
        animeId: animeId,
        genres: genres,
        hasTotal: hasTotal,
        spokenProgress: spokenProgress,
      );
    }

    return InkWell(
      onTap: () {
        final anime = Anime(
          id: animeId,
          title: title,
          imageUrl: imageUrl,
          episodes: total,
          genres: genres,
        );
        widget.open(
            MaterialPageRoute(
                builder: (_) => AnimeDetailScreen(anime: anime)));
      },
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppTheme.hankoPressWash,
      hoverColor: AppTheme.hankoPressWash,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _HankoCover(
                url: imageUrl,
                width: _HankoCover.rowWidth,
                height: _HankoCover.rowHeight),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FadeTitle(
                  title,
                  maxLines: 2,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoListTitleSize, height: 1.25),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    // progressWords, with its count rolling to the new one
                    // when +1 lands (round seven). With the reel off they
                    // say the count to a screen reader, as the reel did.
                    Semantics(
                      container: !_reel,
                      label: _reel ? null : spokenProgress,
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RollingCount(
                                value: _current, style: progressStyle),
                            Text(hasTotal ? ' of $total' : ' watched',
                                style: progressStyle),
                          ],
                        ),
                      ),
                    ),
                    if (_reel) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: HankoReel(
                          watched: _current,
                          total: hasTotal ? total : null,
                          aired: aired ?? _current,
                          semanticLabel: aired == null ? spokenProgress : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PlusOneTile(
              nextEpisode: _current + 1,
              saving: _saving,
              onTap: animeId.isEmpty ? null : () => _bump(total ?? 0),
            ),
          ),
        ],
      ),
    );
  }

  /// The show as a print on Continue's shelf (Print Room, P2; DESIGN.md
  /// §9.5, frame 02): its cover on a mat of its own colour, its title under
  /// it, then "9 of 12" with +1, as round seven's row had them. The print,
  /// the title and the count are one button that opens the show, named by
  /// the title and how far you are; +1 is its own button, laid over the
  /// row's right end. Its writes are the row's (_bump), awaited and caught.
  Widget _buildShelfItem({
    required String title,
    required String imageUrl,
    required int? total,
    required String animeId,
    required List<String> genres,
    required bool hasTotal,
    required String spokenProgress,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final lines = _ContinueCard.titleLines(scaler);
    final still = MediaQuery.disableAnimationsOf(context);
    // Under the print on sumi: stone hi, the mockup's, a step brighter than
    // the rows' stone (6.9:1) so the count reads under a big print (10.7:1).
    final countStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoLabelSize,
      weight: FontWeight.w500,
      color: AppTheme.hankoStoneHi,
      height: 1,
      tabular: true,
    );
    // The print flies off the shelf into the show's page (P6).
    void openShow() => widget.open(_HomeScreenState._showRoute(
        context,
        Anime(
          id: animeId,
          title: title,
          imageUrl: imageUrl,
          episodes: total,
          genres: genres,
        ),
        place: 'shelf'));
    final item = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The mat takes the cover's colour once it's read, fading into it;
        // until then, and for good on a grey cover, it's sumi 2, so the
        // shelf keeps one rhythm of prints on mats.
        _CoverColour(
          url: imageUrl,
          builder: (context, colour) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(
                end: AppTheme.hankoField(colour) ?? AppTheme.hankoSumi2),
            duration:
                still ? Duration.zero : const Duration(milliseconds: 240),
            builder: (context, mat, _) => HankoPrint(
              url: imageUrl,
              width: _ContinueCard.printWidth,
              height: _ContinueCard.printHeight,
              mat: mat,
              heroTag: _HomeScreenState._printTag('shelf', animeId),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Room for every line the title may take, so the rows line up. A
        // minimum, not a fixed height: a box a hair short of the text would
        // fade its last line at the bottom.
        ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: lines *
                  scaler.scale(_ContinueCard.titleSize) *
                  _ContinueCard.titleHeight),
          child: _FadeTitle(
            title,
            maxLines: lines,
            style: AppTheme.hankoSerif(
                fontSize: _ContinueCard.titleSize,
                height: _ContinueCard.titleHeight),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: AppTheme.hankoTouch,
          child: Align(
            alignment: Alignment.centerLeft,
            // The count rolls to the new one when +1 lands (round seven).
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RollingCount(value: _current, style: countStyle),
                Text(hasTotal ? ' of $total' : ' watched', style: countStyle),
              ],
            ),
          ),
        ),
      ],
    );
    return SizedBox(
      width: _ContinueCard.itemWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _PrintTap(
            label: '$title, $spokenProgress',
            onTap: openShow,
            child: item,
          ),
          // Its drawn square lines up with the mat's right edge, so the
          // 48 dp target hangs 4 past it, into the gap between prints.
          Positioned(
            top: _ContinueCard.rowTop(scaler),
            right: -(AppTheme.hankoTouch - _PlusOneTile.drawn) / 2,
            child: _PlusOneTile(
              nextEpisode: _current + 1,
              saving: _saving,
              onTap: animeId.isEmpty ? null : () => _bump(total ?? 0),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hanko's outlined +1 tile: sumi 3 with a 1 px edge outline (4.02:1), "+1"
/// in Jost 600 washi. Outlined rather than filled because it repeats on
/// every row, and one filled main action per screen is the rule. While its
/// write is on its way the outline turns washi.
///
/// Round seven (Shahid, 2026-11-03: "plus +1 a bit smaller and give it an
/// animation when I press it"): the square is drawn at 40 dp, from 48, with
/// "+1" at 14, from 15, inside the same 48 dp target, so it is as easy to
/// hit as before. Each tap presses it like a seal: in to 0.92, out through
/// AppTheme.hankoSealPressScale and back to rest, 240 ms in all. With
/// "remove animations" on it doesn't move.
///
/// The InkWell keeps the whole target, so its tap and keyboard focus stay in
/// the button's own semantics node (question 119). Its washes would cover
/// the whole target too, a square wider than the one drawn, so the square
/// draws them itself from the InkWell's highlight, hover and focus: the 8%
/// press wash, and for keyboard focus a washi outline with a 12% wash.
class _PlusOneTile extends StatefulWidget {
  const _PlusOneTile({
    required this.nextEpisode,
    required this.saving,
    required this.onTap,
  });

  final int nextEpisode;
  final bool saving;
  final VoidCallback? onTap;

  /// The drawn square, inside the AppTheme.hankoTouch target.
  static const double drawn = 40;

  @override
  State<_PlusOneTile> createState() => _PlusOneTileState();
}

class _PlusOneTileState extends State<_PlusOneTile>
    with SingleTickerProviderStateMixin {
  // Print Room P6 (DESIGN.md §9.3 A rule 5, "the tile dips, the count turns
  // over; 200 ms"): the tile dips to 0.90 and comes back, 60 ms in and 140
  // out, with no overshoot. The overshoot is the seal's: your verdict moves
  // like that, the app's most frequent action doesn't. The count's roll
  // (_RollingCount, 160 ms) turns over inside it. Round seven's press, in
  // to 0.92 and out through the seal's 1.06 in 240 ms, is kept, not deleted
  // (CLAUDE.md): false brings it back.
  static const bool _dip = true;

  late final AnimationController _press = AnimationController(
    vsync: this,
    duration:
        _dip ? const Duration(milliseconds: 200) : AppTheme.hankoSealPress * 2,
  );
  late final Animation<double> _scale = (_dip
          ? TweenSequence<double>([
              TweenSequenceItem(
                tween: Tween(begin: 1.0, end: 0.90)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 60,
              ),
              TweenSequenceItem(
                tween: Tween(begin: 0.90, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 140,
              ),
            ])
          : TweenSequence<double>([
              TweenSequenceItem(
                tween: Tween(begin: 1.0, end: 0.92)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 30,
              ),
              TweenSequenceItem(
                tween: Tween(begin: 0.92, end: AppTheme.hankoSealPressScale)
                    .chain(CurveTween(curve: Curves.easeOut)),
                weight: 30,
              ),
              TweenSequenceItem(
                tween: Tween(begin: AppTheme.hankoSealPressScale, end: 1.0)
                    .chain(CurveTween(curve: Curves.easeInOut)),
                weight: 40,
              ),
            ]))
      .animate(_press);

  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _tap() {
    if (!MediaQuery.disableAnimationsOf(context)) _press.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final fill = _focused
        ? Color.alphaBlend(
            AppTheme.hankoWashi.withValues(alpha: 0.12), AppTheme.hankoSumi3)
        : _pressed || _hovered
            ? Color.alphaBlend(AppTheme.hankoPressWash, AppTheme.hankoSumi3)
            : AppTheme.hankoSumi3;
    final outline =
        widget.saving || _focused ? AppTheme.hankoWashi : AppTheme.hankoEdge;
    // One semantics node (container) with the InkWell's tap and focus
    // inside it, as the lede (question 119; see _HomeScreenState._buildLede).
    // "+1" is left out of the tree, since the label says what it does.
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: 'Mark episode ${widget.nextEpisode} watched',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap == null ? null : _tap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: AppTheme.hankoTouch,
              child: Center(
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: _PlusOneTile.drawn,
                    height: _PlusOneTile.drawn,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius:
                          BorderRadius.circular(AppTheme.hankoRadius),
                      border: Border.all(color: outline),
                    ),
                    child: Text(
                      '+1',
                      style: AppTheme.hankoSans(
                          fontSize: 14, weight: FontWeight.w600, height: 1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Continue row's count, which rolls when it changes (round seven): the
/// new figure comes up from below as the old one leaves upward, 160 ms, so
/// a +1 is seen to land in the row's words. A count that goes back (a save
/// that failed) rolls the other way. Still with "remove animations" on.
class _RollingCount extends StatefulWidget {
  const _RollingCount({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  State<_RollingCount> createState() => _RollingCountState();
}

class _RollingCountState extends State<_RollingCount> {
  bool _up = true;

  @override
  void didUpdateWidget(_RollingCount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final current = ValueKey(widget.value);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: still ? Duration.zero : const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (shown, leaving) => Stack(
          alignment: Alignment.centerLeft,
          children: [...leaving, ?shown],
        ),
        transitionBuilder: (child, animation) {
          // The incoming figure runs 0 → 1 from below (above when going
          // back); the leaving one runs 1 → 0, so it starts where it is.
          final incoming = child.key == current;
          final edge = (incoming == _up) ? 0.7 : -0.7;
          return SlideTransition(
            position: Tween(begin: Offset(0, edge), end: Offset.zero)
                .animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Text('${widget.value}', key: current, style: widget.style),
      ),
    );
  }
}

// ── Trending Card ────────────────────────────────────────────
class _TrendingCard extends StatefulWidget {
  final Anime anime;
  final int? rank;
  final _Open open;
  const _TrendingCard({
    super.key,
    required this.anime,
    this.rank,
    required this.open,
  });

  @override
  State<_TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<_TrendingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.open(
          MaterialPageRoute(
              builder: (_) => AnimeDetailScreen(anime: widget.anime)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 140,
          margin: const EdgeInsets.only(right: 14),
          transform: Matrix4.identity()
            ..scale(_hovered ? 1.03 : 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 140,
                      height: 196,
                      child: widget.anime.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.anime.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  Container(color: AppTheme.surfaceLight),
                            )
                          : Container(color: AppTheme.surfaceLight),
                    ),
                  ),
                  if (widget.rank != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomLeft: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          '${widget.rank}',
                          style: AppTheme.mono(
                              fontSize: 13,
                              weight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ),
                  // NEW badge for airing anime
                  if (widget.anime.status == 'RELEASING')
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'NEW',
                          style: AppTheme.mono(
                              fontSize: 8,
                              weight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.anime.titleEnglish ?? widget.anime.title,
                style: AppTheme.sans(
                    fontSize: 12,
                    weight: FontWeight.w500,
                    color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.anime.genres.isNotEmpty)
                Text(
                  widget.anime.genres.first.toUpperCase(),
                  style: AppTheme.mono(
                      fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Badge ────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted, letterSpacing: 1),
      ),
    );
  }
}

// ── Trending Row ─────────────────────────────────────────────
class _TrendingRow extends StatefulWidget {
  final Anime anime;
  final int rank;
  const _TrendingRow({required this.anime, required this.rank});

  @override
  State<_TrendingRow> createState() => _TrendingRowState();
}

class _TrendingRowState extends State<_TrendingRow>
    with SingleTickerProviderStateMixin {
  String? _savedStatus;
  late AnimationController _ctrl;
  late Animation<double> _scale;

  static const _statusMeta = {
    'WATCHING':      (Icons.play_circle_rounded,    Color(0xFFE8624A)),
    'PLAN_TO_WATCH': (Icons.bookmark_rounded,        Color(0xFF5B8DEF)),
    'COMPLETED':     (Icons.check_circle_rounded,    Color(0xFF4CAF7D)),
    'DROPPED':       (Icons.cancel_rounded,          Color(0xFFEF5B5B)),
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('animeList').doc(widget.anime.id)
          .get();
      if (mounted && doc.exists) {
        setState(() => _savedStatus = doc.data()?['status'] as String?);
      }
    } catch (_) {
      // Same as _TonightCardState._loadStatus: offline, get() can throw, and
      // uncaught it is reported to Crashlytics as fatal.
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onBookmarkTap() async {
    final status = await showHanjListSheet(context: context, anime: widget.anime, currentStatus: _savedStatus);
    if (status != null && status != '__REMOVE__' && mounted) {
      setState(() => _savedStatus = status);
      _ctrl.forward(from: 0);
    } else if (status == '__REMOVE__' && mounted) {
      setState(() => _savedStatus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = _savedStatus != null;
    final meta = isSaved ? _statusMeta[_savedStatus] : null;
    final icon = meta?.$1 ?? Icons.bookmark_border_rounded;
    final color = meta?.$2 ?? AppTheme.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: widget.anime))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    // Rank number
                    SizedBox(
                      width: 48,
                      child: Text(
                        widget.rank.toString().padLeft(2, '0'),
                        style: AppTheme.serif(
                          fontSize: 28,
                          weight: FontWeight.w700,
                          color: AppTheme.border,
                          height: 1,
                        ),
                      ),
                    ),
                    // Poster
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 72,
                        child: widget.anime.imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: widget.anime.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    Container(color: AppTheme.surfaceLight),
                              )
                            : Container(color: AppTheme.surfaceLight),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.anime.titleEnglish ?? widget.anime.title,
                            style: AppTheme.sans(
                                fontSize: 15, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (widget.anime.genres.isNotEmpty)
                                widget.anime.genres.first.toUpperCase(),
                            ].join(' · '),
                            style: AppTheme.mono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: AppTheme.primary, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                widget.anime.averageScore != null
                                    ? (widget.anime.averageScore! / 10)
                                        .toStringAsFixed(1)
                                    : '—',
                                style: AppTheme.sans(
                                    fontSize: 12,
                                    weight: FontWeight.w600,
                                    color: AppTheme.primary),
                              ),
                              if (widget.anime.episodes != null) ...[
                                Text(' · ',
                                    style: AppTheme.sans(
                                        color: AppTheme.textMuted,
                                        fontSize: 12)),
                                Text(
                                  '${widget.anime.episodes} ep',
                                  style: AppTheme.sans(
                                      fontSize: 12,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Animated bookmark
                    GestureDetector(
                      onTap: _onBookmarkTap,
                      child: ScaleTransition(
                        scale: _scale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSaved
                                ? color.withValues(alpha: 0.15)
                                : AppTheme.surfaceLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSaved ? color : AppTheme.border,
                            ),
                            boxShadow: isSaved
                                ? [BoxShadow(
                                    color: color.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )]
                                : [],
                          ),
                          child: Icon(icon, color: isSaved ? color : AppTheme.textMuted, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.rank < 10)
                const Divider(height: 1, color: AppTheme.border),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hanko pieces shared by Home's blocks ─────────────────────

/// A cover at a fixed size, with Hanko's square 2 px corners and sumi 3
/// behind it while it loads or when there is none. Decoded at full size on
/// purpose, with no memCacheWidth: a resized decode is a different cache
/// entry, and Detail opens on this same image (DESIGN.md §6c).
class _HankoCover extends StatelessWidget {
  const _HankoCover({
    required this.url,
    required this.width,
    required this.height,
  });

  final String? url;
  final double width;
  final double height;

  /// A row's cover, Continue's and Coming up's: 52 × 74 since round seven
  /// (Shahid, 2026-11-03: "make the posters a bit bigger on home screen"),
  /// from 42 × 60. AniList's 230 px cover stays sharp up to about 57 dp on
  /// the CPH2573 (4 px per dp), so it is still crisp.
  static const double rowWidth = 52;
  static const double rowHeight = 74;

  @override
  Widget build(BuildContext context) {
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: AppTheme.hankoSumi3,
          child: u == null || u.isEmpty
              ? const SizedBox.expand()
              : CachedNetworkImage(
                  imageUrl: u,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}

/// One show in a Hanko poster strip (hanko.html's .mlt), as This season's
/// strip draws it (upcoming_anime.dart): an 88 x 125 cover with square 2 px
/// corners on sumi 3 while it loads, the title under it in Jost 500 12 on up
/// to two lines, and the 8% washi press. The column widens as the title's
/// text grows, so a long word still fits on one line at large text; the
/// strip's height follows (heightFor). Opens the show through Home's _open.
///
/// 88 wide since round seven (Shahid, 2026-11-03: "make the posters a bit
/// bigger on home screen"), from 72. It still widens past 88 only where 72
/// grown with the text would: at 1.3x a 72 px column broke "Apothecary"
/// mid-word, and 72 x 1.3 keeps it whole.
class _StripItem extends StatelessWidget {
  const _StripItem({required this.anime, required this.open});

  final Anime anime;
  final _Open open;

  static double _widthFor(TextScaler scaler) {
    final grow = scaler.scale(12) / 12;
    return math.max(88.0, 72 * grow);
  }

  /// The cover, the gap and two lines of title at the reader's text size.
  static double heightFor(TextScaler scaler) =>
      _widthFor(scaler) * 102 / 72 + 6 + scaler.scale(12) * 1.25 * 2 + 4;

  @override
  Widget build(BuildContext context) {
    final width = _widthFor(MediaQuery.textScalerOf(context));
    final title = anime.titleEnglish ?? anime.title;
    void openShow() => open(
        MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)));
    // One semantics node (container) with the InkWell's tap and focus
    // inside it, as the lede (question 119; see _HomeScreenState._buildLede).
    // Its cover and title are left out of the tree, since the label says it.
    return Semantics(
      container: true,
      button: true,
      label: title,
      child: InkWell(
        onTap: openShow,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HankoCover(
                    url: anime.imageUrl, width: width, height: width * 102 / 72),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      weight: FontWeight.w500,
                      height: 1.25),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Shippori title on up to [maxLines] lines whose last line fades out at
/// its end when the title runs longer, instead of an ellipsis: Shippori
/// draws "…" as the centred Japanese ⋯ (AppTheme.hankoSerif). Flutter's own
/// TextOverflow.fade on a multi-line Text fades the bottom half of the last
/// line instead, so the title is split after its last full line and that
/// line is set on its own, one line with TextOverflow.fade, as the mockup's
/// .fade does.
class _FadeTitle extends StatelessWidget {
  const _FadeTitle(this.text,
      {required this.style, required this.maxLines, this.textAlign});

  final String text;
  final TextStyle style;
  final int maxLines;

  /// Centred titles (the status sheet's) pass TextAlign.center. A cut last
  /// line is always as wide as the box, so it starts at the left edge and
  /// fades at the right whatever the alignment.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      final lines = overflows ? painter.computeLineMetrics() : null;
      // The last line's first character: the painter is left-aligned, so
      // x = 0 on that line is its start. Not getLineBoundary(...).start: at
      // the first offset of a soft-wrapped line it answers with the line
      // before (seen on the emulators), which made every two-line title
      // fall back to Flutter's bottom-half fade below, and split a
      // three-line title after its first line.
      final lastStart = lines == null || lines.length < maxLines
          ? 0
          : painter
              .getPositionForOffset(Offset(
                  0, lines[maxLines - 1].baseline - lines[maxLines - 1].ascent / 2))
              .offset;
      painter.dispose();
      if (!overflows || lastStart <= 0) {
        return Text(text,
            style: style,
            textAlign: textAlign,
            maxLines: maxLines,
            softWrap: maxLines > 1,
            overflow: TextOverflow.fade);
      }
      return Column(
        crossAxisAlignment: textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text.substring(0, lastStart).trimRight(),
              style: style, textAlign: textAlign, maxLines: maxLines - 1),
          Text(text.substring(lastStart).trimLeft(),
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade),
        ],
      );
    });
  }
}

/// Hanko's quiet link: Jost 500 13 in washi, underlined in edge, in a 48 dp
/// target. A secondary way on ("See all", "More"), never shaped as a button.
class _QuietLink extends StatelessWidget {
  const _QuietLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              label,
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                weight: FontWeight.w500,
              ).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: AppTheme.hankoEdge,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Popular this season: one chart row ───────────────────────
// Hanko's ranked row (hanko.html, Home): the rank in Shippori, a 40 × 56
// cover (34 × 48 before round seven's bigger posters), the title on one
// line that fades out (Shippori draws "…" as the centred Japanese
// ellipsis), and AniList's score in indigo, the crowd's colour, so it never
// reads as your verdict (yours are seals). The score is out of 10 with one
// decimal, as everywhere else in Hanj.
class _ChartRow extends StatelessWidget {
  const _ChartRow({
    required this.anime,
    required this.rank,
    required this.onOpen,
  });

  final Anime anime;
  final int rank;
  final VoidCallback onOpen;

  /// 8 dp taller than the cover, as it was at 56 for a 48 dp cover.
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final title = anime.titleEnglish ?? anime.title;
    final score = anime.averageScore;
    final scoreText = score == null ? null : (score / 10).toStringAsFixed(1);
    final scaler = MediaQuery.textScalerOf(context);
    // One semantics node (container) with the InkWell's tap and focus
    // inside it, as the lede (question 119; see _HomeScreenState._buildLede).
    // Its rank, cover, title and score are left out of the tree, since the
    // label says them.
    return Semantics(
      container: true,
      button: true,
      label: '$rank. $title${scoreText == null ? '' : ', AniList $scoreText'}',
      child: InkWell(
        onTap: onOpen,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                SizedBox(
                  width: scaler.scale(18),
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.right,
                    style: AppTheme.hankoSerif(
                        fontSize: 17, color: AppTheme.hankoStone, height: 1),
                  ),
                ),
                const SizedBox(width: 12),
                _HankoCover(url: anime.imageUrl, width: 40, height: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoListTitleSize, height: 1.25),
                  ),
                ),
                if (scoreText != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    scoreText,
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoBodySize,
                      weight: FontWeight.w500,
                      color: AppTheme.hankoAi,
                      tabular: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Coming Up Section ─────────────────────────────────────────
Future<void> _saveReminder(BuildContext context, String animeId, bool val) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final ref = FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('alerts').doc(animeId);
  if (val) {
    await ref.set({
      'animeId': animeId,
      'addedAt': FieldValue.serverTimestamp(),
    });
  } else {
    await ref.delete();
  }
}


/// Coming up: the soonest three next episodes among the shows you're
/// watching. Since Hanko's Home (stage H4, item b) it draws what Home's
/// lifted airing batch found (Stage 2 item a) instead of fetching its own.
class _ComingUpSection extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final bool loading;
  final Set<String> reminderIds;
  final void Function(String animeId, bool val) onToggleReminder;
  final _Open open;

  const _ComingUpSection({
    required this.items,
    required this.loading,
    required this.reminderIds,
    required this.onToggleReminder,
    required this.open,
  });

  @override
  State<_ComingUpSection> createState() => _ComingUpSectionState();
}

class _ComingUpSectionState extends State<_ComingUpSection> {
  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    // Hanko (question 46): no card around the block and no coral. The rows
    // are drawn like Continue's: the cover, the title on up to two lines,
    // a line of facts in Jost, and a 48 dp tile on the right, here the
    // reminder bell, drawn as Detail's is.
    if (widget.loading) {
      // About one row tall, so the page moves little when the rows land.
      return const SizedBox(
        height: 64,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: AppTheme.hankoWashi, strokeWidth: 1.5),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      // Says what the block is for, which is true whatever the reason it is
      // empty: nothing in Watching, nothing scheduled, a MyAnimeList import,
      // or a batch that didn't arrive. The old line asked everyone to add a
      // show to Watching, including people whose shows simply aren't airing.
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          "The next episodes of the shows you’re watching appear here.",
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoMetaSize,
              color: AppTheme.hankoStone,
              height: 1.4),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          _buildRow(context, item),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, Map<String, dynamic> item) {
    final date = item['date'] as DateTime;
    final animeId = (item['animeId'] ?? '').toString();
    final isOn = animeId.isNotEmpty && widget.reminderIds.contains(animeId);
    final title = item['title'] as String;
    final episode = item['episode'] as int;

    return InkWell(
      onTap: () => _openDetail(context, animeId),
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppTheme.hankoPressWash,
      hoverColor: AppTheme.hankoPressWash,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left out of the semantics tree (question 85, as the Calendar's
          // rows since dd45bd1): the title beside it names the show, and the
          // cover's image role made the row read as an image.
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ExcludeSemantics(
              child: _HankoCover(
                  url: item['imageUrl'] as String?,
                  width: _HankoCover.rowWidth,
                  height: _HankoCover.rowHeight),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FadeTitle(
                  title,
                  maxLines: 2,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoListTitleSize, height: 1.25),
                ),
                const SizedBox(height: 7),
                Text(
                  'Episode $episode, ${_when(date)}',
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoStone,
                    height: 1.3,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
          // Room for a cut title's fade before the bell (3dbd8fd).
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _bell(context, animeId, title, episode, isOn),
          ),
        ],
      ),
    );
  }

  /// The reminder bell, drawn as Detail's (Hanko H3): a 36 dp square in a
  /// 48 dp target, an edge outline when off, washi with a sumi bell when on.
  /// It does what the round coral bell did: the same callback, the same
  /// write, the same message. It is its own semantics node with the same
  /// tap as the gesture (question 85; the Calendar's bell since dd45bd1), so
  /// a screen reader reaches it apart from the row it sits in. Folded into
  /// the row, the bell's name and state joined the row's node, whose tap
  /// opens the show, so a screen reader couldn't set the reminder.
  ///
  /// The tap and focus are an InkWell's inside that node (question 119, as
  /// the lede): a GestureDetector's tap given to the node over excluded
  /// semantics had no focus, so the bell couldn't take focus on the web, and
  /// Enter or Space couldn't set it. The InkWell has Hanko's press wash and
  /// the theme's focus wash over the 48 dp target.
  Widget _bell(BuildContext context, String animeId, String title,
      int episode, bool isOn) {
    Future<void> toggle() async {
      final newVal = !isOn;
      Future<void>? saving;
      if (animeId.isNotEmpty) {
        widget.onToggleReminder(animeId, newVal);
        saving = _saveReminder(context, animeId, newVal);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newVal
              ? 'Reminder set for $title Ep $episode'
              : 'Reminder removed for $title Ep $episode'),
          backgroundColor: AppTheme.surfaceLight,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      // Question 83: the write is awaited and caught. Unawaited, a
      // refused write (by the rules, say) went to
      // PlatformDispatcher.onError, which main.dart reports to
      // Crashlytics as fatal, and the bell went on showing a reminder
      // that wasn't saved. Now the bell goes back and the message says
      // so, naming no cause. Offline, the write waits for the
      // connection and the bell stays as tapped.
      if (saving == null) return;
      try {
        await saving;
      } catch (_) {
        if (!context.mounted) return;
        widget.onToggleReminder(animeId, isOn);
        // In place of "Reminder set" if it's still showing. Home's failure
        // copy takes the typographic apostrophe, as its list line does
        // (question 126).
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(newVal
                  ? "Couldn’t set the reminder. Try again."
                  : "Couldn’t remove the reminder. Try again."),
              backgroundColor: AppTheme.surfaceLight,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              ),
            ),
          );
      }
    }

    return Semantics(
      container: true,
      button: true,
      toggled: isOn,
      label: 'Remind me when episode $episode of $title airs',
      child: InkWell(
        onTap: toggle,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: AppTheme.hankoTouch,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isOn ? AppTheme.hankoWashi : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  border: isOn ? null : Border.all(color: AppTheme.hankoEdge),
                ),
                child: Icon(
                  isOn
                      ? Icons.notifications_sharp
                      : Icons.notifications_none_outlined,
                  color: isOn ? AppTheme.hankoSumi : AppTheme.hankoWashi,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// When the episode airs, in the lede's journal voice: "today at 13:00",
  /// "tomorrow at 13:00", "Friday at 13:00" (2 to 6 days on), "13 Nov at
  /// 13:00" (a week or more). By the device's own calendar and clock. Its
  /// words are joined by no-break spaces, so when large text needs a second
  /// line it starts after the episode and never leaves the time alone.
  String _when(DateTime t) {
    final now = DateTime.now();
    final days = DateTime.utc(t.year, t.month, t.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    final String day;
    if (days <= 0) {
      day = 'today';
    } else if (days == 1) {
      day = 'tomorrow';
    } else if (days < 7) {
      day = DateFormat('EEEE').format(t);
    } else {
      day = DateFormat('d MMM').format(t);
    }
    return '$day at ${_formatTime(t)}'.replaceAll(' ', '\u00A0');
  }

  String _formatTime(DateTime dt) {
    // dt is already device-local (converted from AniList's epoch).
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _opening = false;

  Future<void> _openDetail(BuildContext context, String animeId) async {
    if (_opening || animeId.isEmpty) return;
    _opening = true;

    // Try the cached detail first for an instant open, else fetch by id.
    Anime? anime =
        await OfflineCacheService.instance.getCachedAnimeDetail(animeId);
    anime ??= await AnilistService().getAnimeById(animeId);

    _opening = false;
    if (anime != null && mounted) {
      widget.open(
          MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime!)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open right now — try again')),
      );
    }
  }
}

// ── Plan to Watch Card ───────────────────────────────────────
// Simple poster + title card for the "Up next" row on Home.
// Tapping opens the anime detail screen.
class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final _Open open;
  const _PlanCard({required this.data, required this.open});

  @override
  Widget build(BuildContext context) {
    final title    = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final animeId  = data['animeId']?.toString() ?? '';
    final genres   = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final episodes = data['episodes'] as int?;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => open(
          MaterialPageRoute(
            builder: (_) => AnimeDetailScreen(
              anime: Anime(
                id: animeId,
                title: title,
                imageUrl: imageUrl,
                episodes: episodes,
                genres: genres,
              ),
            ),
          ),
        ),
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 140,
                  height: 196,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Container(color: AppTheme.surfaceLight),
                        )
                      : Container(color: AppTheme.surfaceLight),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: AppTheme.sans(
                    fontSize: 11,
                    weight: FontWeight.w500,
                    color: AppTheme.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (episodes != null)
                Text(
                  '$episodes EP',
                  style:
                      AppTheme.mono(fontSize: 9, color: AppTheme.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
