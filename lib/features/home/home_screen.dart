import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/theme/app_theme.dart';
import '../../widgets/anilist_saved_note.dart';
import '../../widgets/hanko_reel.dart';
import '../../widgets/hanko_seal.dart';
import '../../core/responsive.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../services/offline_cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../models/anime_model.dart';
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
    } catch (_) {
      // The cache couldn't answer: keep what is on screen.
    } finally {
      _reloading = false;
    }
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
            color: AppTheme.hankoStone,
            height: 1.3),
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

  /// The top line (Hanko stage H4, item g): the coral wing beside "Hanj" in
  /// Shippori Mincho, and Search as a 48 dp button. The wing is the text cut
  /// (MARK-SIZES.md §1), drawn for 18 px and validated to 48, here at 20.
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
                  'assets/images/hanj_wing_transparent.png',
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
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopLine(),
                    _buildDateline(),
                    _recordColumn(Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppTheme.hankoGutter, 6, AppTheme.hankoGutter, 0),
                      // Dynamic headline
                      child: _buildHeadline(),
                    )),
                  ],
                ),
              ),
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
            // all", which opens My List's Watching filter.
            if (_continueWatching.isNotEmpty)
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
            // One show from your own watchlist, a new one each day. Tonight's
            // Drop, the season pick for everyone, keeps the slot only when
            // the watchlist holds nothing the pick can land on (empty, or
            // only old MyAnimeList imports: question 114, see _pickable).
            if (_pickable.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('home-watchlist-pick'),
                child: _recordColumn(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 0),
                  child: Builder(builder: (context) {
                    final pick = _watchlistPick();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _WatchlistPick(
                          entry: pick,
                          onOpen: () => _openEntry(pick),
                        ),
                        // Up next folds in here (question 45): the rest of
                        // your watchlist is one tap away, on My List's
                        // watchlist filter. Only when there is more than the
                        // pick, as Continue's "See all" shows only when there
                        // are more rows than Home has room for.
                        if (_planToWatch.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _QuietLink(
                              label:
                                  'See your watchlist (${_planToWatch.length})',
                              onTap: () => _open(MaterialPageRoute(
                                  builder: (_) => const MyListScreen(
                                      initialStatus: 'PLAN_TO_WATCH',
                                      showBackButton: true))),
                            ),
                          ),
                      ],
                    );
                  }),
                )),
              )
            // ── Tonight's Drop / Anime of Day ────────────────
            else if (_animeOfDay != null)
              SliverToBoxAdapter(
                key: const ValueKey('home-anime-of-day'),
                child: _recordColumn(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 0),
                  child: _TonightCard(anime: _animeOfDay!, open: _open),
                )),
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

  /// The watchlist entries the pick can land on (question 114): not
  /// MyAnimeList imports from before the D21 fix. They are keyed by their
  /// MyAnimeList id, which AniList reads as another show or none, so one
  /// opens nearly empty, and a show to start tonight should open. The
  /// entries are left as they are: the watchlist link counts them, and My
  /// List shows them.
  List<Map<String, dynamic>> get _pickable =>
      [for (final e in _planToWatch) if (!_isMalImport(e)) e];

  /// Tonight's watchlist pick: the day of the year, modulo the number of
  /// entries it can land on (newest first), the rotation Tonight's Drop has
  /// always used, applied to your own list. The same pick all day, a new one
  /// tomorrow.
  Map<String, dynamic> _watchlistPick() {
    final pickable = _pickable;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return pickable[dayOfYear % pickable.length];
  }

  void _openEntry(Map<String, dynamic> data) {
    final anime = Anime(
      id: data['animeId']?.toString() ?? '',
      title: data['title'] as String? ?? 'Unknown',
      imageUrl: data['imageUrl'] as String?,
      episodes: data['episodes'] as int?,
      genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
    );
    _open(MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)));
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

    final when = _whenRated(ratedAt);
    // The sentence, with three ways of keeping words together: a short
    // title on one line ([wholeTitle], as the mockup's no-break span does),
    // "you" with its verb ([bindVerb]), and always "sealed it" with the
    // seal, a no-break space before it as the mockup's &nbsp; does.
    String compose({required bool wholeTitle, bool bindVerb = false}) {
      final title =
          wholeTitle ? rawTitle.replaceAll(' ', ' ') : rawTitle;
      final you = bindVerb ? 'you ' : 'you ';
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
    // text size setting; HankoSeal shrinks the numerals to fit.
    final seal = Size(scaler.scale(32), scaler.scale(28));
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
      child: InkWell(
        onTap: () => _openEntry(entry),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: LayoutBuilder(builder: (context, constraints) {
              // Q54: a short title kept whole can leave the word before it
              // alone on a line. At 1.3x "On Monday you / finished / Cowboy
              // Bebop, all ..." left "finished" by itself. So the first of
              // these that leaves no word alone wins: the title whole; the
              // title whole with "you" kept by its verb; the title free to
              // break. A long title may always break, as before.
              final candidates = rawTitle.length <= 18
                  ? [
                      compose(wholeTitle: true),
                      compose(wholeTitle: true, bindVerb: true),
                      compose(wholeTitle: false),
                    ]
                  : [compose(wholeTitle: false)];
              final sentence = candidates.firstWhere(
                  (s) => !_leavesAWordAlone(
                      s, style, scaler, seal, constraints.maxWidth),
                  orElse: () => candidates.first);
              return Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    TextSpan(text: sentence),
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
            }),
          ),
        ),
      ),
    );
  }

  /// Whether [sentence], followed by the seal and laid out at [maxWidth],
  /// leaves one word alone on a line before the last. Words joined by a
  /// no-break space count as more than one word, so a short title on a
  /// line of its own is fine. Each line's first character comes from x = 0
  /// on that line, as _FadeTitle finds it (getLineBoundary misreports a
  /// line's start on the web).
  bool _leavesAWordAlone(String sentence, TextStyle style, TextScaler scaler,
      Size seal, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(style: style, children: [
        TextSpan(text: sentence),
        const WidgetSpan(
            alignment: PlaceholderAlignment.middle, child: SizedBox.shrink()),
      ]),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )
      ..setPlaceholderDimensions([
        PlaceholderDimensions(
            size: seal, alignment: PlaceholderAlignment.middle),
      ])
      ..layout(maxWidth: maxWidth);
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

      return StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          // hanko.html's sheet: sumi 2, 6 px top corners, the 20 px gutter.
          decoration: const BoxDecoration(
            color: AppTheme.hankoSumi2,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppTheme.hankoSheetRadius)),
          ),
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 10, AppTheme.hankoGutter, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              // The show's cover beside its name, as the sheet's head in
              // hanko.html draws it: pictures for what the show is.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HankoCover(url: anime.imageUrl, width: 36, height: 51),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Three lines, fading where a cut remains (H2 QA
                        // W2). Shared with Detail. Set from the left now,
                        // beside the cover; it was centred.
                        _FadeTitle(
                          anime.titleEnglish ?? anime.title,
                          maxLines: 3,
                          textAlign: TextAlign.start,
                          style: AppTheme.hankoSerif(
                              fontSize: 20, height: 1.15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Where does this one live?',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              color: AppTheme.hankoStone,
                              height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              pair(0, ctx, setLocal),
              const SizedBox(height: 8),
              pair(2, ctx, setLocal),
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
      );
    },
  );
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

  void _openShow() => widget.open(MaterialPageRoute(
      builder: (_) => AnimeDetailScreen(anime: widget.anime)));

  @override
  Widget build(BuildContext context) {
    // Since Hanko (stage H4, item d) Tonight's Drop shows only when your
    // watchlist is empty, drawn like the watchlist pick: no text on the art,
    // the crowd's score in indigo, and the bookmark as an outlined 48 dp
    // tile. The "Continue" pill went: it did what tapping the card does,
    // and said "Continue" about a show you haven't started.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          // The typographic apostrophe: Shippori draws the typewriter one
          // as a straight tick (questions 109 and 154).
          child: Text('Tonight’s drop',
              style: AppTheme.hankoSerif(height: 1.3)),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // One semantics node (container) with the InkWell's tap and
              // focus inside it, as the lede (question 119; see
              // _HomeScreenState._buildLede). Its cover and words are left
              // out of the tree, since the label says them.
              child: Semantics(
                container: true,
                button: true,
                label: [
                  title,
                  if (facts.isNotEmpty) facts,
                  if (scoreText != null) 'AniList $scoreText',
                ].join(', '),
                child: InkWell(
                  onTap: _openShow,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                  hoverColor: AppTheme.hankoPressWash,
                  child: ExcludeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HankoCover(
                            url: anime.imageUrl, width: 72, height: 102),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FadeTitle(
                                title,
                                maxLines: 2,
                                style: AppTheme.hankoSerif(
                                    fontSize: AppTheme.hankoFeaturedSize,
                                    height: 1.15),
                              ),
                              if (facts.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  facts,
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoMetaSize,
                                      color: AppTheme.hankoStone,
                                      height: 1.4),
                                ),
                              ],
                              if (scoreText != null) ...[
                                const SizedBox(height: 4),
                                Text.rich(
                                  TextSpan(
                                    text: 'AniList ',
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoMetaSize,
                                        color: AppTheme.hankoStone,
                                        height: 1.4),
                                    children: [
                                      TextSpan(
                                        text: scoreText,
                                        style: AppTheme.hankoSans(
                                          fontSize: AppTheme.hankoMetaSize,
                                          weight: FontWeight.w500,
                                          color: AppTheme.hankoAi,
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
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ScaleTransition(
              scale: _bookmarkScale,
              child: IconButton(
                onPressed: _onBookmarkTap,
                tooltip: isSaved ? 'On your list' : 'Add to your list',
                icon: Icon(icon, size: 20, color: AppTheme.hankoWashi),
                style: const ButtonStyle(
                  backgroundColor:
                      WidgetStatePropertyAll(AppTheme.hankoSumi3),
                  overlayColor:
                      WidgetStatePropertyAll(AppTheme.hankoPressWash),
                  splashFactory: NoSplash.splashFactory,
                  side: WidgetStatePropertyAll(
                      BorderSide(color: AppTheme.hankoEdge)),
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
          ],
        ),
      ],
    );
  }
}

/// From your watchlist tonight (Hanko stage H4, item d): one show from your
/// own watchlist, a different one each day, in the slot Tonight's Drop (the
/// same trending pick for everyone) used to hold. It shows only what the
/// entry holds, its episode count: "On your watchlist since March" waits
/// for a date the list can vouch for (question 27), and the year and
/// "AniList recommends it" line in the mockup aren't data Home has. The
/// whole pick is one button that opens the show.
class _WatchlistPick extends StatelessWidget {
  const _WatchlistPick({required this.entry, required this.onOpen});

  final Map<String, dynamic> entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title = entry['title'] as String? ?? 'Unknown';
    final episodes = entry['episodes'] as int?;
    final fact = episodes == null
        ? null
        : episodes == 1
            ? '1 episode'
            : '$episodes episodes';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('From your watchlist tonight',
              style: AppTheme.hankoSerif(height: 1.3)),
        ),
        const SizedBox(height: 12),
        // One semantics node (container) with the InkWell's tap and focus
        // inside it, as the lede (question 119; see
        // _HomeScreenState._buildLede). Its cover and words are left out of
        // the tree, since the label says them.
        Semantics(
          container: true,
          button: true,
          label: fact == null ? title : '$title, $fact',
          child: InkWell(
            onTap: onOpen,
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            hoverColor: AppTheme.hankoPressWash,
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HankoCover(
                      url: entry['imageUrl'] as String?, width: 72, height: 102),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FadeTitle(
                          title,
                          maxLines: 2,
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoFeaturedSize,
                              height: 1.15),
                        ),
                        if (fact != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            fact,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                color: AppTheme.hankoStone,
                                height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
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
    // label says only how far you are.
    final progressWords =
        hasTotal ? '$_current of $total' : '$_current watched';

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
            child: _HankoCover(url: imageUrl, width: 42, height: 60),
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
                    ExcludeSemantics(
                      child: Text(
                        progressWords,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoStone,
                          height: 1,
                          tabular: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: HankoReel(
                        watched: _current,
                        total: hasTotal ? total : null,
                        aired: aired ?? _current,
                        semanticLabel:
                            aired == null ? '$progressWords watched' : null,
                      ),
                    ),
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
}

/// Hanko's outlined +1 tile: sumi 3 with a 1 px edge outline (4.02:1), 48 dp
/// square, "+1" in Jost 600 washi. Outlined rather than filled because it
/// repeats on every row, and one filled main action per screen is the rule.
/// While its write is on its way the outline turns washi.
class _PlusOneTile extends StatelessWidget {
  const _PlusOneTile({
    required this.nextEpisode,
    required this.saving,
    required this.onTap,
  });

  final int nextEpisode;
  final bool saving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // One semantics node (container) with the InkWell's tap and focus
    // inside it, as the lede (question 119; see _HomeScreenState._buildLede).
    // "+1" is left out of the tree, since the label says what it does.
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: 'Mark episode $nextEpisode watched',
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: BorderSide(
              color: saving ? AppTheme.hankoWashi : AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: SizedBox(
              width: AppTheme.hankoTouch,
              height: AppTheme.hankoTouch,
              child: Center(
                child: Text(
                  '+1',
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
/// strip draws it (upcoming_anime.dart): a 72 x 102 cover with square 2 px
/// corners on sumi 3 while it loads, the title under it in Jost 500 12 on up
/// to two lines, and the 8% washi press. The column widens as the title's
/// text grows, so a long word still fits on one line at large text; the
/// strip's height follows (heightFor). Opens the show through Home's _open.
class _StripItem extends StatelessWidget {
  const _StripItem({required this.anime, required this.open});

  final Anime anime;
  final _Open open;

  static double _widthFor(TextScaler scaler) {
    final grow = scaler.scale(12) / 12;
    return grow > 1 ? 72 * grow : 72.0;
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
// Hanko's ranked row (hanko.html, Home): the rank in Shippori, a 34 × 48
// cover, the title on one line that fades out (Shippori draws "…" as the
// centred Japanese ellipsis), and AniList's score in indigo, the crowd's
// colour, so it never reads as your verdict (yours are seals). The score is
// out of 10 with one decimal, as everywhere else in Hanj.
class _ChartRow extends StatelessWidget {
  const _ChartRow({
    required this.anime,
    required this.rank,
    required this.onOpen,
  });

  final Anime anime;
  final int rank;
  final VoidCallback onOpen;

  static const double height = 56;

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
                _HankoCover(url: anime.imageUrl, width: 34, height: 48),
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
                  url: item['imageUrl'] as String?, width: 42, height: 60),
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
