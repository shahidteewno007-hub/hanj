import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

import '../../widgets/anilist_saved_note.dart';
import '../../widgets/hanko_cover_colour.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_flight.dart';
import '../../widgets/hanko_print.dart';
import '../../widgets/hanko_rating_ruler.dart';
import '../../widgets/hanko_reel.dart';
import '../../widgets/hanko_seal.dart';
import '../../widgets/hanko_seal_register.dart';
import '../../widgets/hanko_title_slip.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/confetti_overlay.dart';
import '../../models/anime_model.dart';
import '../../services/firestore_service.dart';
import '../../services/anilist_service.dart';
import '../../services/offline_cache_service.dart';
import '../../core/trailer_launcher.dart';
import '../../widgets/share_card.dart';
import '../episode_discussions/episode_discussion_screen.dart';
import '../social/arcs_hanko.dart';
import '../social/arcs_screen.dart';
import '../../services/arcs_service.dart';
import '../staff_detail/studio_detail_screen.dart';
import '../staff_detail/staff_detail_screen.dart';
import '../home/home_screen.dart' show showHanjListSheet;
import '../../models/achievements.dart' show Achievements;
import '../../services/achievements_service.dart';
import '../achievements/achievements_screen.dart' show AchievementSlip;

class AnimeDetailScreen extends StatefulWidget {
  final Anime anime;

  /// The print this page was opened from flies into its print (Print Room,
  /// P6): the flight's tag goes on Detail's print, and its colour is the
  /// field's from the first frame. Null when Detail was opened any other way.
  final HankoFlight? flight;

  const AnimeDetailScreen({super.key, required this.anime, this.flight});

  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen>
{
  // Today's header (the hero, the score row, the action row), switched off
  // since Hanko's header replaced it in stage H3. Kept, not deleted
  // (CLAUDE.md); true brings it back as it was. See _classicHeader.
  static const bool _classicDetail = false;

  // Print Room's Detail (DESIGN.md §9.5, stage P4; Shahid chose Print Room
  // 2026-11-03): the show's colour always on behind the print, from the top
  // of the screen, with a glow behind it; P1's print with its shadow and
  // sharp cover; the colophon in washi and the title at 28; and, on
  // Overview, the cast as round portraits and You may like as prints on
  // mats. Round seven's Detail is kept, not deleted (CLAUDE.md): false
  // brings it back as it was, the tint and all.
  static const bool _printRoom = true;

  // The seal press (Print Room, P6; DESIGN.md §9.3 A rule 5): rating, or
  // finishing a show you've rated, drops your seal onto the print, which
  // overshoots and settles while an ink ring spreads and fades, with one
  // haptic tick (HankoSealPress). P4's press, 1.06 to 1.0 in 120 ms on a
  // rating only, is kept, not deleted (CLAUDE.md): false brings it back.
  static const bool _sealPress = true;

  // +1 moves as Home's does (Print Room, P6; DESIGN.md §9.3 A rule 5, "the
  // tile dips, the count turns over; 200 ms"; question P6-4): the washi +1
  // dips to 0.90 and comes back, 60 ms in and 140 out, with no overshoot,
  // and the count's figure turns over in 160 ms (_HankoPlusOne,
  // _HankoRollingCount). The still +1 and count are kept, not deleted
  // (CLAUDE.md): false brings them back.
  static const bool _plusOneDip = true;

  // Detail opens lighter (Print Room P8; question P6-7). Reading your list
  // entry rebuilds only the header (the Episodes tab too, while it shows),
  // and AniList's full entry only the bar, the header and the tab's content,
  // as the staff answer already does (question 115). Each used to rebuild
  // the whole screen, the app bar, tab bar and Seasons strip among it,
  // which show none of it. Nothing on screen differs. False brings back the
  // whole-screen rebuilds as they were.
  static const bool _lightLoads = true;

  // With _lightLoads, the staff answer spread over frames (P8): the bar and
  // header in its frame, Overview a frame later, the Seasons walk after the
  // strips. Measured on the phone (2026-11-13) this turned one heavy frame
  // into two or three lighter ones, each still over budget. False keeps the
  // answer in one frame, with _lightLoads' narrower rebuilds.
  static const bool _spreadAnswer = true;

  final _firestoreService = FirestoreService();
  final _aniListService   = AnilistService();
  final _confettiKey      = GlobalKey<ConfettiOverlayState>();
  // Full anime details. Starts as whatever was passed in (may be a stub when
  // opened from Continue), then gets enriched via getAnimeById on open.
  late Anime _anime;
  String? _currentStatus;
  double? _userRating;
  int?    _currentEpisode;
  // When the rating was last saved (ratedAt), for the date beside the seal.
  // Null for ratings made during an import, and for one still saving.
  DateTime? _ratedAt;
  // False until the list entry has been read, so the seal's slot and the
  // status row don't show "not on your list" before anyone knows.
  bool _entryLoaded = false;
  bool    _isLoading       = false;
  int     _selectedTab     = 0;
  int     _swipeDirection  = 1; // 1 = left-to-right, -1 = right-to-left
  Map<String, dynamic>? _staffData;
  // The staff answer is always asked for on open, so with _lightLoads these
  // start true (P8): setting them a frame later rebuilt the bar, the header
  // and Overview, about 550 widgets, for flags only the Cast and You May
  // Like tabs read, and Detail always opens on Overview.
  bool _isLoadingStaff     = _lightLoads;
  List<Anime> _relatedAnime = [];
  List<String> _characterImages = [];
  List<String> _galleryImages = []; // high-res poster + banner for the gallery
  bool _isLoadingRelated   = _lightLoads;

  // Next episode airing data
  DateTime? _nextAiringAt;
  int?      _nextEpisodeNum;
  Timer?    _countdownTimer;
  // Ticks once a second. Held in a ValueNotifier rather than plain state so the
  // per-second update rebuilds only the countdown card, not this whole screen.
  final ValueNotifier<Duration> _timeUntilAiring =
      ValueNotifier<Duration>(Duration.zero);

  // Drives Hanko's top bar: its colour follows the field scrolling under it,
  // and the title fades in once the header's title has gone. Only the bar
  // listens, so scrolling never rebuilds the screen.
  final ScrollController _scroll = ScrollController();

  // Bumped by _staffChanged when the staff answer, its loading flags or the
  // next episode change. Only what shows them listens: the bar's tint, the
  // header and the tab content (question 115). A whole-screen setState there
  // rebuilt 583 widgets in one frame on the phone when the answer arrived,
  // the app bar's and the tab bar's among them, which show none of it.
  final ValueNotifier<int> _staffVersion = ValueNotifier<int>(0);

  // Bumped by _entryChanged when your list entry is read (P8). The header
  // listens to both; the tab content to this one only on the Episodes tab.
  final ValueNotifier<int> _entryVersion = ValueNotifier<int>(0);
  late final Listenable _headerVersion =
      Listenable.merge([_staffVersion, _entryVersion]);

  // With _lightLoads, the tab's content listens to this, bumped a frame after
  // _staffVersion (P8): the staff answer's frame builds the bar and the
  // header, and the next one Overview, so the answer costs two lighter frames
  // instead of one heavy one. Overview sits below the header, and a frame is
  // about 11 ms. _tabSoon keeps it to one bump per frame.
  final ValueNotifier<int> _tabVersion = ValueNotifier<int>(0);
  late final Listenable _tabEntryVersion =
      Listenable.merge([_tabVersion, _entryVersion]);
  bool _tabSoon = false;

  // Opened from the keyboard, Detail gives Back the keyboard focus (question
  // 153), so Enter works at once. The screen as a whole used to hold
  // Flutter's focus while the web page reported Back as focused, and Enter
  // did nothing until Tab was pressed. Traditional highlight mode means the
  // last input was a key or a mouse, not touch: opened by touch, nothing
  // changes.
  final bool _focusBack =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  // The Seasons strip (round seven): this show's PREQUEL and SEQUEL chain as
  // AnilistService walks it. Only the strip listens, so a step of the walk
  // rebuilds nothing else.
  final ValueNotifier<SeasonChain?> _seasons = ValueNotifier<SeasonChain?>(null);

  // Print Room's field (P4). Its colour is AniList's coverImage.color, from
  // the staff answer. Until that lands, a colour the Seasons walk already
  // knows for this show (_knownColour), so a season opened from the strip
  // has its field in the first frame. Without either, once AniList has
  // answered or failed (_staffSettled), the cover's own colour, read from
  // the cover by HankoCoverColour (_coverRead): waiting for the answer means
  // the field never shows the cover's colour and then switches to AniList's.
  // A MyAnimeList import reads its cover at once: AniList's data isn't its
  // own (§6c). A grey cover has no colour, so the page stays sumi.
  Color? _knownColour;
  Color? _coverRead;
  bool _staffSettled = false;

  @override
  void initState() {
    super.initState();
    _anime = widget.anime;
    // What this run already knows of the seasons, with no request: a season
    // opened from the strip shows the strip in its first frame.
    final id = int.tryParse(widget.anime.id);
    if (id != null && !_isMalImport) _seasons.value = AnilistService.knownSeasons(id);
    if (_printRoom) {
      for (final s in _seasons.value?.seasons ?? const <AnimeSeason>[]) {
        if (s.id == id) _knownColour = _hexColor(s.coverColor);
      }
      if (_isMalImport) _readCover();
    }
    _loadData();
    // Cache the anime for offline viewing later. Only a full entry (D18): a
    // stub from a list row has no synopsis or score, and caching it over a
    // full copy left that show bare offline, and on Home's "Coming up",
    // which opens from this cache first. A stub's full entry is cached when
    // getAnimeById returns it, in _loadFullAnime.
    if (!_isStub(widget.anime)) {
      OfflineCacheService.instance.cacheAnimeDetail(widget.anime);
    }
    // Defer network fetches until after the first frame so the synchronous
    // setState(isLoading=true) calls inside them don't fire during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFullAnime();
      // Stage 1c: one AniList request per open. The gallery, You May Like
      // and the next episode come from this response; they were three more.
      _loadStaffData();
    });
  }

  // Enrich the (possibly stub) anime with full details. When opened from
  // Continue, the passed object only has id/title/image/episodes/genres, so
  // score, status, season, romaji, synopsis etc. would be blank without this.
  /// A list row's stub, rather than an entry from an AniList query: no score,
  /// or no AniList status. My List's random pick passes your list status
  /// (WATCHING …) in that field, which AniList's statuses never share
  /// (AniList says FINISHED, the list COMPLETED), so it counts as a stub too.
  /// An unscored show from Search counts as well, and is looked up.
  static bool _isStub(Anime anime) =>
      anime.averageScore == null || !_mediaStatuses.contains(anime.status);

  /// AniList's MediaStatus values.
  static const _mediaStatuses = {
    'FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'CANCELLED', 'HIATUS',
  };

  Future<void> _loadFullAnime() async {
    // Skip if we already have rich data (opened from search/trending).
    if (!_isStub(widget.anime)) {
      return;
    }
    try {
      final full = await _aniListService.getAnimeById(widget.anime.id);
      if (full != null && mounted) {
        if (_lightLoads) {
          _staffChanged(() => _anime = full);
        } else {
          setState(() => _anime = full);
        }
        OfflineCacheService.instance.cacheAnimeDetail(full);
        // Nothing to re-run (D16): airing and You May Like used to be
        // fetched again here, the airing query with the same id both times.
        // Both now come from getAnimeStaff, which needs only the id.
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _timeUntilAiring.dispose();
    _scroll.dispose();
    _staffVersion.dispose();
    _entryVersion.dispose();
    _tabVersion.dispose();
    _seasons.dispose();
    super.dispose();
  }

  String _cleanDescription(String html) {
    return html
        // HTML tags
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?[ib]>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // Markdown links [text](url) → text
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        // __bold__ and **bold**
        .replaceAll(RegExp(r'_{2}([^_]+)_{2}'), r'$1')
        .replaceAll(RegExp(r'\*{2}([^*]+)\*{2}'), r'$1')
        // ~!spoiler!~ markers
        .replaceAll(RegExp(r'~!|!~'), '')
        // Bare URLs
        .replaceAll(RegExp(r'https?://\S+'), '')
        // $1 placeholders
        .replaceAll(RegExp(r'\$\d+'), '')
        // Source notes
        .replaceAll(RegExp(r'\(Source:[^)]+\)', caseSensitive: false), '')
        // Clean up excess newlines
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _loadData() async {
    final id     = int.parse(widget.anime.id);
    try {
      // One read of the list entry (H3 d). It used to be three sequential
      // reads of this same document, one per field.
      final entry  = await _firestoreService.getAnimeDetails(id);
      final status = entry?['status'] as String?;
      final rating = (entry?['userRating'] as num?)?.toDouble();
      final ep     = (entry?['currentEpisode'] as num?)?.toInt();
      final ratedAt = (entry?['ratedAt'] as Timestamp?)?.toDate();
      if (mounted) {
        _entryChanged(() {
          _currentStatus = status; _userRating = rating; _currentEpisode = ep;
          _ratedAt = ratedAt; _entryLoaded = true;
        });
      }
    } catch (_) {
      // Offline, a title that isn't on the list has no cached animeList doc,
      // so get() throws `unavailable`. Uncaught, that went to Crashlytics as
      // fatal on every such open. The screen just shows it as not on the list.
      if (mounted) _entryChanged(() => _entryLoaded = true);
    }
  }

  /// Applies the list entry's first read and rebuilds only what shows it
  /// (P8): the header, and the tab content on the Episodes tab. With the
  /// classic header, or _lightLoads off, the whole screen, as before.
  void _entryChanged(VoidCallback change) {
    if (_classicDetail || !_lightLoads) {
      setState(change);
      return;
    }
    change();
    _entryVersion.value++;
  }

  // Unused since Stage 1c: getAnimeStaff carries nextAiringEpisode. Kept as a
  // deletion candidate (CLAUDE.md), with _fetchAiringHttp below.
  Future<void> _loadAiringData() async {
    // Fetch regardless of entry point — when opened from Continue the anime
    // is a stub without a status field, so we can't gate on it. The query
    // returns null for shows that aren't airing, which we handle below.
    try {
      const url = 'https://graphql.anilist.co';
      final query = '''
      query(\$id: Int) {
        Media(id: \$id, type: ANIME) {
          nextAiringEpisode { airingAt episode }
        }
      }
      ''';
      final http = await _fetchAiringHttp(url, query, widget.anime.id);
      if (http == null || !mounted) return;
      final airingAt  = http['airingAt']  as int?;
      final episode   = http['episode']   as int?;
      if (airingAt == null) return;
      final dt = DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
      if (mounted) {
        setState(() {
          _nextAiringAt   = dt;
          _nextEpisodeNum = episode;
        });
        _timeUntilAiring.value = dt.difference(DateTime.now());
        // Tick every second
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          final diff = dt.difference(DateTime.now());
          _timeUntilAiring.value = diff.isNegative ? Duration.zero : diff;
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _fetchAiringHttp(
      String url, String query, String animeId) async {
    try {
      await AnilistService.throttle();
      final resp = await http.Client().post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: '{"query":"${query.replaceAll('\n', ' ').replaceAll('"', '\\"')}","variables":{"id":$animeId}}',
      ).timeout(const Duration(seconds: 8));
      AnilistService.noteLimits(resp.headers);
      if (resp.statusCode == 429) {
        AnilistService.backoff(
            int.tryParse(resp.headers['retry-after'] ?? '') ?? 10);
      }
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      return data['data']['Media']['nextAiringEpisode'] as Map<String, dynamic>?;
    } catch (_) { return null; }
  }

  /// Applies a change to the staff answer's state and rebuilds only what
  /// shows it (question 115). With the classic header back on, whose hero
  /// shows the gallery and the characters, the whole screen rebuilds, as it
  /// always did.
  void _staffChanged(VoidCallback change) {
    if (_classicDetail) {
      setState(change);
      return;
    }
    change();
    _staffVersion.value++;
    if (!_lightLoads || !_spreadAnswer || _tabSoon) return;
    _tabSoon = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabSoon = false;
      if (mounted) _tabVersion.value++;
    });
  }

  Future<void> _loadStaffData() async {
    if (mounted && !(_isLoadingStaff && _isLoadingRelated)) {
      _staffChanged(() { _isLoadingStaff = true; _isLoadingRelated = true; });
    }
    try {
      final data = await _aniListService.getAnimeStaff(_anime.id);
      if (mounted) {
        final chars = data?['characters']?['edges'] as List? ?? [];
        final imgs = <String>[];
        for (final e in chars) {
          final img = e['node']?['image']?['medium'] as String?;
          if (img != null && imgs.length < 8) imgs.add(img);
        }
        // The gallery: the sharp cover and the banner, or at least the cover
        // already on screen, so it is never empty.
        final gallery = <String>[
          if (data?['coverImage']?['extraLarge'] case final String xl) xl,
          if (data?['bannerImage'] case final String banner) banner,
        ];
        if (gallery.isEmpty && widget.anime.imageUrl != null) {
          gallery.add(widget.anime.imageUrl!);
        }
        _staffChanged(() {
          _staffData = data;
          _isLoadingStaff = false;
          _characterImages = imgs;
          _galleryImages = gallery;
          // You May Like: AniList users' recommendations for this show, not
          // the top-scored shows of its first genre.
          _relatedAnime = _aniListService.recommendationsFrom(data);
          _isLoadingRelated = false;
          _staffSettled = true;
        });
        // Print Room's field: no colour from AniList, so the cover's own.
        if (_printRoom && _coverColor == null && _knownColour == null) _readCover();
        // The Seasons strip (round seven): the answer carries this show's
        // relations. The walk starts from them after this frame, so the
        // strip adds nothing to the frame the answer lands in.
        AnilistService.noteSeasons(data);
        _walkSeasonsSoon();
        final next = data?['nextAiringEpisode'];
        final airingAt = next is Map ? next['airingAt'] as int? : null;
        if (airingAt != null) {
          _startCountdown(
            DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
            next['episode'] as int?,
          );
        }
      }
    } catch (_) {
      if (mounted) _staffChanged(() { _isLoadingStaff = false; _isLoadingRelated = false; _staffSettled = true; });
      // The seasons known from before still show.
      if (mounted) _walkSeasonsSoon();
      // Print Room's field, offline too: the cover is on screen already.
      if (mounted && _printRoom && _knownColour == null) _readCover();
    }
  }

  /// Reads the cover's own colour for Print Room's field (P4), from the
  /// cover Detail shows, with no request of its own: HankoCoverColour
  /// decodes it small from the same image. It never throws (Crashlytics
  /// reports an unhandled async error as fatal).
  void _readCover() {
    final url = widget.anime.imageUrl ?? _anime.imageUrl;
    if (url == null || url.isEmpty) return;
    if (HankoCoverColour.knows(url)) {
      _staffChanged(() => _coverRead = HankoCoverColour.peek(url));
      return;
    }
    unawaited(HankoCoverColour.ofUrl(url).then((colour) {
      if (mounted && colour != null) _staffChanged(() => _coverRead = colour);
    }));
  }

  /// Print Room's field colour (P4): AniList's, else what the Seasons walk
  /// knew, else the cover's own once AniList has had its say. Opened by a
  /// print's flight (P6), the colour that print's place showed, from the
  /// first frame, and it stays: AniList's, landing a second or more later,
  /// would change the page's colour under you as you read.
  Color? get _fieldColour {
    final flown = widget.flight?.colour;
    if (flown != null) return flown;
    final anilist = _coverColor ?? _knownColour;
    if (anilist != null) return anilist;
    return _staffSettled || _isMalImport ? _coverRead : null;
  }

  /// Walks this show's seasons after the current frame (round seven).
  void _walkSeasonsSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_lightLoads || !_spreadAnswer) {
        _walkSeasons();
        return;
      }
      // Two frames later still (P8): the frame after the answer's builds
      // Overview, the next one its cast and You may like (_NextFrame), and
      // the walk's first step, known already, reports at once.
      _afterFrames(2, () {
        if (mounted) _walkSeasons();
      });
    });
  }

  /// Runs [then] after [frames] more frames, asking for each (P8).
  static void _afterFrames(int frames, VoidCallback then) {
    if (frames <= 0) {
      then();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFrames(frames - 1, then));
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Walks this show's seasons, step by step, into the Seasons strip; also
  /// the strip's "Try again". A MyAnimeList import gets none: AniList data
  /// looked up by its id can belong to another show (§6c, as the print).
  void _walkSeasons() {
    final id = int.tryParse(widget.anime.id);
    if (id == null || _isMalImport) return;
    unawaited(_aniListService.walkSeasons(
      id,
      alive: () => mounted,
      onChain: (chain) {
        if (mounted) _seasons.value = chain;
      },
    ));
  }

  /// Opens another season's Detail in place of this one (round seven). The
  /// strip chooses a season rather than going deeper, so Back still leads
  /// where this Detail came from.
  void _openSeason(AnimeSeason season) {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AnimeDetailScreen(anime: season.toAnime())));
  }

  /// The next episode's live countdown, from the staff response.
  void _startCountdown(DateTime dt, int? episode) {
    _staffChanged(() {
      _nextAiringAt   = dt;
      _nextEpisodeNum = episode;
    });
    _timeUntilAiring.value = dt.difference(DateTime.now());
    // D17: one timer per screen. A second start used to leave the first
    // ticking, uncancelled, after the screen closed, since dispose() cancels
    // only the latest. Cancel before starting, whoever calls this.
    _countdownTimer?.cancel();
    // Tick every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final diff = dt.difference(DateTime.now());
      _timeUntilAiring.value = diff.isNegative ? Duration.zero : diff;
    });
  }

  // Unused since Stage 1c: getAnimeStaff carries both images. Kept as a
  // deletion candidate (CLAUDE.md).
  /// Fetches coverImage.extraLarge + bannerImage for the full-screen gallery.
  /// These are higher quality than the imageUrl already on the Anime model
  /// (which uses the 'large' variant). Falls back to the existing imageUrl
  /// so the gallery is never empty.
  Future<void> _loadGalleryImages() async {
    const url = 'https://graphql.anilist.co';
    const query = r'''
    query($id: Int) {
      Media(id: $id, type: ANIME) {
        coverImage { extraLarge }
        bannerImage
      }
    }
    ''';
    try {
      await AnilistService.throttle();
      final resp = await http.Client().post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({'query': query, 'variables': {'id': int.parse(widget.anime.id)}}),
      ).timeout(const Duration(seconds: 15));
      AnilistService.noteLimits(resp.headers);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final media = data['data']?['Media'];
        if (media != null && mounted) {
          final imgs = <String>[];
          final xl = media['coverImage']?['extraLarge'] as String?;
          final banner = media['bannerImage'] as String?;
          if (xl != null) imgs.add(xl);
          if (banner != null) imgs.add(banner);
          // Fallback: use existing imageUrl so gallery is never empty
          if (imgs.isEmpty && widget.anime.imageUrl != null) {
            imgs.add(widget.anime.imageUrl!);
          }
          setState(() => _galleryImages = imgs);
        }
      }
    } catch (_) {
      // Fallback silently
      if (mounted && widget.anime.imageUrl != null) {
        setState(() => _galleryImages = [widget.anime.imageUrl!]);
      }
    }
  }

  // Unused since Stage 1c: You May Like is AniList's recommendations, from
  // getAnimeStaff. Kept as a deletion candidate (CLAUDE.md).
  Future<void> _loadRelatedAnime() async {
    setState(() => _isLoadingRelated = true);
    try {
      final related = await _aniListService.getRecommendedAnime(_anime.id, _anime.genres);
      if (mounted) setState(() { _relatedAnime = related; _isLoadingRelated = false; });
    } catch (_) { if (mounted) setState(() => _isLoadingRelated = false); }
  }

  void _showWatchPicker(BuildContext context, dynamic anime) {
    final title = Uri.encodeComponent(anime.titleEnglish ?? anime.title);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1612),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Watch on', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      final uri = Uri.parse('https://www.crunchyroll.com/search?q=$title');
                      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
                      catch (_) { await launchUrl(uri, mode: LaunchMode.platformDefault); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0C02),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF47521).withValues(alpha: 0.4)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.play_circle_outline_rounded,
                              size: 30, color: Color(0xFFF47521)),
                          SizedBox(height: 8),
                          Text('Crunchyroll', style: TextStyle(color: Color(0xFFF47521), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      final uri = Uri.parse('https://www.netflix.com/search?q=$title');
                      try { await launchUrl(uri, mode: LaunchMode.externalApplication); }
                      catch (_) { await launchUrl(uri, mode: LaunchMode.platformDefault); }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A0202),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE50914).withValues(alpha: 0.4)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.play_circle_outline_rounded,
                              size: 30, color: Color(0xFFE50914)),
                          SizedBox(height: 8),
                          Text('Netflix', style: TextStyle(color: Color(0xFFE50914), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddToListSheet() async {
    final result = await showHanjListSheet(
      context: context,
      anime: _anime,
      currentStatus: _currentStatus,
    );
    if (!mounted || result == null) return;
    if (result == '__REMOVE__') {
      setState(() => _isLoading = true);
      await _firestoreService.removeAnimeFromList(int.parse(widget.anime.id));
      if (!mounted) return;
      setState(() { _currentStatus = null; _userRating = null; _currentEpisode = null; _ratedAt = null; _isLoading = false; });
    } else {
      // Sheet already saved to Firestore — just update UI immediately
      setState(() => _currentStatus = result);
      // The sheet reported it to achievements (showHanjListSheet). Finishing
      // a show you've rated presses your seal, with its tick, so the slip
      // stays silent (decision h).
      if (Achievements.replaceCards && result == 'COMPLETED' && _userRating != null) {
        AchievementSlip.expect(context,
            feedback: AchievementSlip.sheetClosing, ticked: _sealPress);
      }
      // Hanko drops Detail's confetti (H3 f); it plays only with the classic
      // header back on.
      if (_classicDetail && result == 'COMPLETED') {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _confettiKey.currentState?.launch(); });
      } else if (result == 'WATCHING') {
        // Wait for the bottom sheet's dismiss animation to finish before
        // showing the episode dialog — prevents the two animations overlapping.
        await Future.delayed(const Duration(milliseconds: 280));
        if (mounted) _showEpisodeDialog();
      }
    }
  }

  Future<void> _selectStatus(String status) async {
    if (!mounted) return;
    setState(() { _currentStatus = status; });
    if (status == 'COMPLETED') {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _confettiKey.currentState?.launch(); });
    }
  }

  void _showRatingDialog() {
    // A rating is a field on the list entry and updateRating is an update(),
    // so a show that isn't on the list has nowhere to keep one.
    if (_currentStatus == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add it to your list to rate it.')),
      );
      return;
    }
    double tempRating = _userRating ?? 5.0;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, s) => AlertDialog(
          backgroundColor: AppTheme.surfaceMid,
          title: Text('Rate this Anime', style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tempRating.toStringAsFixed(1), style: AppTheme.serif(fontSize: 56, weight: FontWeight.w700, color: AppTheme.primary)),
              Text('/ 10', style: AppTheme.mono(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 16),
              Slider(value: tempRating, min: 1.0, max: 10.0, divisions: 18, activeColor: AppTheme.primary, onChanged: (v) => s(() => tempRating = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: AppTheme.sans(color: AppTheme.textMuted))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await _firestoreService.updateRating(int.parse(widget.anime.id), tempRating);
                } catch (e) {
                  // update() throws not-found when the entry doesn't exist.
                  // Uncaught, that reached Crashlytics as fatal and the
                  // rating silently didn't save.
                  if (!mounted) return;
                  final missing = e is FirebaseException && e.code == 'not-found';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(missing
                        ? 'Add it to your list to rate it.'
                        : 'Your rating didn\'t save. Try again.'),
                  ));
                  return;
                }
                if (!mounted) return;
                setState(() => _userRating = tempRating);
              },
              child: Text('Save', style: AppTheme.sans(color: AppTheme.primary, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  /// Saves a rating from the ruler (H3 c), with the same updateRating the
  /// dialog used, caught so a rejected write never reaches Crashlytics as a
  /// fatal. A re-rate offers Undo for 4 s; a first rating has none, since
  /// that would need a write that clears the rating.
  Future<void> _rate(double rating) async => _applyRating(rating, offerUndo: true);

  /// The rating shows at once and saves in the background (H3 e), the way
  /// Home's +1 works. A refused save puts the previous rating back, unless a
  /// newer one has been made since. Offline, the save waits for the
  /// connection and the new rating stays.
  void _applyRating(double rating, {required bool offerUndo}) {
    final previous = _userRating;
    final previousAt = _ratedAt;
    if (rating == previous) return;
    setState(() { _userRating = rating; _ratedAt = DateTime.now(); });
    // Achievements: a seal can earn one (Sealed, Finished and sealed, the
    // whole ruler). The slip waits for your seal's press, which ticked.
    if (Achievements.replaceCards) {
      AchievementSlip.expect(context,
          feedback: HankoSealPress.duration, ticked: _sealPress);
      unawaited(AchievementsService.instance.noteAction(widget.anime.id, {
        'userRating': rating,
        'ratedAt': FieldValue.serverTimestamp(),
      }).catchError((Object _) {}));
    }
    if (offerUndo && previous != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          // Since Flutter 3.44 a snack bar with an action stays until it's
          // tapped or swiped (persist defaults to action != null), so Undo
          // never left by itself and anything queued behind it (the
          // achievement slip) waited for good. It goes after its 4 s again;
          // with TalkBack on it stays until dismissed, as the slip does,
          // so a screen reader user has the time to reach Undo.
          persist: MediaQuery.accessibleNavigationOf(context),
          content: Text('Rated ${HankoSeal.formatScore(rating)}.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (mounted) _undoRating(rating, previous, previousAt);
            },
          ),
        ));
    }
    unawaited(_saveRating(rating).then((saved) {
      if (!saved && mounted && _userRating == rating) {
        setState(() { _userRating = previous; _ratedAt = previousAt; });
      }
    }));
  }

  /// Undo after a re-rate puts back the previous rating with its own date,
  /// not today's: the seal's "Yours 25 Oct" reads it, and so will the diary.
  /// A rating with no date (an import's) gets its date removed again. Shown
  /// at once like any rating; a refused save puts the re-rate back, unless
  /// the rating has changed since.
  void _undoRating(double undone, double previous, DateTime? previousAt) {
    final undoneAt = _ratedAt;
    setState(() { _userRating = previous; _ratedAt = previousAt; });
    unawaited(_saveRating(previous, restoring: true, ratedAt: previousAt).then((saved) {
      if (!saved && mounted && _userRating == previous) {
        setState(() { _userRating = undone; _ratedAt = undoneAt; });
      }
    }));
  }

  /// +1 (H3 f): the episode goes up at once and saves in the background, as
  /// Home's +1 does; a refused save puts it back and says so. Offline, the
  /// save waits for the connection and the new number stays. At the last
  /// episode it also writes Completed the way Home's does, a status update
  /// with no activity event (the logic change question 4 approved). With no
  /// episode total it never finishes the show. No confetti: in Hanko the
  /// moment of finishing is pressing your seal.
  Future<void> _bump() async {
    final total = _anime.episodes;
    final from = _currentEpisode ?? 0;
    final next = from + 1;
    final hasTotal = total != null && total > 0;
    if (hasTotal && next > total) return;
    final finishes = hasTotal && next >= total;
    final statusBefore = _currentStatus;
    setState(() {
      _currentEpisode = next;
      if (finishes) _currentStatus = 'COMPLETED';
    });
    // Achievements: the +1 that finishes a show, reported as it shows (the
    // writes below wait for the connection offline). The slip waits for
    // +1's dip; a show you've rated is sealed again, and that press ticks.
    if (Achievements.replaceCards && finishes) {
      AchievementSlip.expect(context,
          feedback: HankoSealPress.duration,
          ticked: _sealPress && _userRating != null);
      unawaited(AchievementsService.instance.noteAction(widget.anime.id, {
        'currentEpisode': next,
        'lastWatched': FieldValue.serverTimestamp(),
        'status': 'COMPLETED',
      }).catchError((Object _) {}));
    }
    try {
      await _firestoreService.updateEpisodeProgress(int.parse(widget.anime.id), next);
    } catch (_) {
      if (!mounted) return;
      // Roll back only this +1, unless another has been made since.
      if (_currentEpisode == next) {
        setState(() {
          _currentEpisode = from;
          if (finishes && _currentStatus == 'COMPLETED') _currentStatus = statusBefore;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Your progress didn\'t save. Try again.'),
      ));
      return;
    }
    if (!finishes) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('animeList')
          .doc(widget.anime.id)
          .update({'status': 'COMPLETED'});
    } catch (_) {
      // The episode saved; only the status didn't.
      if (!mounted) return;
      if (_currentStatus == 'COMPLETED') setState(() => _currentStatus = statusBefore);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Couldn\'t mark it completed. Try again.'),
      ));
    }
  }

  /// updateRating, caught: says what went wrong and returns false. With
  /// [restoring] (Undo), it writes [ratedAt] back instead of a new date, or
  /// removes it when the restored rating had none; updateRating always
  /// stamps the server's time.
  Future<bool> _saveRating(double rating, {bool restoring = false, DateTime? ratedAt}) async {
    try {
      if (restoring) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return true; // as updateRating does, signed out
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('animeList')
            .doc(widget.anime.id)
            .update({
          'userRating': rating,
          'ratedAt': ratedAt == null ? FieldValue.delete() : Timestamp.fromDate(ratedAt),
        });
      } else {
        await _firestoreService.updateRating(int.parse(widget.anime.id), rating);
      }
      return true;
    } catch (e) {
      // update() throws not-found when the entry doesn't exist.
      if (mounted) {
        final missing = e is FirebaseException && e.code == 'not-found';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(missing
              ? 'Add it to your list to rate it.'
              : 'Your rating didn\'t save. Try again.'),
        ));
      }
      return false;
    }
  }

  void _showEpisodeDialog() {
    final total = _anime.episodes;
    showDialog(
      context: context,
      builder: (_) => _EpisodeInputDialog(
        total: total,
        initial: _currentEpisode ?? 0,
        onSave: (clamped) async {
          try {
            await _firestoreService.updateEpisodeProgress(
                int.parse(widget.anime.id), clamped);
          } catch (_) {
            // The dialog doesn't await onSave, so a rejected update() went
            // to PlatformDispatcher.onError, a fatal Crashlytics report, and
            // the progress silently didn't save.
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Your progress didn\'t save. Try again.'),
            ));
            return;
          }
          if (mounted) setState(() => _currentEpisode = clamped);
        },
      ),
    );
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'WATCHING': return 'WATCHING';
      case 'COMPLETED': return 'COMPLETED';
      case 'PLAN_TO_WATCH': return 'PLAN';
      case 'DROPPED': return 'DROPPED';
      default: return 'ADD';
    }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'WATCHING': return AppTheme.watching;
      case 'COMPLETED': return AppTheme.completed;
      case 'PLAN_TO_WATCH': return AppTheme.planToWatch;
      case 'DROPPED': return AppTheme.dropped;
      default: return AppTheme.primary;
    }
  }

  IconData _statusIcon(String? s) {
    switch (s) {
      case 'WATCHING':      return Icons.play_circle_rounded;
      case 'COMPLETED':     return Icons.check_circle_rounded;
      case 'PLAN_TO_WATCH': return Icons.bookmark_rounded;
      case 'DROPPED':       return Icons.cancel_rounded;
      default:              return Icons.add_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final anime = _anime;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              if (_classicDetail)
                ..._classicHeader(context, anime, screenHeight)
              else
                ..._hankoHeader(context, anime),

              // Tab bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  _SimpleTabBar(
                    selected: _selectedTab,
                    onTap: (i) => setState(() => _selectedTab = i),
                  ),
                  // 48 dp labels, the indicator and the rule, growing with
                  // the text size instead of overflowing a fixed 52.
                  height: math.max(52.0, 32 + MediaQuery.textScalerOf(context).scale(13) * 1.5),
                ),
              ),
            // Tab content — swipeable via horizontal drag. It rebuilds with
            // the staff answer on its own (question 115), from here down, as
            // the whole screen's setState did: a tab fading out keeps what
            // it showed.
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: !_lightLoads
                    ? _staffVersion
                    : !_spreadAnswer
                        ? (_selectedTab == 1 ? _headerVersion : _staffVersion)
                    : _selectedTab == 1
                        ? _tabEntryVersion
                        : _tabVersion,
                builder: (_, _) => GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity == null) return;
                    // A swipe steps through the tabs shown, past a hidden
                    // one (Episodes, round seven).
                    const shown = _SimpleTabBar.shown;
                    final at = shown.indexOf(_selectedTab);
                    if (details.primaryVelocity! < -200 && at < shown.length - 1) {
                      setState(() { _swipeDirection = 1; _selectedTab = shown[at + 1]; });
                    } else if (details.primaryVelocity! > 200 && at > 0) {
                      setState(() { _swipeDirection = -1; _selectedTab = shown[at - 1]; });
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) {
                      // A CurveTween, not a CurvedAnimation (question 141). This
                      // builder runs on every rebuild of the tab content, and each
                      // CurvedAnimation left a status listener on the switcher's
                      // controller that nothing removed. With no reverse curve,
                      // the two give the same values.
                      final offset = animation.drive(Tween<Offset>(
                        begin: Offset(_swipeDirection * 0.18, 0),
                        end: Offset.zero,
                      ).chain(CurveTween(curve: Curves.easeOut)));
                      return SlideTransition(
                        position: offset,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(_selectedTab),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight: screenHeight * 0.4),
                        child: _TabContent(
                          selectedIndex: _selectedTab,
                          anime: _anime,
                          staffData: _staffData,
                          isLoadingStaff: _isLoadingStaff,
                          cleanDescription: _cleanDescription,
                          currentEpisode: _currentEpisode,
                          relatedAnime: _relatedAnime,
                          isLoadingRelated: _isLoadingRelated,
                          nextAiringAt: _nextAiringAt,
                          nextEpisodeNum: _nextEpisodeNum,
                          timeUntilAiring: _timeUntilAiring,
                          characterImages: _characterImages,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          ),
          if (_classicDetail) ConfettiOverlay(key: _confettiKey),
        ],
      ),
    );
  }

  // ── Today's header, kept behind a flag (stage H3) ──────────
  // Hanko's header replaced the hero, the score row, the genre chips and
  // the action row. CLAUDE.md: never delete, so they are kept here, moved
  // out of build() unchanged, and switched off by _classicDetail. Deletion
  // candidates, with _HeroPanel and _IconBtn.
  List<Widget> _classicHeader(BuildContext context, Anime anime, double screenHeight) => [
              // Hero
              SliverAppBar(
                expandedHeight: screenHeight * 0.50,
                pinned: true,
                backgroundColor: AppTheme.background,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),
                actions: [
                  GestureDetector(
                    onTap: () => showShareCard(context, anime: anime, status: _currentStatus, userRating: _userRating),
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                flexibleSpace: FlexibleSpaceBar(background: _HeroPanel(anime: anime, characterImages: _characterImages, galleryImages: _galleryImages)),
              ),

              // Meta
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Season label
                      if (anime.season != null || anime.seasonYear != null)
                        Text(
                          '步 · ${anime.season != null ? "${anime.season![0]}${anime.season!.substring(1).toLowerCase()} " : ""}${anime.seasonYear ?? ""} · ${anime.titleEnglish ?? anime.title}'.toUpperCase(),
                          style: AppTheme.mono(fontSize: 10, color: AppTheme.primary, letterSpacing: 1),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 6),
                      Text(anime.titleEnglish ?? anime.title, style: AppTheme.serif(fontSize: 26, weight: FontWeight.w700, height: 1.1)),
                      if (anime.titleEnglish != null && anime.title != anime.titleEnglish) ...[
                        const SizedBox(height: 2),
                        Text(anime.title, style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted).copyWith(fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 16),
                      // Score row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SCORE', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    anime.averageScore != null ? (anime.averageScore! / 10).toStringAsFixed(1) : '—',
                                    style: AppTheme.serif(fontSize: 42, weight: FontWeight.w700, color: AppTheme.primary, height: 1),
                                  ),
                                  Text(' / 10', style: AppTheme.mono(fontSize: 12, color: AppTheme.textMuted)),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (anime.episodes != null || anime.format != null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (anime.format != null)
                                  Text(anime.format!.replaceAll('_', ' '),
                                      style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.5)),
                                if (anime.episodes != null)
                                  Text('${anime.episodes} EP',
                                      style: AppTheme.mono(fontSize: 14, weight: FontWeight.w700, color: AppTheme.textSecondary)),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Genre chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (anime.status == 'RELEASING') ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(20)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text('ON AIR', style: AppTheme.mono(fontSize: 10, color: Colors.white, weight: FontWeight.w700, letterSpacing: 0.5)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                            ],
                            for (final g in anime.genres.take(3)) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
                                child: Text(g, style: AppTheme.sans(fontSize: 12, color: AppTheme.textSecondary)),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action buttons
                      _classicActions(anime),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
      ];

  Widget _classicActions(Anime anime) =>
                      Row(
                        children: [
                          Expanded(
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _isLoading ? null : _showAddToListSheet,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(color: _statusColor(_currentStatus), borderRadius: BorderRadius.circular(30)),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (_isLoading)
                                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      else ...[
                                        Icon(_statusIcon(_currentStatus), color: Colors.white, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          _currentStatus != null
                                              ? (_currentStatus == 'WATCHING' &&
                                                      _currentEpisode != null &&
                                                      _currentEpisode! > 0
                                                  ? '${_statusLabel(_currentStatus)} · EP $_currentEpisode'
                                                  : '${_statusLabel(_currentStatus)} · Edit')
                                              : 'Add to list',
                                          style: AppTheme.sans(fontSize: 14, weight: FontWeight.w600, color: Colors.white),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (anime.trailerUrl != null)
                            _IconBtn(icon: Icons.play_arrow_rounded, onTap: () => _showWatchPicker(context, anime), color: AppTheme.surfaceLight),
                          if (anime.trailerUrl != null) const SizedBox(width: 8),
                          _IconBtn(
                            icon: Icons.star_rounded,
                            onTap: _showRatingDialog,
                            color: _userRating != null ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.surfaceLight,
                            iconColor: _userRating != null ? AppTheme.accent : AppTheme.textSecondary,
                            badge: _userRating?.toStringAsFixed(1),
                          ),
                        ],
                      );

  // ── Hanko's header (stage H3) ───────────────────────────────

  /// A MyAnimeList import (D21): keyed by its MyAnimeList id and showing
  /// MyAnimeList's cover. Until the import fix lands, AniList data looked up
  /// by that id can belong to another show, so the print keeps the cover the
  /// row showed, with no sharp cover, tint or slip from AniList (§6c).
  bool get _isMalImport =>
      Uri.tryParse(widget.anime.imageUrl ?? '')?.host.contains('myanimelist') ?? false;

  String? get _nativeTitle =>
      _isMalImport ? null : _staffData?['title']?['native'] as String?;
  String? get _sharpCover =>
      _isMalImport ? null : _staffData?['coverImage']?['extraLarge'] as String?;
  Color? get _coverColor =>
      _isMalImport ? null : _hexColor(_staffData?['coverImage']?['color'] as String?);

  String? get _studioName {
    final nodes = _staffData?['studios']?['nodes'] as List?;
    return nodes != null && nodes.isNotEmpty ? nodes.first['name'] as String? : null;
  }

  /// The series director, from Stage 1c's `directors` (the first six staff by
  /// relevance): "Director", else "Chief Director". Null when AniList lists
  /// neither there.
  ({int id, String name})? get _director {
    final edges = _staffData?['directors']?['edges'] as List? ?? const [];
    for (final role in const ['director', 'chief director']) {
      for (final e in edges) {
        if (e is! Map || (e['role'] as String?)?.trim().toLowerCase() != role) continue;
        final id = e['node']?['id'] as int?;
        final name = e['node']?['name']?['full'] as String?;
        if (id != null && name != null && name.isNotEmpty) return (id: id, name: name);
      }
    }
    return null;
  }

  /// AniList's users' scores per 10-point bucket, {10: 1159, … 100: 106581}.
  Map<int, int> get _scoreDistribution => {
        for (final e in _staffData?['stats']?['scoreDistribution'] as List? ?? const [])
          if (e is Map && e['score'] is int && e['amount'] is int)
            e['score'] as int: e['amount'] as int,
      };

  /// AniList's coverImage.color, "#bbf1a1".
  static Color? _hexColor(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  List<Widget> _hankoHeader(BuildContext context, Anime anime) {
    // Read where they're shown, from _anime (P8): AniList's full entry
    // rebuilds only the bar and the header, and can change the title.
    String title() => _anime.titleEnglish ?? _anime.title;
    // The URL the previous screen showed: decoded already, so the print is
    // there in the first frame.
    String? shownCover() => widget.anime.imageUrl ?? _anime.imageUrl;
    return [
      SliverAppBar(
        pinned: true,
        toolbarHeight: 48,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: 'Back',
          autofocus: _focusBack,
          icon: const Icon(Icons.arrow_back_sharp),
          color: AppTheme.hankoWashi,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_sharp),
            color: AppTheme.hankoWashi,
            onPressed: () => showShareCard(context,
                anime: _anime, status: _currentStatus, userRating: _userRating),
          ),
          const SizedBox(width: 4),
        ],
        // The bar and the header below take the cover's tint, the studio
        // and the rest from the staff answer, and rebuild with it on their
        // own (question 115).
        flexibleSpace: ListenableBuilder(
          listenable: _staffVersion,
          builder: (_, _) => _printRoom
              ? _PrintRoomBar(
                  scroll: _scroll,
                  colour: _fieldColour,
                  geometry: HankoDetailHeader.geometryFor(MediaQuery.sizeOf(context).width),
                  title: title(),
                )
              : _HankoBar(
                  scroll: _scroll,
                  tint: AppTheme.hankoCoverTint(_coverColor),
                  geometry: HankoDetailHeader.geometryFor(MediaQuery.sizeOf(context).width),
                  title: title(),
                ),
        ),
      ),
      SliverToBoxAdapter(
        child: ListenableBuilder(
          listenable: _headerVersion,
          builder: (_, _) {
            final anime = _anime;
            final cover = shownCover();
            final studio = _studioName;
            final director = _director;
            return HankoDetailHeader(
              title: title(),
              nativeTitle: _nativeTitle,
              coverUrl: cover,
              // The print it was opened from lands here (P6).
              printTag: widget.flight?.tag,
              sharpCoverUrl: _sharpCover,
              // Print Room's field colour (P4): AniList's, or the cover's own.
              coverColor: _printRoom ? _fieldColour : _coverColor,
              // The studio and director links (H3 k): the pages Detail already
              // opened from its Information block and its Cast tab.
              studio: studio,
              onStudio: studio == null
                  ? null
                  : () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => StudioDetailScreen(studioName: studio))),
              director: director?.name,
              onDirector: director == null
                  ? null
                  : () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => StaffDetailScreen(staffId: director.id, staffName: director.name))),
              format: anime.format,
              season: anime.season,
              seasonYear: anime.seasonYear,
              episodes: anime.episodes,
              duration: _staffData?['duration'] as int?,
              airing: anime.status == 'RELEASING',
              entryLoaded: _entryLoaded,
              status: _currentStatus,
              rating: _userRating,
              ratedAt: _ratedAt,
              currentEpisode: _currentEpisode,
              nextEpisode: _nextEpisodeNum,
              nextAiringAt: _nextAiringAt,
              // A MyAnimeList import AniList hasn't replaced still carries MAL's
              // mean (the import stores mean × 10), so it gets no "AniList" crowd.
              averageScore: _isMalImport && identical(anime, widget.anime) ? null : anime.averageScore,
              scoreDistribution: _scoreDistribution,
              busy: _isLoading,
              onRate: _rate,
              onStatus: _showAddToListSheet,
              onBump: _bump,
              onCover: cover == null
                  ? null
                  : () => _openGallery(context,
                      _isMalImport || _galleryImages.isEmpty ? [cover] : _galleryImages, 0),
            );
          },
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      // The Seasons strip (round seven), between the header and the tabs. It
      // listens on its own: a step of the walk rebuilds only the strip.
      SliverToBoxAdapter(
        child: ValueListenableBuilder<SeasonChain?>(
          valueListenable: _seasons,
          builder: (context, chain, _) => chain == null || !_HankoSeasons.shows(chain)
              ? const SizedBox.shrink()
              : _HankoSeasons(chain: chain, onOpen: _openSeason, onRetry: _walkSeasons),
        ),
      ),
    ];
  }
}

// ── Hanko header (stage H3) ──────────────────────────────────

/// Detail's header in Hanko (stage H3; `design/mockups/looks/hanko.html`,
/// frames 2 and 8). The whole cover as a print of about 208 dp on a field
/// tinted from its own colour, the native title on a slip pasted on it, the
/// facts beside it like a book's colophon, and the title below, on the field.
///
/// It takes plain values and reports through callbacks, so the dev specimen
/// (`lib/hanko_dev.dart`) can draw it with inline data and no Firebase or
/// network. Public only for that specimen; the app builds it from
/// [AnimeDetailScreen] alone.
class HankoDetailHeader extends StatefulWidget {
  const HankoDetailHeader({
    super.key,
    required this.title,
    this.nativeTitle,
    this.coverUrl,
    this.printTag,
    this.sharpCoverUrl,
    this.coverColor,
    this.studio,
    this.onStudio,
    this.director,
    this.onDirector,
    this.format,
    this.season,
    this.seasonYear,
    this.episodes,
    this.duration,
    this.airing = false,
    this.entryLoaded = true,
    this.status,
    this.rating,
    this.ratedAt,
    this.currentEpisode,
    this.nextEpisode,
    this.nextAiringAt,
    this.averageScore,
    this.scoreDistribution = const {},
    this.busy = false,
    this.onCover,
    this.onRate,
    this.onStatus,
    this.onBump,
  });

  /// The show's name as the app shows it: English, else romaji.
  final String title;

  /// AniList's `title.native`, for the slip. A title with no Japanese (or
  /// other CJK) letters gets no slip. The slip is switched off since round
  /// seven (`_HankoPrint._showNativeTitle`).
  final String? nativeTitle;

  /// The cover the previous screen showed (AniList's `large`, 230 px wide).
  /// It is in the image cache already, so the print is there in the first
  /// frame.
  final String? coverUrl;

  /// The Hero tag of the print Detail was opened from (Print Room, P6), on
  /// Print Room's print, so that print flies into this one. Null: no Hero.
  final Object? printTag;

  /// AniList's `extraLarge` (460 px), crossfading in over [coverUrl].
  final String? sharpCoverUrl;

  /// AniList's `coverImage.color`: the print's colour until the art loads,
  /// and at 20% the field behind it, neutral near the seal's hue. In Print
  /// Room (P4) the field's colour, AniList's or else the cover's own, mixed
  /// by the field rule with no hue guard.
  final Color? coverColor;

  final String? studio;

  /// Opens the studio's page.
  final VoidCallback? onStudio;

  /// Who directed it, and opening their page.
  final String? director;
  final VoidCallback? onDirector;

  /// AniList's MediaFormat (TV, MOVIE, ONA …) and season (WINTER …).
  final String? format;
  final String? season;
  final int? seasonYear;
  final int? episodes;

  /// Minutes per episode; a film's whole length.
  final int? duration;

  /// Still airing (AniList's RELEASING).
  final bool airing;

  /// Whether your list entry has been read. Until it has, the seal's slot
  /// stays empty rather than guess.
  final bool entryLoaded;

  /// Your list status (WATCHING, COMPLETED …), or null when the show isn't
  /// on your list.
  final String? status;

  /// Your rating as stored. An imported one can be off the 1–10 scale (D20);
  /// the seal shows it as it is.
  final double? rating;

  /// When you rated it; null for a rating made during an import.
  final DateTime? ratedAt;

  /// The episode you're on, from your list entry.
  final int? currentEpisode;

  /// AniList's next airing episode and when it airs, for an airing show: the
  /// reel outlines what has aired, and a line says when the next one does.
  final int? nextEpisode;
  final DateTime? nextAiringAt;

  /// The crowd: AniList's average score (0–100), shown on Hanj's 10-point
  /// scale, and its users' scores per 10-point bucket
  /// (`stats.scoreDistribution`). No score, no crowd: an unaired show.
  final double? averageScore;
  final Map<int, int> scoreDistribution;

  /// A change to your list is under way (removing the show): the status
  /// button shows a spinner and doesn't open the sheet.
  final bool busy;

  /// Opens the gallery.
  final VoidCallback? onCover;

  /// Saves a rating from the ruler, once your finger lets go. The seal keeps
  /// showing the new rating until this completes, then shows [rating].
  final Future<void> Function(double rating)? onRate;

  /// Opens the status sheet: the status word, or "Add to list".
  final VoidCallback? onStatus;

  /// Marks the next episode watched: the +1 shown while you're watching.
  final VoidCallback? onBump;

  /// The header's sizes at [width]: the print is 208 by 293 from a 360 dp
  /// phone up, smaller on narrower screens so the facts keep room. The field
  /// fades out by the title, starting a little past half its height.
  static ({double printWidth, double printHeight, double titleTop, double fieldHeight, double fadeFrom})
      geometryFor(double width) {
    final inner = width - 2 * AppTheme.hankoGutter;
    final printWidth = math.min(208.0, (inner * 0.65).floorToDouble());
    final printHeight = (printWidth * 293 / 208).roundToDouble();
    final titleTop = 4 + printHeight + 12;
    final fieldHeight = titleTop + 16;
    return (
      printWidth: printWidth,
      printHeight: printHeight,
      titleTop: titleTop,
      fieldHeight: fieldHeight,
      fadeFrom: (fieldHeight * 0.55).roundToDouble(),
    );
  }

  /// The colophon's fact lines: "TV", "Fall 2023", "28 episodes" (or, airing
  /// with no total yet, "5 episodes so far"), "24 min each". What's missing
  /// is left out, never guessed. The format has a line
  /// of its own: in the column beside the print (92 dp on a 360 dp phone),
  /// "TV, Spring 2009" wrapped and left "TV," alone. The season and its year
  /// share the next line whenever they fit; when larger text can't fit them,
  /// they break between the two words, never inside the year (a no-break
  /// space there split "Spring 200 / 9" at 1.3×).
  static List<String> _factsFor({
    String? format,
    String? season,
    int? seasonYear,
    int? episodes,
    int? duration,
    bool airing = false,
    int? nextEpisode,
  }) {
    final film = format == 'MOVIE';
    final formatWord = switch (format) {
      null => null,
      'TV' => 'TV',
      'TV_SHORT' => 'TV short',
      'MOVIE' => 'Film',
      'SPECIAL' => 'Special',
      'MUSIC' => 'Music video',
      _ => format.replaceAll('_', ' '),
    };
    final seasonWord = [
      if (season != null && season.isNotEmpty)
        '${season[0]}${season.substring(1).toLowerCase()}',
      if (seasonYear != null) '$seasonYear',
    ].join(' ');
    // An airing show with no total yet counts what has aired, the episodes
    // before the next one: the count lives here since the Episodes tab went
    // (round seven). "so far" stays with its "episodes" when the column is
    // too narrow for the line.
    final aired = airing && nextEpisode != null ? nextEpisode - 1 : 0;
    final count = film
        ? null
        : episodes != null && episodes > 0
            ? '$episodes ${episodes == 1 ? 'episode' : 'episodes'}'
            : aired > 0
                ? '$aired ${aired == 1 ? 'episode' : 'episodes'} so\u00A0far'
                : null;
    return [
      ?formatWord,
      seasonWord,
      ?count,
      if (airing) 'Airing',
      if (duration != null && duration > 0)
        film || episodes == 1 ? '$duration min' : '$duration min each',
    ].where((s) => s.isNotEmpty).toList();
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  /// "3 Oct", or "3 Oct 2025" outside this year; [long] spells the month.
  static String _date(DateTime d, {bool long = false}) {
    final month = (long ? _monthNames : _months)[d.month - 1];
    return d.year == DateTime.now().year ? '${d.day} $month' : '${d.day} $month ${d.year}';
  }

  /// Your seal, pressed across the print's edge: filled with [shown] (your
  /// rating, or the one under your finger), or the empty dashed slot where it
  /// will go. Nothing until the entry is read.
  Widget _seal(double? shown) {
    if (!entryLoaded) return const SizedBox.square(dimension: 56);
    final rating = shown;
    if (status == null) {
      return const HankoSeal.unrated(size: 56, showAdd: false, semanticLabel: 'Not on your list');
    }
    if (rating == null) return const HankoSeal.unrated(size: 56, showAdd: false);
    final when = ratedAt;
    return HankoSeal.score(
      rating,
      size: 56,
      semanticLabel: 'Your rating, ${HankoSeal.formatScore(rating)}'
          '${when == null ? '' : ', rated ${_date(when, long: true)}'}',
    );
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  /// "Episode 8 on Saturday": today, tomorrow, a weekday within the week,
  /// else the date. Worked out once per build, so nothing ticks; the live
  /// countdown stays in Overview. Calendar days are counted between UTC
  /// dates, as Home's Coming up counts them (question 111): between local
  /// midnights, a change to or from summer time made a day 23 hours long,
  /// and tomorrow read "today".
  String? get _nextLine {
    final at = nextAiringAt;
    final episode = nextEpisode;
    if (at == null || episode == null) return null;
    final now = DateTime.now();
    final day = DateTime.utc(at.year, at.month, at.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    final when = switch (day) {
      < 0 => 'is out',
      0 => 'today',
      1 => 'tomorrow',
      < 7 => 'on ${_weekdays[at.weekday - 1]}',
      _ => 'on ${_date(at)}',
    };
    return 'Episode $episode $when';
  }

  /// The words beside the seal: whose it is and when, or what to do.
  String? get _caption {
    if (!entryLoaded) return null;
    if (status == null) return 'Add to your list to rate';
    if (rating == null) return 'Rate it';
    final when = ratedAt;
    return when == null ? 'Your rating' : 'Yours\n${_date(when)}';
  }

  @override
  State<HankoDetailHeader> createState() => _HankoDetailHeaderState();
}

class _HankoDetailHeaderState extends State<HankoDetailHeader> {
  // The rating under your finger while you drag the ruler, and after you let
  // go until the save is through. Only the seal listens, so a drag never
  // rebuilds the screen (a whole-screen rebuild costs 17–19 ms, PERF.md).
  final ValueNotifier<double?> _preview = ValueNotifier<double?>(null);

  // Counts ratings made here, so the seal's press replays for each one.
  int _presses = 0;

  @override
  void didUpdateWidget(HankoDetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Finishing a show you've rated seals it again (P6, rule 5): the press
    // replays when your status turns Completed here, by the last +1 or the
    // status sheet. Not when the entry is first read, and not for a show
    // with no rating, which has no seal yet.
    if (_AnimeDetailScreenState._sealPress &&
        oldWidget.entryLoaded &&
        widget.entryLoaded &&
        oldWidget.status != 'COMPLETED' &&
        widget.status == 'COMPLETED' &&
        widget.rating != null) {
      _presses++;
    }
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _release(double rating) async {
    _preview.value = rating;
    if (rating != widget.rating) setState(() => _presses++);
    await widget.onRate?.call(rating);
    if (mounted) _preview.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final g = HankoDetailHeader.geometryFor(constraints.maxWidth);
        // The caption's top sits 14 px below the seal's, as drawn, whether it
        // runs to one line or two; larger text lets it grow upward.
        final captionLine = MediaQuery.textScalerOf(context).scale(AppTheme.hankoDataSmallSize) * 1.35;
        final caption = widget._caption;
        final onList = widget.entryLoaded && widget.status != null;
        final watched = widget.currentEpisode ??
            (widget.status == 'COMPLETED' ? widget.episodes ?? 0 : 0);
        final printRoom = _AnimeDetailScreenState._printRoom;
        return Stack(
          children: [
            if (printRoom)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: _PrintRoomField.end(g.printHeight),
                child: _PrintRoomField(
                  colour: widget.coverColor,
                  printWidth: g.printWidth,
                  printHeight: g.printHeight,
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: g.fieldHeight,
                child: _HankoField(
                  tint: AppTheme.hankoCoverTint(widget.coverColor),
                  fadeFrom: g.fadeFrom / g.fieldHeight,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (printRoom)
                            _PrintRoomPrint(
                              width: g.printWidth,
                              height: g.printHeight,
                              title: widget.title,
                              coverUrl: widget.coverUrl,
                              heroTag: widget.printTag,
                              coverColor: widget.coverColor,
                              nativeTitle: widget.nativeTitle,
                              onTap: widget.onCover,
                            )
                          else
                            _HankoPrint(
                              width: g.printWidth,
                              height: g.printHeight,
                              title: widget.title,
                              coverUrl: widget.coverUrl,
                              sharpCoverUrl: widget.sharpCoverUrl,
                              coverColor: widget.coverColor,
                              nativeTitle: widget.nativeTitle,
                              onTap: widget.onCover,
                            ),
                          const SizedBox(width: 20),
                          Expanded(
                            // At least the print's height, so the caption can
                            // sit at its foot beside the seal; taller only if
                            // large text makes the facts run long.
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: g.printHeight),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _HankoColophon(
                                    // The column beside the print, for
                                    // Print Room's whole words (P4).
                                    width: constraints.maxWidth - 2 * AppTheme.hankoGutter - g.printWidth - 20,
                                    // The seal's top (keyline included):
                                    // see the Positioned seal below.
                                    sealTop: g.printHeight - 68 - AppTheme.hankoKeyline,
                                    studio: widget.studio,
                                    onStudio: widget.onStudio,
                                    director: widget.director,
                                    onDirector: widget.onDirector,
                                    facts: HankoDetailHeader._factsFor(
                                      format: widget.format,
                                      season: widget.season,
                                      seasonYear: widget.seasonYear,
                                      episodes: widget.episodes,
                                      duration: widget.duration,
                                      airing: widget.airing,
                                      nextEpisode: widget.nextEpisode,
                                    ),
                                  ),
                                  Padding(
                                    // Clear of the seal's 8 px past the print
                                    // and 10 px from it.
                                    padding: EdgeInsets.only(
                                      left: 18,
                                      top: 8,
                                      bottom: math.max(0.0, 54 - 2 * captionLine),
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(minHeight: 2 * captionLine),
                                      child: caption == null
                                          ? null
                                          : ExcludeSemantics(
                                              excluding: widget.rating != null,
                                              child: Text(
                                                caption,
                                                style: AppTheme.hankoSans(
                                                  fontSize: AppTheme.hankoDataSmallSize,
                                                  // On Print Room's field all
                                                  // text is washi (P4).
                                                  color: printRoom
                                                      ? AppTheme.hankoWashi
                                                      : AppTheme.hankoStoneHi,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        left: g.printWidth - 28,
                        top: g.printHeight - 68,
                        // P6: the seal drops onto the print, overshoots and
                        // settles, with its ink ring and one haptic tick.
                        child: _AnimeDetailScreenState._sealPress
                            ? HankoSealPress(
                                presses: _presses,
                                child: ValueListenableBuilder<double?>(
                                  valueListenable: _preview,
                                  builder: (context, preview, _) => widget._seal(preview ?? widget.rating),
                                ),
                              )
                            // Rating presses the seal in, 1.06 to 1.0 in 120
                            // ms; with Remove animations on, it simply appears.
                            : TweenAnimationBuilder<double>(
                                key: ValueKey(_presses),
                                tween: Tween(begin: _presses == 0 || still ? 1.0 : AppTheme.hankoSealPressScale, end: 1.0),
                                duration: AppTheme.hankoSealPress,
                                curve: Curves.easeOut,
                                builder: (context, scale, seal) => Transform.scale(scale: scale, child: seal),
                                child: ValueListenableBuilder<double?>(
                                  valueListenable: _preview,
                                  builder: (context, preview, _) => widget._seal(preview ?? widget.rating),
                                ),
                              ),
                      ),
                    ],
                  ),
                  // Print Room's title is larger (28) and needs the air.
                  SizedBox(height: printRoom ? _PrintRoomField.titleGap : 12),
                  _HankoTitle(title: widget.title),
                  const SizedBox(height: 8),
                  // The status row (H3 g): "Add to list" as the screen's one
                  // main action, or your status as a word that opens the
                  // sheet. Its height is kept while the entry is read.
                  if (!widget.entryLoaded)
                    const SizedBox(height: AppTheme.hankoTouch)
                  else if (widget.status == null)
                    _HankoMainAction(
                      label: 'Add to list',
                      icon: Icons.add_sharp,
                      onTap: widget.onStatus,
                    )
                  else
                    _HankoStatusButton(
                      status: widget.status!,
                      busy: widget.busy,
                      onTap: widget.onStatus,
                    ),
                  // The ruler rates, 1 to 10 in half steps, saving when you
                  // let go. Only for a show on your list: a rating lives on
                  // the list entry (no D4).
                  if (onList) ...[
                    const SizedBox(height: 4),
                    HankoRatingRuler(
                      value: widget.rating,
                      onChanged: (v) => _preview.value = v,
                      onChangeEnd: _release,
                    ),
                  ],
                  // Where you are: while watching, and for any show you've
                  // watched some of. Completed with no count stored means
                  // every episode. A film or other one-episode work shows no
                  // "1 of 1" unless you're watching it.
                  if (onList &&
                      (widget.status == 'WATCHING' ||
                          (watched > 0 && widget.episodes != 1))) ...[
                    const SizedBox(height: 10),
                    _HankoEpisodes(
                      watched: watched,
                      total: widget.episodes,
                      // Aired so far: up to the next episode of an airing
                      // show; nothing known past what you've watched when
                      // it airs with no date; all of them otherwise.
                      aired: widget.nextEpisode != null
                          ? widget.nextEpisode! - 1
                          : (widget.airing ? watched : null),
                      nextLine: widget._nextLine,
                      // +1 while watching, until the last episode. It
                      // dips as Home's does (P6, _plusOneDip).
                      action: widget.status == 'WATCHING' &&
                              (widget.episodes == null ||
                                  widget.episodes! <= 0 ||
                                  watched < widget.episodes!)
                          ? _AnimeDetailScreenState._plusOneDip
                              ? _HankoPlusOne(
                                  nextEpisode: watched + 1,
                                  onTap: widget.onBump,
                                )
                              : _HankoMainAction(
                                  label: '+1',
                                  icon: null,
                                  semanticLabel: 'Mark episode ${watched + 1} watched',
                                  minWidth: 76,
                                  minHeight: 56,
                                  fontSize: 20,
                                  onTap: widget.onBump,
                                )
                          : null,
                    ),
                  ],
                  // The crowd (H3 h), after the screen's one hairline.
                  if (widget.averageScore != null) ...[
                    const SizedBox(height: 14),
                    const ColoredBox(
                      color: AppTheme.hankoHairline,
                      child: SizedBox(height: 1, width: double.infinity),
                    ),
                    const SizedBox(height: 10),
                    _HankoCrowd(
                      averageScore: widget.averageScore!,
                      distribution: widget.scoreDistribution,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The crowd: "AniList 9.1", the number in indigo, the crowd's colour, and
/// beside it the same scores as a seal register in indigo, on Hanj's 1–10
/// ruler (AniList's buckets 10 … 100 sit on 1 … 10). The register shows only
/// when AniList has a distribution.
class _HankoCrowd extends StatelessWidget {
  const _HankoCrowd({required this.averageScore, required this.distribution});

  final double averageScore;
  final Map<int, int> distribution;

  @override
  Widget build(BuildContext context) {
    final score = (averageScore / 10).toStringAsFixed(1);
    return Row(
      children: [
        Semantics(
          label: 'AniList average, $score out of 10',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(
              text: 'AniList ',
              children: [
                TextSpan(
                  text: score,
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoAi,
                  ),
                ),
              ],
            ),
            style: AppTheme.hankoSans(fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone),
          ),
        ),
        const Spacer(),
        if (distribution.values.any((n) => n > 0))
          SizedBox(
            width: 112,
            child: HankoSealRegister.anilist(distribution, averageScore: averageScore.round()),
          ),
      ],
    );
  }
}

/// The screen's one main action: a washi tile with sumi words (15.34:1),
/// 2 px corners, pressed with an 8% wash and no ripple.
class _HankoMainAction extends StatelessWidget {
  const _HankoMainAction({
    required this.label,
    required this.onTap,
    required this.icon,
    this.semanticLabel,
    this.minWidth = AppTheme.hankoTouch,
    this.minHeight = AppTheme.hankoTouch,
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// What a screen reader says instead of [label] ("+1" says little).
  final String? semanticLabel;
  final double minWidth;
  final double minHeight;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    // Its own semantics node (container) with the InkWell's tap and focus
    // inside it (question 104, as the status word). With a [semanticLabel],
    // the label used to sit over excluded semantics, which dropped the
    // InkWell's tap: a screen reader found "Mark episode 8 watched" but
    // couldn't press it. Now only the words drawn on the tile are left out,
    // under the InkWell, when the label replaces them.
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          child: ExcludeSemantics(
            excluding: semanticLabel != null,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth, minHeight: minHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: icon == null ? 14 : 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: AppTheme.hankoSumi),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: AppTheme.hankoSans(
                        fontSize: fontSize,
                        weight: FontWeight.w600,
                        color: AppTheme.hankoSumi,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the show is to you, as a word you can change: the status sheet opens
/// from it, for every status, as today's pill did.
class _HankoStatusButton extends StatelessWidget {
  const _HankoStatusButton({required this.status, required this.busy, required this.onTap});

  final String status;
  final bool busy;
  final VoidCallback? onTap;

  static (IconData, String) _look(String status) => switch (status) {
        'WATCHING' => (Icons.play_circle_sharp, 'Watching'),
        'PLAN_TO_WATCH' => (Icons.bookmark_sharp, 'Plan to watch'),
        'COMPLETED' => (Icons.check_circle_sharp, 'Completed'),
        'DROPPED' => (Icons.cancel_sharp, 'Dropped'),
        _ => (Icons.circle_outlined, status),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, word) = _look(status);
    // Its own semantics node (container), named "Status: <word>", with the
    // InkWell's tap and focus inside it (question 104; the container pattern
    // of dd45bd1 and 2d721db). A label over excluded semantics dropped both,
    // so a screen reader found the word but couldn't open the sheet, and on
    // the web the word couldn't take focus. Only the row's own word and icons
    // are left out, under the InkWell, so the word isn't read twice.
    return Semantics(
      container: true,
      button: true,
      enabled: !busy && onTap != null,
      label: 'Status: $word',
      hint: 'Change status',
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.hankoWashi),
                          )
                        : Icon(icon, size: 20, color: AppTheme.hankoWashi),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    word,
                    style: AppTheme.hankoSans(fontSize: 15, weight: FontWeight.w500, height: 1),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_sharp, size: 20, color: AppTheme.hankoStone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where you are in the show: "Episode", then "7 of 28" (the number in
/// Mincho, the total in Jost), the reel (off, _reel), and when the next
/// episode airs, with the +1 beside it while you're watching.
class _HankoEpisodes extends StatelessWidget {
  const _HankoEpisodes({
    required this.watched,
    required this.total,
    required this.aired,
    required this.nextLine,
    required this.action,
  });

  /// The reel under "7 of 28" (HankoReel), switched off. Shahid, 2026-11-05:
  /// "I don't like the episode count lines that show like how many episodes
  /// you have watched, remove that just have 9 of 12". The count then says
  /// "watched" to a screen reader, as the reel did.
  static const bool _reel = false;

  final int watched;
  final int? total;

  /// Episodes aired so far, or null when every one has.
  final int? aired;
  final String? nextLine;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final total = this.total != null && this.total! > 0 ? this.total : null;
    final action = this.action;
    final nextLine = this.nextLine;
    // "7 of 28" as it's drawn; with the reel off it also says "watched".
    final words = total != null ? '$watched of $total' : '$watched';
    final figure = AppTheme.hankoSerif(fontSize: 30, height: 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Episode',
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: AppTheme.hankoStone,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              if (_AnimeDetailScreenState._plusOneDip)
                // The figure turns over when +1 lands (P6): its own small
                // widget, on " of 28"'s baseline, and said with it in one
                // label, as Text.rich's semanticsLabel did.
                Semantics(
                  label: _reel ? words : '$words watched',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        _HankoRollingCount(value: watched, style: figure),
                        if (total != null)
                          Text(
                            ' of $total',
                            // Set on the figure's line, as when they were one
                            // paragraph. Each paragraph rounds its own
                            // baseline, so on a line of its own " of 28" sat
                            // half a dp low and the row 0.37 dp taller.
                            strutStyle: StrutStyle.fromTextStyle(figure, forceStrutHeight: true),
                            style: AppTheme.hankoSans(fontSize: 15, color: AppTheme.hankoStone, height: 1),
                          ),
                      ],
                    ),
                  ),
                )
              else
                Text.rich(
                  TextSpan(
                    text: '$watched',
                    children: [
                      if (total != null)
                        TextSpan(
                          text: ' of $total',
                          style: AppTheme.hankoSans(fontSize: 15, color: AppTheme.hankoStone, height: 1),
                        ),
                    ],
                  ),
                  semanticsLabel: _reel
                      ? null
                      : total != null
                          ? '$watched of $total watched'
                          : '$watched watched',
                  style: AppTheme.hankoSerif(fontSize: 30, height: 1),
                ),
              // The reel: one tick per episode, watched solid, aired and
              // waiting outlined, still to air short (a line past 30). Off
              // since 2026-11-05 (_reel).
              if (_reel) ...[
                const SizedBox(height: 10),
                HankoReel(watched: watched, total: total, aired: aired),
              ],
              if (nextLine != null) ...[
                const SizedBox(height: 8),
                Text(
                  nextLine,
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    color: AppTheme.hankoStone,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 18), action],
      ],
    );
  }
}

/// Detail's +1, moving as Home's does (Print Room, P6; DESIGN.md §9.3 A rule
/// 5; question P6-4): each tap dips the washi tile to 0.90 and brings it
/// back, 60 ms in and 140 out, ease out, with no overshoot, which is the
/// seal's. The count turns over meanwhile (_HankoRollingCount). With "remove
/// animations" on it doesn't move.
///
/// The tile is +1's _HankoMainAction as it was, scaled whole, its tap and
/// focus with it, so it stays one button with the same label. Only the tile
/// moves: a transition on its own controller, in a layer of its own, so a dip
/// rebuilds and repaints nothing else on the page. "Add to list", the same
/// main action, doesn't dip.
class _HankoPlusOne extends StatefulWidget {
  const _HankoPlusOne({required this.nextEpisode, required this.onTap});

  final int nextEpisode;
  final VoidCallback? onTap;

  @override
  State<_HankoPlusOne> createState() => _HankoPlusOneState();
}

class _HankoPlusOneState extends State<_HankoPlusOne>
    with SingleTickerProviderStateMixin {
  // Home's dip (_PlusOneTileState): 0.90 at 60 ms, at rest by 200.
  late final AnimationController _dip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.90).chain(CurveTween(curve: Curves.easeOut)),
      weight: 60,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.90, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
      weight: 140,
    ),
  ]).animate(_dip);

  @override
  void dispose() {
    _dip.dispose();
    super.dispose();
  }

  void _tap() {
    if (!MediaQuery.disableAnimationsOf(context)) _dip.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ScaleTransition(
        scale: _scale,
        child: _HankoMainAction(
          label: '+1',
          icon: null,
          semanticLabel: 'Mark episode ${widget.nextEpisode} watched',
          minWidth: 76,
          minHeight: 56,
          fontSize: 20,
          onTap: widget.onTap == null ? null : _tap,
        ),
      ),
    );
  }
}

/// The count's figure, which turns over when it changes (Print Room, P6), as
/// Home's Continue count does (_RollingCount, round seven): the new figure
/// comes up from below as the old one leaves upward, 160 ms, so a +1 is seen
/// to land in "7 of 28". A count that goes back (a refused save) rolls the
/// other way. Still with "remove animations" on. In a layer of its own, so a
/// roll repaints nothing else on the page.
class _HankoRollingCount extends StatefulWidget {
  const _HankoRollingCount({required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  State<_HankoRollingCount> createState() => _HankoRollingCountState();
}

class _HankoRollingCountState extends State<_HankoRollingCount> {
  bool _up = true;

  @override
  void didUpdateWidget(_HankoRollingCount old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _up = widget.value > old.value;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final current = ValueKey(widget.value);
    return RepaintBoundary(
      child: ClipRect(
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
              position: Tween(begin: Offset(0, edge), end: Offset.zero).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: Text('${widget.value}', key: current, style: widget.style),
        ),
      ),
    );
  }
}

/// The colour a 20% cover tint gives over sumi, or sumi when there's none.
Color _hankoFieldColour(Color? tint) =>
    tint == null ? AppTheme.hankoSumi : Color.alphaBlend(tint, AppTheme.hankoSumi);

/// The tinted field behind the print: solid, then fading to sumi by the
/// title. The tint arrives with the staff response, so it fades in.
class _HankoField extends StatelessWidget {
  const _HankoField({required this.tint, required this.fadeFrom});

  final Color? tint;
  final double fadeFrom;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _hankoFieldColour(tint)),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      builder: (context, solid, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, fadeFrom, 1],
            colors: [solid!, solid, AppTheme.hankoSumi],
          ),
        ),
      ),
    );
  }
}

/// Hanko's top bar behind back and share. At the top it is the field's
/// colour, so bar and field read as one; as the field scrolls under it, it
/// takes the colour passing beneath, and once the header's title has gone,
/// the title fades in. Only this listens to the scroll.
class _HankoBar extends StatelessWidget {
  const _HankoBar({
    required this.scroll,
    required this.tint,
    required this.geometry,
    required this.title,
  });

  final ScrollController scroll;
  final Color? tint;
  final ({double printWidth, double printHeight, double titleTop, double fieldHeight, double fadeFrom})
      geometry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _hankoFieldColour(tint)),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      builder: (context, solid, _) => AnimatedBuilder(
        animation: scroll,
        builder: (context, _) {
          final offset = scroll.hasClients ? scroll.offset : 0.0;
          final fade = ((offset - g.fadeFrom) / (g.fieldHeight - g.fadeFrom)).clamp(0.0, 1.0);
          final shown = ((offset - g.titleTop) / 24).clamp(0.0, 1.0);
          return ColoredBox(
            color: Color.lerp(solid, AppTheme.hankoSumi, fade)!,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: shown == 0
                      ? null
                      : ExcludeSemantics(
                          child: Text(
                            title,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: AppTheme.hankoSerif(
                              color: AppTheme.hankoWashi.withValues(alpha: shown),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Print Room's field on Detail (stage P4; DESIGN.md §9.5, frame 03): the
/// show's colour by the field rule (AppTheme.hankoField: at most 45% of it
/// in sumi, capped at a luminance of 0.10 where text sits, no hue guard),
/// always on, from the top of the screen, with a glow of the colour behind
/// the print.
///
/// It's anchored to the print, not the title, so it's the same whatever the
/// title's length or the text size: solid down to [_lead] above the print's
/// foot, then fading over 150 dp to nothing [_tail] below it, the mockup's
/// numbers for a two-line title. The glow is P1's (the field rule at the
/// glow cap, for where no text sits), a circle of [_glowRadius] round the
/// print's centre: the mockup's 170 × 210 ellipse, made round as
/// HankoField's glow is.
///
/// It's P1's HankoField on a box of known size, in the header's coordinates
/// (its top is the bar's foot). [above] reaches the box up past the
/// header's top: the bar draws the same field from the top of the screen
/// (_PrintRoomBar), so the two meet with no seam.
class _PrintRoomField extends StatelessWidget {
  const _PrintRoomField({
    required this.colour,
    required this.printWidth,
    required this.printHeight,
    this.above = 0,
  });

  final Color? colour;
  final double printWidth;
  final double printHeight;

  /// How far the box reaches above the header's top.
  final double above;

  /// Where the print starts in the header (HankoDetailHeader's 4 dp).
  static const double _printTop = 4;
  static const double _lead = 49;
  static const double _tail = 101;
  static const double _glowRadius = 170;

  /// From the print's foot to the title: the larger title needs the air.
  static const double titleGap = 20;

  /// Where the field ends, in the header: [_tail] below the print's foot.
  static double end(double printHeight) => _printTop + printHeight + _tail;

  /// Where the title starts, in the header.
  static double titleTop(double printHeight) => _printTop + printHeight + titleGap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = above + end(printHeight);
        final fadeFrom = above + _printTop + printHeight - _lead;
        final glowX = AppTheme.hankoGutter + printWidth / 2;
        final glowY = above + _printTop + printHeight / 2;
        return HankoField(
          colour: colour,
          solidTo: fadeFrom / height,
          glow: Alignment(2 * glowX / width - 1, 2 * glowY / height - 1),
          glowRadius: _glowRadius / math.min(width, height),
          child: SizedBox(width: width, height: height),
        );
      },
    );
  }
}

/// Print Room's top bar on Detail (P4), behind back and share: a window
/// onto the header's field. It draws the same field, from the top of the
/// screen, moved up as the page scrolls, over sumi. At rest the field reads
/// as one from the top of the screen, its glow included, where a flat bar
/// would cut the glow with a straight line; scrolled, the bar shows exactly
/// what passes under it (the field, its fade, then sumi) and nothing scrolls
/// through it. The field is its own layer and only moves as the page
/// scrolls, so a scroll repaints nothing but the title. Once the header's
/// title has gone, the title fades in, as round seven's bar does.
class _PrintRoomBar extends StatelessWidget {
  const _PrintRoomBar({
    required this.scroll,
    required this.colour,
    required this.geometry,
    required this.title,
  });

  final ScrollController scroll;
  final Color? colour;
  final ({double printWidth, double printHeight, double titleTop, double fieldHeight, double fadeFrom})
      geometry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    final titleTop = _PrintRoomField.titleTop(g.printHeight);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The bar's whole height: the status bar's and the toolbar's.
        final bar = constraints.maxHeight;
        final field = RepaintBoundary(
          child: _PrintRoomField(
            colour: colour,
            printWidth: g.printWidth,
            printHeight: g.printHeight,
            above: bar,
          ),
        );
        return ClipRect(
          child: ColoredBox(
            color: AppTheme.hankoSumi,
            child: AnimatedBuilder(
              animation: scroll,
              child: field,
              builder: (context, field) {
                final offset = scroll.hasClients ? scroll.offset : 0.0;
                final shown = ((offset - titleTop) / 24).clamp(0.0, 1.0);
                return Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: bar + _PrintRoomField.end(g.printHeight),
                      child: Transform.translate(offset: Offset(0, -offset), child: field),
                    ),
                    Positioned.fill(
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 56),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: shown == 0
                                ? null
                                : ExcludeSemantics(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.fade,
                                      style: AppTheme.hankoSerif(
                                        color: AppTheme.hankoWashi.withValues(alpha: shown),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Print Room's print on Detail (P4): P1's HankoPrint at 208 dp, with the
/// hero's shadow (one rectangle shadow, question 161) and the 460 px cover
/// from the first frame (question 167): the stored cover until it arrives,
/// or for good if it can't, and a MyAnimeList import keeps its own. Kept
/// from round seven: the 1 px washi ring, so a dark cover keeps its edge on
/// a dark field, drawn over the shadow, which would dim it; the button that
/// opens the gallery; and the native title's slip, off with round seven's
/// own switch.
class _PrintRoomPrint extends StatelessWidget {
  const _PrintRoomPrint({
    required this.width,
    required this.height,
    required this.title,
    required this.coverUrl,
    required this.heroTag,
    required this.coverColor,
    required this.nativeTitle,
    required this.onTap,
  });

  final double width;
  final double height;
  final String title;
  final String? coverUrl;

  /// The flight's tag (P6): the print Detail was opened from lands here.
  final Object? heroTag;
  final Color? coverColor;
  final String? nativeTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final art = Stack(
      clipBehavior: Clip.none,
      children: [
        HankoPrint(
          url: coverUrl,
          width: width,
          height: height,
          lift: HankoPrintLift.large,
          sharp: true,
          placeholder: coverColor ?? AppTheme.hankoSumi3,
          heroTag: heroTag,
        ),
        Positioned(
          left: -1,
          top: -1,
          right: -1,
          bottom: -1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.hankoWashi.withValues(alpha: 0.12)),
              borderRadius: const BorderRadius.all(Radius.circular(AppTheme.hankoRadius + 1)),
            ),
          ),
        ),
        if (_HankoPrint._showNativeTitle && HankoTitleSlip.shows(nativeTitle))
          Positioned(
            left: 10,
            top: 10,
            child: HankoTitleSlip(
              nativeTitle: nativeTitle,
              maxHeight: height - 25,
              maxWidth: width - 20,
            ),
          ),
      ],
    );
    // As round seven's print: its own semantics node with the InkWell's tap
    // and focus inside it (question 139), the InkWell over the art on its
    // own transparent Material, since the cover would hide ink drawn under
    // it, and the art left out of the tree, since the label says it.
    return Semantics(
      container: true,
      image: true,
      button: onTap != null,
      label: 'Cover of $title',
      hint: onTap != null ? 'Opens the gallery' : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: art),
          if (onTap != null)
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The print: the whole cover, never cropped to a band, with its native
/// title on a slip (switched off, see [_showNativeTitle]). Tapping it opens
/// the gallery.
class _HankoPrint extends StatelessWidget {
  // The native title's slip is switched off (round seven). Shahid left it to
  // the main session ("Maybe remove the japanese if you suggest"), which
  // recommended removing it: the slip set the title in the phone's own
  // Japanese font, not Hanko's, and most of Hanj's users can't read it. Kept,
  // not deleted (CLAUDE.md); true brings it back as it was.
  static const bool _showNativeTitle = false;

  const _HankoPrint({
    required this.width,
    required this.height,
    required this.title,
    required this.coverUrl,
    required this.sharpCoverUrl,
    required this.coverColor,
    required this.nativeTitle,
    required this.onTap,
  });

  final double width;
  final double height;
  final String title;
  final String? coverUrl;
  final String? sharpCoverUrl;
  final Color? coverColor;
  final String? nativeTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = coverUrl;
    final sharp = sharpCoverUrl != null && sharpCoverUrl != base ? sharpCoverUrl : null;
    Widget none(BuildContext _, String _, Object _) => const SizedBox.shrink();
    final art = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: coverColor ?? AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        // A 1 px washi ring, so a dark cover keeps its edge on a dark field.
        boxShadow: [
          BoxShadow(color: AppTheme.hankoWashi.withValues(alpha: 0.12), spreadRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (base != null)
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
            if (_showNativeTitle && HankoTitleSlip.shows(nativeTitle))
              Positioned(
                left: 10,
                top: 10,
                child: HankoTitleSlip(
                  nativeTitle: nativeTitle,
                  maxHeight: height - 25,
                  maxWidth: width - 20,
                ),
              ),
          ],
        ),
      ),
    );
    // Its own semantics node (container) with the InkWell's tap and focus
    // inside it (question 139, R5B's pattern), so the keyboard reaches it:
    // the GestureDetector gave a screen reader the tap but no focus. The
    // InkWell lies over the art on its own transparent Material, since ink
    // is drawn under a Material's children and the cover would hide it. The
    // art is left out of the tree: the label says it.
    return Semantics(
      container: true,
      image: true,
      button: onTap != null,
      label: 'Cover of $title',
      hint: onTap != null ? 'Opens the gallery' : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: art),
          if (onTap != null)
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The facts beside the print, set like a book's colophon: the studio, then
/// format and season, episodes and their length, and who directed it. The
/// studio and the director are links (H3 k), each opening its own page.
class _HankoColophon extends StatelessWidget {
  const _HankoColophon({
    required this.width,
    required this.studio,
    required this.onStudio,
    required this.director,
    required this.onDirector,
    required this.facts,
    this.sealTop = double.infinity,
  });

  /// The column's width: in Print Room (P4) a name wider than it is set a
  /// little smaller rather than broken between its letters.
  final double width;
  final String? studio;
  final VoidCallback? onStudio;
  final String? director;
  final VoidCallback? onDirector;
  final List<String> facts;

  /// Where the seal's keyline starts, from the colophon's top. A line that
  /// would run into it steps right, clear of the seal's corner.
  final double sealTop;

  @override
  Widget build(BuildContext context) {
    final studio = this.studio;
    final director = this.director;
    // On Print Room's field all text is washi (P4; DESIGN.md §9.3 rule 2):
    // stone hi falls to 3.96:1 on the lightest fields.
    const ink = _AnimeDetailScreenState._printRoom ? AppTheme.hankoWashi : AppTheme.hankoStoneHi;
    return _ClearOfSeal(
      sealTop: sealTop,
      children: [
        if (studio != null)
          _HankoLink(label: studio, semanticLabel: 'Studio, $studio', onTap: onStudio, maxWidth: width),
        for (final (i, fact) in facts.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 && studio == null ? 0 : 4),
            child: Text(
              fact,
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                color: ink,
                height: 1.3,
              ),
            ),
          ),
        if (director != null) ...[
          const SizedBox(height: 10),
          Text(
            'Directed by',
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoLabelSize,
              color: ink,
              height: 1.3,
            ),
          ),
          _HankoLink(label: director, semanticLabel: 'Director, $director', onTap: onDirector, maxWidth: width),
        ],
      ],
    );
  }
}

/// The colophon's lines, top to bottom like a start-aligned Column, except
/// that a line which would run into the seal steps right by [indent]. The
/// seal reaches 10 px past the print into the colophon's column (with its
/// keyline), so when large text or long names make the facts run long, the
/// last lines would pass under it; at 1.3× the dashed seal crossed the
/// director's name. Lines above the seal keep their full width, so the
/// usual layout doesn't change. A line counts as running into the seal
/// once it passes [sealTop] by more than [slack] (a link's 48 dp target is
/// mostly air around its text). A line whose longest word wouldn't fit the
/// narrower width stays where it was rather than break that word.
class _ClearOfSeal extends MultiChildRenderObjectWidget {
  const _ClearOfSeal({required this.sealTop, required super.children});

  final double sealTop;
  static const double indent = 18; // past the seal's 10 px, as its caption does
  static const double slack = 4;

  @override
  _RenderClearOfSeal createRenderObject(BuildContext context) => _RenderClearOfSeal(sealTop);

  @override
  void updateRenderObject(BuildContext context, _RenderClearOfSeal renderObject) {
    renderObject.sealTop = sealTop;
  }
}

class _ClearOfSealParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderClearOfSeal extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ClearOfSealParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ClearOfSealParentData> {
  _RenderClearOfSeal(this._sealTop);

  double _sealTop;
  set sealTop(double value) {
    if (value == _sealTop) return;
    _sealTop = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ClearOfSealParentData) {
      child.parentData = _ClearOfSealParentData();
    }
  }

  Size _lay(BoxConstraints constraints, {required bool dry}) {
    final full = BoxConstraints(maxWidth: constraints.maxWidth);
    final narrow = BoxConstraints(
        maxWidth: math.max(0.0, constraints.maxWidth - _ClearOfSeal.indent));
    Size sized(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    var y = 0.0;
    var width = 0.0;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ClearOfSealParentData;
      var size = sized(child, full);
      var x = 0.0;
      // Step right only if every word still fits on its own line: at large
      // text a long name ("Katsumasa") is wider than the narrower column and
      // would break mid-word, which reads worse than the seal's corner.
      if (y + size.height - _ClearOfSeal.slack > _sealTop &&
          child.getMinIntrinsicWidth(double.infinity) <= narrow.maxWidth) {
        size = sized(child, narrow);
        x = _ClearOfSeal.indent;
      }
      if (!dry) data.offset = Offset(x, y);
      y += size.height;
      width = math.max(width, x + size.width);
      child = data.nextSibling;
    }
    return constraints.constrain(Size(width, y));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _lay(constraints, dry: true);

  @override
  void performLayout() {
    size = _lay(constraints, dry: false);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      width = math.max(width, c.getMinIntrinsicWidth(double.infinity));
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      width = math.max(width, c.getMaxIntrinsicWidth(double.infinity));
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _lay(BoxConstraints(maxWidth: width), dry: true).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A name that opens its page: washi 500 with Hanko's link underline (the
/// edge colour, 3 px below), in a 48 dp tall target. Without a page to open
/// it is plain text.
class _HankoLink extends StatelessWidget {
  const _HankoLink({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    required this.maxWidth,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// The colophon's width, for Print Room's whole words (P4).
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final linked = onTap != null;
    final style = AppTheme.hankoSans(
      fontSize: AppTheme.hankoMetaSize,
      weight: FontWeight.w500,
      height: 1.3,
    ).copyWith(
      decoration: linked ? TextDecoration.underline : null,
      decorationColor: AppTheme.hankoEdge,
      decorationThickness: 1,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final text = Text(
      label,
      style: style,
      // In Print Room every word stays whole: at 1.3× "MADHOUSE" broke as
      // "MADHOUS / E" in the column beside the print (P4).
      textScaler: _AnimeDetailScreenState._printRoom
          ? _wholeWords(scaler, label, style, maxWidth)
          : scaler,
    );
    if (!linked) return Padding(padding: const EdgeInsets.only(bottom: 2), child: text);
    // Its own semantics node (container) with the InkWell's tap and focus
    // inside it (question 104, as the status word). The label used to sit
    // over excluded semantics, which dropped the InkWell's tap, so a screen
    // reader found "Studio, MAPPA" but couldn't open it. The name drawn on
    // the page is left out, under the InkWell, so it isn't read twice. The
    // transparent Material is the InkWell's own ink layer (question 138, as
    // the bell's): ink is drawn under a Material's children, and the nearest
    // Material was the Scaffold's, under the tinted field, which hid the
    // links' focus and press washes.
    return Semantics(
      container: true,
      link: true,
      label: semanticLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch, minWidth: double.infinity),
              child: Align(alignment: Alignment.centerLeft, child: text),
            ),
          ),
        ),
      ),
    );
  }
}

/// The title on the field, Shippori Mincho 24. Past two lines it splits at
/// its first ": " into a smaller subtitle (the spec's rule). The whole title
/// shows, at the default text size and at larger ones: only an extreme
/// length reaches the line limit, and fades there rather than end in "…",
/// which Shippori draws as the centred ⋯.
class _HankoTitle extends StatelessWidget {
  const _HankoTitle({required this.title});

  final String title;

  static const double _maxWidth = 280;

  /// Print Room's title (P4; DESIGN.md §9.3 rule 6, "bigger moments for the
  /// type"): Shippori at 28, in the column's whole width up to 320, the
  /// mockup's measure at 360 dp. The colon rule and the line limits follow
  /// the new size.
  static const double _printRoomSize = 28;
  static const double _printRoomMaxWidth = 320;

  /// Lines at the default text size. "As a Reincarnated Aristocrat, I'll Use
  /// My Appraisal Skill to Rise in the World Season 3" fits four exactly, so
  /// six leave two spare; the subtitle's three get one more.
  static const int _lines = 6;
  static const int _subLines = 4;

  /// [lines] at the default size, grown with the text: at 1.3× the same words
  /// need about 1.3 times the lines (it was a fixed four, and at 1.3× the
  /// title above lost "World Season 3"). The scale is read at [fontSize],
  /// since the phone may scale large text less than small.
  static int _linesAt(TextScaler scaler, double fontSize, int lines) =>
      (lines * scaler.scale(fontSize) / fontSize).ceil();

  @override
  Widget build(BuildContext context) {
    const printRoom = _AnimeDetailScreenState._printRoom;
    final style = AppTheme.hankoSerif(
        fontSize: printRoom ? _printRoomSize : AppTheme.hankoDisplaySize, height: 1.18);
    final subStyle = AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.4);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(printRoom ? _printRoomMaxWidth : _maxWidth, constraints.maxWidth);
        var main = title;
        String? sub;
        final colon = title.indexOf(': ');
        if (colon > 0) {
          final painter = TextPainter(
            text: TextSpan(text: title, style: style),
            textScaler: scaler,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: width);
          final lines = painter.computeLineMetrics().length;
          painter.dispose();
          if (lines > 2) {
            main = title.substring(0, colon);
            sub = title.substring(colon + 2).trim();
          }
        }
        return SizedBox(
          width: width,
          child: Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    main,
                    style: style,
                    maxLines: _linesAt(scaler, style.fontSize!, _lines),
                    overflow: TextOverflow.fade,
                  ),
                  if (sub != null && sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        sub,
                        maxLines: _linesAt(scaler, subStyle.fontSize!, _subLines),
                        overflow: TextOverflow.fade,
                        style: subStyle,
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
}

// ── Seasons strip (round seven) ──────────────────────────────

/// The show's seasons in order (round seven): its PREQUEL and SEQUEL chain
/// on AniList, as prints on a shelf. Shahid, 2026-11-03: "We need one anime
/// to have like seasons on it as well so the episode list we can choose
/// which season".
///
/// Each print is the season's cover with Detail's washi ring, a spine in its
/// cover's colour below it, and, on the print, "Airing" or "Upcoming". Under
/// it, the season's name (what its title adds to the titles' shared start)
/// and its episode count. The season on screen is framed in washi and
/// doesn't open; any other opens its Detail in place of this one. While the
/// walk reads further, a quiet slot waits at that end; if a read fails, the
/// slot offers another try.
class _HankoSeasons extends StatefulWidget {
  const _HankoSeasons({required this.chain, required this.onOpen, required this.onRetry});

  final SeasonChain chain;
  final ValueChanged<AnimeSeason> onOpen;
  final VoidCallback onRetry;

  static const double _printWidth = 96;
  static const double _printHeight = 136;
  static const double _gap = 12;

  /// Shown for two seasons or more; on a film or a special's page, which
  /// isn't a season itself, for the seasons of its series.
  static bool shows(SeasonChain chain) {
    final here = chain.seasons.any((s) => s.id == chain.currentId);
    return chain.seasons.length >= (here ? 2 : 1);
  }

  /// The place of the season on screen on the shelf, slots included, or -1.
  static int _hereAt(SeasonChain chain) {
    final i = chain.seasons.indexWhere((s) => s.id == chain.currentId);
    return i < 0 ? -1 : i + (chain.moreBefore ? 1 : 0);
  }

  /// What each print calls its season: what its title adds to the start the
  /// titles share ("Season 2", "Final Season Part 2"), so a long title isn't
  /// cut down to the part every season has. The first, which usually adds
  /// nothing, is "Season 1" ("1st Season" when the others count that way).
  /// Titles that share no start are shown whole.
  static List<String> _names(List<AnimeSeason> seasons) {
    final shown = [for (final s in seasons) s.titleEnglish ?? s.title];
    final romaji = [for (final s in seasons) s.title];
    // English where AniList has it; romaji when a season has no English
    // title and only the romaji titles share their start.
    final a = _sharedStart(shown), b = _sharedStart(romaji);
    final (titles, cut) = b > a ? (romaji, b) : (shown, a);
    if (seasons.length < 2 || cut < 4) return shown;
    final rest = [
      for (final t in titles) t.substring(cut).replaceFirst(RegExp(r'^[\s:\-–—~,.!]+'), '').trim(),
    ];
    final ordinal = rest.any((r) => RegExp(r'^\d+(st|nd|rd|th) season', caseSensitive: false).hasMatch(r));
    // What adds only a number ("Mob Psycho 100 II") is that season: "Season 2".
    String numbered(String r) {
      const roman = {'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10};
      final n = roman[r] ?? (RegExp(r'^\d{1,2}$').hasMatch(r) ? int.parse(r) : null);
      return n == null ? r : 'Season $n';
    }
    return [
      for (final (i, r) in rest.indexed)
        r.isNotEmpty ? numbered(r) : (i == 0 ? (ordinal ? '1st Season' : 'Season 1') : shown[i]),
    ];
  }

  /// How long a start the titles share, ending where every title breaks:
  /// at its end, a space or punctuation, never inside a word.
  static int _sharedStart(List<String> titles) {
    if (titles.isEmpty) return 0;
    final first = titles.first;
    var n = first.length;
    for (final t in titles.skip(1)) {
      var i = 0;
      while (i < n && i < t.length && t.codeUnitAt(i) == first.codeUnitAt(i)) {
        i++;
      }
      n = i;
    }
    bool breaksAt(String t, int i) => i >= t.length || RegExp(r'[\s:\-–—~,.!]').hasMatch(t[i]);
    while (n > 0 && !titles.every((t) => breaksAt(t, n))) {
      n--;
    }
    return n;
  }

  /// The line under the name: the episode count; for an airing season with
  /// no total yet, how many have aired; for one still to come, when.
  static String _count(AnimeSeason s) {
    final episodes = s.episodes;
    if (episodes != null && episodes > 0) return '$episodes ${episodes == 1 ? 'episode' : 'episodes'}';
    final next = s.nextEpisode;
    if (s.status == 'RELEASING' && next != null && next > 1) return '${next - 1} so far';
    final season = s.season;
    final year = s.year;
    return [
      if (season != null && season.isNotEmpty) '${season[0]}${season.substring(1).toLowerCase()}',
      if (year != null) '$year',
    ].join(' ');
  }

  /// "Airing" or "Upcoming", on the print.
  static String? _tag(AnimeSeason s) => switch (s.status) {
        'RELEASING' => 'Airing',
        'NOT_YET_RELEASED' => 'Upcoming',
        _ => null,
      };

  /// "3 seasons · 64 episodes", the total only when every count is known;
  /// "so far" while more may turn up.
  static String _aside(SeasonChain chain) {
    final seasons = chain.seasons;
    final more = (chain.moreBefore || chain.moreAfter) && !chain.failed;
    final counted = seasons.length == 1 ? '1 season' : '${seasons.length} seasons';
    if (more) return '$counted so far';
    if (seasons.any((s) => s.episodes == null || s.episodes! <= 0)) return counted;
    final total = seasons.fold<int>(0, (n, s) => n + s.episodes!);
    return '$counted · $total episodes';
  }

  /// The spine's colour: the cover's own, or the edge when it has none.
  /// Every show brings its colour (Print Room, question 159; Shahid,
  /// 2026-11-04: "Go ahead"), so there's no hue guard: a cover near coral
  /// keeps its colour too.
  static Color _spine(String? hex) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return AppTheme.hankoEdge;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  State<_HankoSeasons> createState() => _HankoSeasonsState();
}

class _HankoSeasonsState extends State<_HankoSeasons> {
  final ScrollController _scroll = ScrollController();

  // Set once you scroll the shelf yourself; from then on it stays put.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _place(-1);
  }

  @override
  void didUpdateWidget(_HankoSeasons oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = _HankoSeasons._hereAt(oldWidget.chain);
    if (was != _HankoSeasons._hereAt(widget.chain)) _place(was);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the season on screen in view: at first centred, when the shelf
  /// is wider than the screen; then where it was when seasons arrive before
  /// it, unless you've scrolled the shelf yourself.
  void _place(int was) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || (_scrolled && was >= 0)) return;
      final now = _HankoSeasons._hereAt(widget.chain);
      if (now < 0) return;
      final position = _scroll.position;
      const step = _HankoSeasons._printWidth + _HankoSeasons._gap;
      final target = was < 0
          ? AppTheme.hankoGutter + now * step + _HankoSeasons._printWidth / 2 - position.viewportDimension / 2
          : position.pixels + (now - was) * step;
      final clamped = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if (clamped != position.pixels) _scroll.jumpTo(clamped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chain = widget.chain;
    final names = _HankoSeasons._names(chain.seasons);
    final still = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    // Every name gets the lines the longest needs, one or two, so the counts
    // line up without a gap under one-line names.
    final nameStyle = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w600, height: 1.25);
    var nameLines = 1;
    for (final name in names) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: nameStyle),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: _HankoSeasons._printWidth);
      nameLines = math.max(nameLines, painter.computeLineMetrics().length);
      painter.dispose();
      if (nameLines == 2) break;
    }
    final nameHeight = nameLines * scaler.scale(AppTheme.hankoMetaSize) * 1.25;
    final tiles = <Widget>[
      if (chain.moreBefore) _slot(nameHeight, before: true),
      for (final (i, season) in chain.seasons.indexed)
        _arrive(
          key: ValueKey(season.id),
          order: i,
          still: still,
          child: _print(season, names[i], nameHeight, still: still),
        ),
      if (chain.moreAfter) _slot(nameHeight, before: false),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            child: _HankoSectionHead(title: 'Seasons', aside: _HankoSeasons._aside(chain)),
          ),
          // Its own layer: scrolling the shelf, a print arriving or the slot's
          // spinner repaints the shelf alone, not the page.
          RepaintBoundary(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                _scrolled = true;
                return false;
              },
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, tile) in tiles.indexed) ...[
                      if (i > 0) const SizedBox(width: _HankoSeasons._gap),
                      tile,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A print fades and rises into place once, when it first arrives, a few
  /// at a time from the left; with Remove animations on, it is simply there.
  Widget _arrive({required Key key, required int order, required bool still, required Widget child}) {
    const fade = 240;
    final delay = 45 * math.min<int>(order, 4);
    return TweenAnimationBuilder<double>(
      key: key,
      tween: Tween(begin: still ? 1.0 : 0.0, end: 1.0),
      duration: Duration(milliseconds: still ? 0 : fade + delay),
      curve: Interval(delay / (fade + delay), 1, curve: Curves.easeOut),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }

  Widget _print(AnimeSeason season, String name, double nameHeight, {required bool still}) {
    final here = season.id == widget.chain.currentId;
    final count = _HankoSeasons._count(season);
    final tag = _HankoSeasons._tag(season);
    final cover = season.coverUrl;
    final year = season.year;
    // Read as one line: "Season 2, 12 episodes, 2017, airing".
    final label = [
      name,
      if (count.isNotEmpty) count,
      if (year != null && !count.contains('$year')) '$year',
      if (tag != null) tag.toLowerCase(),
    ].join(', ');
    final art = Container(
      width: _HankoSeasons._printWidth,
      height: _HankoSeasons._printHeight,
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        // The print's 1 px washi ring, as Detail's own print.
        boxShadow: [BoxShadow(color: AppTheme.hankoWashi.withValues(alpha: 0.12), spreadRadius: 1)],
      ),
      // The season on screen, framed in washi, as the tab you're on is
      // underlined in it.
      foregroundDecoration: here
          ? BoxDecoration(
              border: Border.all(color: AppTheme.hankoWashi, width: 2),
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                fadeInDuration: still ? Duration.zero : const Duration(milliseconds: 200),
                fadeOutDuration: Duration.zero,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            if (tag != null)
              Positioned(
                left: 6,
                top: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.hankoSumi.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Text(
                      tag,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoDataSmallSize,
                        weight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final visual = SizedBox(
      width: _HankoSeasons._printWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          art,
          // The spine: the cover's own colour, a little apart from it.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              height: 2,
              width: double.infinity,
              child: ColoredBox(color: _HankoSeasons._spine(season.coverColor)),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: nameHeight,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                weight: here ? FontWeight.w600 : FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            count,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoLabelSize,
              color: AppTheme.hankoStone,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
    // Its own semantics node (container) with the InkWell's tap and focus
    // inside it (R5B's pattern). The season on screen is marked selected and
    // has no tap. The InkWell lies over the print on its own transparent
    // Material, since ink is drawn under a Material's children and the cover
    // would hide it.
    return Semantics(
      container: true,
      button: !here,
      selected: here,
      label: label,
      hint: here ? null : 'Opens this season',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: visual),
          if (!here)
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => widget.onOpen(season),
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                  hoverColor: AppTheme.hankoPressWash,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The slot at an end where more seasons may turn up: a quiet spinner
  /// while the walk reads, or, after a failed read, "Try again".
  Widget _slot(double nameHeight, {required bool before}) {
    final failed = widget.chain.failed;
    final box = Container(
      width: _HankoSeasons._printWidth,
      height: _HankoSeasons._printHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi2,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        border: Border.all(color: AppTheme.hankoHairline),
      ),
      child: failed
          ? const Icon(Icons.refresh_sharp, size: 20, color: AppTheme.hankoStone)
          // Its own layer, so its turning repaints only itself.
          : const RepaintBoundary(
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.hankoStone),
              ),
            ),
    );
    final visual = SizedBox(
      width: _HankoSeasons._printWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          box,
          SizedBox(height: 13 + nameHeight),
          Text(
            failed ? 'Try again' : 'Looking…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: failed
                ? AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, weight: FontWeight.w500, height: 1.35)
                    .copyWith(decoration: TextDecoration.underline, decorationColor: AppTheme.hankoEdge)
                : AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone, height: 1.35),
          ),
        ],
      ),
    );
    final where = before ? 'earlier' : 'later';
    if (!failed) {
      return Semantics(
        key: ValueKey('slot $where'),
        container: true,
        label: 'Looking for $where seasons',
        child: ExcludeSemantics(child: visual),
      );
    }
    return Semantics(
      key: ValueKey('slot $where'),
      container: true,
      button: true,
      label: '${before ? 'Earlier' : 'Later'} seasons didn’t load. Try again',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: visual),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onRetry,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────
class _HeroPanel extends StatelessWidget {
  final Anime anime;
  final List<String> characterImages;
  final List<String> galleryImages;
  const _HeroPanel({required this.anime, this.characterImages = const [], this.galleryImages = const []});

  @override
  Widget build(BuildContext context) {
    final url = anime.imageUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF121110)),

        Positioned.fill(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 60, 6, 16),
                  child: GestureDetector(
                    onTap: () {
                      if (url == null) return;
                      final imgs = galleryImages.isNotEmpty ? galleryImages : [url!];
                      _openGallery(context, imgs, 0);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: url != null
                          ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: AppTheme.surfaceMid))
                          : Container(color: AppTheme.surfaceMid),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 60, 16, 16),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(fit: StackFit.expand, children: [
                            if (url != null) CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, color: Colors.black.withValues(alpha: 0.3), colorBlendMode: BlendMode.darken, errorWidget: (_, _, _) => Container(color: AppTheme.surfaceMid))
                            else Container(color: AppTheme.surfaceMid),
                            if (anime.status == 'RELEASING')
                              Positioned(top: 8, right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(6)),
                                  child: Text('OUT NOW', style: AppTheme.mono(fontSize: 8, color: Colors.white, weight: FontWeight.w700, letterSpacing: 0.5)),
                                ),
                              ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppTheme.primaryDim, AppTheme.surface])),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  anime.genres.isNotEmpty ? '"${anime.genres.first}"' : '"Walk through\nevery series."',
                                  style: AppTheme.serif(fontSize: 13, height: 1.4).copyWith(fontStyle: FontStyle.italic),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(bottom: 0, left: 0, right: 0, height: 80,
          child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppTheme.background]))),
        ),
      ],
    );
  }
}


// ── Tab Bar Delegate ─────────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  const _TabBarDelegate(this.child, {this.height = 52});

  @override double get minExtent => height;
  @override double get maxExtent => height;

  @override
  Widget build(_, _, _) => child;

  @override
  bool shouldRebuild(_TabBarDelegate old) => true;
}

// ── Overview Tab ─────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  // ── Stat tiles are hidden ──────────────────────────────────
  // "MEMBERS watching" is the average score as a percentage, "TRENDING vs
  // last wk" a fixed +18% for anything airing, and "EPISODES this season"
  // the total, which the score row and INFORMATION already show. The row is
  // kept intact below. Don't set this to true until every tile shows a real
  // number.
  static const bool _showStatTiles = false;

  // ── The Information block is hidden (H3 i) ─────────────────
  // Its studio, episodes, format and season now sit beside the print in the
  // colophon, the studio as a link, so Overview no longer repeats them. The
  // block is kept intact below.
  static const bool _showInformation = false;

  // ── Watch along (arcs redesign, 2026-11-14) ────────────────
  // A row under Discussion into this show's arcs (watch-alongs), shown only
  // once Arcs is open (ArcsScreen.open). Off gives back Overview as it was.
  static const bool _watchAlong = true;

  /// AniList's official streaming links for the show (`externalLinks` of
  /// type STREAMING, from Stage 1c's request), one per site, the first kept
  /// (question 113): AniList can list a site more than once (two Crunchyroll
  /// pages, say), and Where to watch named it twice.
  List<({String site, String url})> get _streams {
    final sites = <String>{};
    return [
      for (final link in staffData?['externalLinks'] as List? ?? const [])
        if (link is Map &&
            link['type'] == 'STREAMING' &&
            link['site'] is String &&
            link['url'] is String &&
            sites.add((link['site'] as String).trim().toLowerCase()))
          (site: link['site'] as String, url: link['url'] as String),
    ];
  }

  /// The cast for Overview's portraits (Print Room, P4): the staff answer's
  /// characters in AniList's order, main roles first, up to eight, as the
  /// Cast tab lists them.
  List<({String name, String? image})> get _cast {
    final out = <({String name, String? image})>[];
    for (final e in staffData?['characters']?['edges'] as List? ?? const []) {
      final node = e is Map ? e['node'] : null;
      if (node is! Map) continue;
      final name = node['name']?['full'];
      if (name is! String || name.trim().isEmpty) continue;
      out.add((name: name.trim(), image: node['image']?['medium'] as String?));
      if (out.length == 8) break;
    }
    return out;
  }

  final Anime anime;
  final Map<String, dynamic>? staffData;
  final bool isLoadingStaff;
  final String Function(String) cleanDescription;
  final int? currentEpisode;
  final DateTime? nextAiringAt;
  final int? nextEpisodeNum;
  final ValueListenable<Duration> timeUntilAiring;
  final List<String> characterImages;

  /// AniList's recommendations, the ones the You May Like tab shows: on
  /// Overview as prints on mats (Print Room, P4).
  final List<Anime> relatedAnime;

  const _OverviewTab({
    required this.anime,
    required this.staffData,
    required this.isLoadingStaff,
    required this.cleanDescription,
    required this.currentEpisode,
    this.nextAiringAt,
    this.nextEpisodeNum,
    required this.timeUntilAiring,
    this.characterImages = const [],
    required this.relatedAnime,
  });

  @override
  Widget build(BuildContext context) {
    final studio = (staffData?['studios']?['nodes'] as List?)?.isNotEmpty == true
        ? (staffData!['studios']['nodes'] as List)[0]['name'] as String?
        : null;
    final cast = _AnimeDetailScreenState._printRoom ? _cast : const <({String name, String? image})>[];
    final mayLike = _AnimeDetailScreenState._printRoom ? relatedAnime : const <Anime>[];

    // The sections carry keys (question 115), so the list matches them by
    // key, not by place. The countdown card arrives with the staff answer
    // at the top, and Where to watch above the discussion row; unkeyed,
    // every section after them met a different widget at its old place and
    // was built again from nothing, text layout and all.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // Up Next — live countdown of the real next airing episode
        if (nextAiringAt != null && nextEpisodeNum != null) ...[
          _NextEpisodeCountdown(
            animeId:       anime.id,
            episode:       nextEpisodeNum!,
            airingAt:      nextAiringAt!,
            timeUntil:     timeUntilAiring,
          ),
          const SizedBox(height: 24),
        ],

        const AnilistSavedNote(key: ValueKey('saved note'), padding: EdgeInsets.only(bottom: 12)),

        // Synopsis. Hanko: a Mincho head, no coral bar and no tracked-caps
        // eyebrow under it.
        if (anime.description != null) ...[
          const _HankoSectionHead(key: ValueKey('synopsis head'), title: 'Synopsis', aside: null),
          _SynopsisText(key: const ValueKey('synopsis'), text: cleanDescription(anime.description!)),
          const SizedBox(height: 28),
        ],

        // Print Room (P4; DESIGN.md §9.5, frame 04): after the synopsis, as
        // the mockup has them, the cast as round portraits and You may like
        // as prints on mats.
        if (cast.isNotEmpty)
          _NextFrame(
            key: const ValueKey('cast'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HankoSectionHead(title: 'Cast', aside: null),
                _CastPortraits(cast: cast),
                const SizedBox(height: 28),
              ],
            ),
          ),
        if (mayLike.isNotEmpty)
          _NextFrame(
            key: const ValueKey('may like'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HankoSectionHead(title: 'You may like', aside: null),
                _MayLike(anime: mayLike),
                const SizedBox(height: 28),
              ],
            ),
          ),

        // Stat tiles (hidden, see _showStatTiles)
        if (_showStatTiles) ...[
          Row(children: [
            Expanded(child: _StatBox(value: anime.averageScore != null ? '${(anime.averageScore! / 10 * 10).round()}%' : '—', label: 'MEMBERS\nwatching', dark: true)),
            const SizedBox(width: 8),
            Expanded(child: _StatBox(value: anime.episodes != null ? '${anime.episodes}' : '—', label: 'EPISODES\nthis season')),
            const SizedBox(width: 8),
            Expanded(child: _StatBox(value: anime.status == 'RELEASING' ? '+18%' : '—', label: 'TRENDING\nvs last wk', accent: true)),
          ]),
          const SizedBox(height: 28),
        ],

        // Genres, once, as one line (H3 i): today's header showed three as
        // chips and this tab all of them again.
        if (anime.genres.isNotEmpty) ...[
          Text('Genres', key: const ValueKey('genres head'), style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
          const SizedBox(height: 6),
          Text(anime.genres.join(', '), key: const ValueKey('genres'), style: AppTheme.hankoSans(height: 1.5)),
          const SizedBox(height: 28),
        ],

        // Information (hidden, see _showInformation)
        if (_showInformation) ...[
        Text('INFORMATION', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
          child: Column(children: [
            MouseRegion(
              cursor: studio != null ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: studio != null ? () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => StudioDetailScreen(studioName: studio))) : null,
                child: Row(children: [
                  Text('STUDIO', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.8)),
                  const Spacer(),
                  Text(studio ?? '—', style: AppTheme.sans(fontSize: 14, weight: FontWeight.w500,
                      color: studio != null ? AppTheme.primary : AppTheme.textPrimary)),
                  if (studio != null) ...[const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppTheme.primary)],
                ]),
              ),
            ),
            const Divider(color: AppTheme.border, height: 20),
            _InfoRow('EPISODES', anime.episodes?.toString() ?? '—'),
            const Divider(color: AppTheme.border, height: 20),
            _InfoRow('FORMAT', anime.format?.replaceAll('_', ' ') ?? '—'),
            const Divider(color: AppTheme.border, height: 20),
            _InfoRow('SEASON', [
              if (anime.season != null) '${anime.season![0]}${anime.season!.substring(1).toLowerCase()}',
              if (anime.seasonYear != null) anime.seasonYear.toString(),
            ].join(' ')),
          ]),
        ),
        const SizedBox(height: 28),
        ],

        // Characters are shown in the Cast tab (AniList medium images are too low-res for a gallery strip)

        // Trailer, under a Mincho head like Overview's other sections.
        if (anime.trailerUrl != null) ...[
          const _HankoSectionHead(key: ValueKey('trailer head'), title: 'Trailer', aside: null),
          TrailerButton(key: const ValueKey('trailer'), trailerUrl: anime.trailerUrl!),
          const SizedBox(height: 28),
        ],

        // Where to watch (Stage 1c): the official streaming services AniList
        // lists, for every show that has them. Today's play button offered two
        // search links, and only for shows with a trailer. The links carry no
        // region, so nothing here promises it streams where you are.
        if (_streams.isNotEmpty) ...[
          const _HankoSectionHead(key: ValueKey('watch head'), title: 'Where to watch', aside: 'Official links on AniList'),
          _HankoWatchLinks(key: const ValueKey('watch links'), links: _streams),
          const SizedBox(height: 28),
        ],

        // ── Discussion ──────────────────────────────────────
        // A plain 48 dp row in Hanko: no card, no coral arrow.
        InkWell(
          key: const ValueKey('discussion'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EpisodeDiscussionScreen(anime: anime, episodeNumber: 0))),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Row(children: [
              const Icon(Icons.forum_outlined, size: 20, color: AppTheme.hankoWashi),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Join the discussion',
                    style: AppTheme.hankoSans(fontSize: 15, weight: FontWeight.w500)),
              ),
              const Icon(Icons.chevron_right_sharp, size: 20, color: AppTheme.hankoStone),
            ]),
          ),
        ),

        // ── Watch along (arcs redesign) ─────────────────────
        // The same quiet row: this show's arcs, or start one for it.
        if (ArcsScreen.open && _watchAlong)
          InkWell(
            key: const ValueKey('watch along'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ArcsIndexScreen(
                        show: ArcShow(
                            id: anime.id,
                            title: anime.titleEnglish ?? anime.title,
                            cover: anime.imageUrl,
                            episodes: anime.episodes)))),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
              child: Row(children: [
                const Icon(Icons.groups_2_outlined, size: 20, color: AppTheme.hankoWashi),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Watch along with others',
                      style: AppTheme.hankoSans(fontSize: 15, weight: FontWeight.w500)),
                ),
                const Icon(Icons.chevron_right_sharp, size: 20, color: AppTheme.hankoStone),
              ]),
            ),
          ),
      ],
    );
  }
}

/// A section's head in Hanko: Shippori Mincho 16, with a note on the right.
class _HankoSectionHead extends StatelessWidget {
  const _HankoSectionHead({super.key, required this.title, required this.aside});

  final String title;
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final aside = this.aside;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppTheme.hankoSerif(height: 1.3)),
            ),
          ),
          if (aside != null)
            Text(
              aside,
              style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone, height: 1.3),
            ),
        ],
      ),
    );
  }
}

/// The streaming links as plain rows, two to a line: Hanko keeps pills for
/// controls. Each opens outside the app.
class _HankoWatchLinks extends StatelessWidget {
  const _HankoWatchLinks({super.key, required this.links});

  final List<({String site, String url})> links;

  static Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // Both attempts caught: an uncaught async error is a fatal Crashlytics
    // report (CLAUDE.md, Gotchas).
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          children: [
            for (final link in links)
              SizedBox(
                width: cell,
                // Its own semantics node (container) with the InkWell's tap
                // and focus inside it (question 104, as the status word). The
                // label used to sit over excluded semantics, which dropped the
                // InkWell's tap, so a screen reader found "Watch on
                // Crunchyroll" but couldn't open it.
                child: Semantics(
                  container: true,
                  link: true,
                  label: 'Watch on ${link.site}',
                  hint: 'Opens outside Hanj',
                  child: InkWell(
                    onTap: () => _open(link.url),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: AppTheme.hankoPressWash,
                    child: ExcludeSemantics(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                link.site,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.hankoSans(weight: FontWeight.w500, height: 1.2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.open_in_new_sharp, size: 16, color: AppTheme.hankoStone),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Builds [child] a frame after it first appears (Print Room, P4).
/// Overview's two strips come with the staff answer, in a frame that already
/// rebuilds the header and the tab; on the phone that frame took about twice
/// as long with them in it. They sit below the first screen when the answer
/// lands, so a frame later looks the same and the work is split in two.
class _NextFrame extends StatefulWidget {
  const _NextFrame({super.key, required this.child});

  final Widget child;

  @override
  State<_NextFrame> createState() => _NextFrameState();
}

class _NextFrameState extends State<_NextFrame> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) => _ready ? widget.child : const SizedBox.shrink();
}

/// The cast on Overview as round portraits (Print Room, P4; DESIGN.md §9.5,
/// frame 04): people are round, things square. The staff answer's
/// characters, up to eight, in a strip that scrolls sideways: 66 dp circles
/// 14 apart, the face kept in the circle (AniList's character art is a
/// portrait with the face near its top; the mockup's 50% 18%), and the name
/// under it in Jost 500 12 washi, two lines (three at 1.3×), fading past
/// that. At 360 dp four show and a fifth peeks in. They're people, not
/// actions: the app has no character page, and the Cast tab, one tap away,
/// has their voices. The strip starts at the gutter and runs out to the
/// page's edges as it scrolls.
class _CastPortraits extends StatelessWidget {
  const _CastPortraits({required this.cast});

  final List<({String name, String? image})> cast;

  static const double _size = 66;
  static const double _gap = 14;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppTheme.hankoSans(
        fontSize: AppTheme.hankoLabelSize, weight: FontWeight.w500, height: 1.25);
    // A limit counted in lines grows with the text (P1's finding).
    final lines = math.max(2, (2 * scaler.scale(AppTheme.hankoLabelSize) / AppTheme.hankoLabelSize).round());
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, person) in cast.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            Semantics(
              container: true,
              label: person.name,
              child: ExcludeSemantics(
                child: SizedBox(
                  width: _size,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: _size,
                          child: ColoredBox(
                            color: AppTheme.hankoSumi3,
                            child: _portrait(person),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      _FadeLines(person.name, style: style, maxLines: lines, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _portrait(({String name, String? image}) person) {
    // No art, or art that won't load: the name's first letter, as the Cast
    // tab's avatars do.
    final initial = Center(
      child: Text(
        person.name.characters.first.toUpperCase(),
        style: AppTheme.hankoSerif(fontSize: 22, color: AppTheme.hankoStone),
      ),
    );
    final url = person.image;
    if (url == null || url.isEmpty) return initial;
    Widget art(String src, Widget Function() fallback) => CachedNetworkImage(
          imageUrl: src,
          fit: BoxFit.cover,
          alignment: const Alignment(0, -0.64),
          errorWidget: (_, _, _) => fallback(),
        );
    final large = _largeArt(url);
    if (large == null) return art(url, () => initial);
    return art(large, () => art(url, () => initial));
  }

  /// The large character art (about 230 px wide) for AniList's `medium`
  /// (about 100), which looked soft filling 66 dp on the phone (question
  /// P4-2; Shahid, 2026-11-05: "Go with your recommendations"). It's the
  /// image server's naming (`/character/medium/` becomes
  /// `/character/large/`), as question 167 does for hero covers, not a
  /// documented API: if it fails, the medium art shows, and then the
  /// initial. Other hosts come back null.
  static String? _largeArt(String url) {
    const medium = '/character/medium/';
    return url.contains(medium) ? url.replaceFirst(medium, '/character/large/') : null;
  }
}

/// You may like on Overview as prints on mats (Print Room, P4; DESIGN.md
/// §9.5, frame 04): AniList's recommendations, the ones the You May Like tab
/// shows, in a strip that scrolls sideways. Each is P1's HankoPrint at
/// 92 × 130 (the whole cover) with its small shadow, on a mat of its own
/// colour (AppTheme.hankoMatPad), 104 wide and 12 apart, with its title
/// under it in Shippori 14 washi, three lines (four at 1.3×), fading past
/// that. Each opens its own page.
class _MayLike extends StatelessWidget {
  const _MayLike({required this.anime});

  final List<Anime> anime;

  static const double _printWidth = 92;
  static const double _printHeight = 130;
  static const double _gap = 12;
  static const double _titleSize = AppTheme.hankoBodySize;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final lines = math.max(3, (3 * scaler.scale(_titleSize) / _titleSize).round());
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, show) in anime.indexed) ...[
            if (i > 0) const SizedBox(width: _gap),
            _MayLikePrint(key: ValueKey(show.id), anime: show, lines: lines),
          ],
        ],
      ),
    );
  }
}

/// One of You may like's prints (P4). Recommendations carry no AniList
/// colour, so its mat reads the cover's own (HankoCoverColour, from the
/// cover it shows, as Home's shelf does): sumi 2 until it's read, then
/// fading into it in 240 ms (at once with Remove animations), and sumi 2 for
/// good on a grey cover, so the strip keeps one rhythm of prints on mats.
/// One button named by the title, with the InkWell's tap and keyboard focus
/// in its own node and the art left out of the tree (question 119's
/// pattern). The InkWell's own washes would be drawn under the art, so they
/// are drawn over the mat instead, as Home's shelf does: the 8% press wash
/// while pressed or hovered, and a 2 px washi outline just outside the mat
/// for keyboard focus.
class _MayLikePrint extends StatefulWidget {
  const _MayLikePrint({super.key, required this.anime, required this.lines});

  final Anime anime;
  final int lines;

  @override
  State<_MayLikePrint> createState() => _MayLikePrintState();
}

class _MayLikePrintState extends State<_MayLikePrint> {
  Color? _colour;
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_MayLikePrint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anime.imageUrl != widget.anime.imageUrl) _read();
  }

  /// HankoCoverColour never throws (Crashlytics reports an unhandled async
  /// error as fatal), and shares the cover's own download.
  void _read() {
    final url = widget.anime.imageUrl;
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
      if (!mounted || widget.anime.imageUrl != url) return;
      setState(() => _colour = colour);
    });
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.anime;
    final title = show.titleEnglish ?? show.title;
    final still = MediaQuery.disableAnimationsOf(context);
    final print = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: AppTheme.hankoField(_colour) ?? AppTheme.hankoSumi2),
      duration: still ? Duration.zero : const Duration(milliseconds: 240),
      builder: (context, mat, _) => HankoPrint(
        url: show.imageUrl,
        width: _MayLike._printWidth,
        height: _MayLike._printHeight,
        mat: mat,
      ),
    );
    return SizedBox(
      width: _MayLike._printWidth + 2 * AppTheme.hankoMatPad,
      child: Semantics(
        container: true,
        button: true,
        label: title,
        hint: 'Opens its page',
        child: InkWell(
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: show))),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    color: _pressed || _hovered ? AppTheme.hankoPressWash : null,
                    border: _focused
                        ? Border.all(
                            color: AppTheme.hankoWashi,
                            width: 2,
                            strokeAlign: BorderSide.strokeAlignOutside)
                        : null,
                    borderRadius: const BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
                  ),
                  child: print,
                ),
                const SizedBox(height: 8),
                _FadeLines(
                  title,
                  style: AppTheme.hankoSerif(fontSize: _MayLike._titleSize, height: 1.25),
                  maxLines: widget.lines,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A text scaler that keeps every word of [text] whole within [maxWidth]
/// (Print Room, P4). Flutter breaks a word wider than its line between its
/// letters: at 1.3× text the colophon read "MADHOUS / E" and You may like
/// "Evergarde / n". So when the widest word won't fit, [text] is set just
/// small enough that it does, never below 80% of the reader's own size;
/// otherwise [scaler] is returned as it is.
TextScaler _wholeWords(TextScaler scaler, String text, TextStyle style, double maxWidth) {
  if (!maxWidth.isFinite || maxWidth <= 0) return scaler;
  // One layout: a paragraph's minimum intrinsic width is its widest word.
  // (Measured on the phone: a layout per word cost the frame the staff
  // answer lands in about 50 of them.)
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: scaler,
    textDirection: TextDirection.ltr,
  )..layout();
  final widest = painter.minIntrinsicWidth;
  painter.dispose();
  return _fitWidest(scaler, style, widest, maxWidth) ?? scaler;
}

/// The scaler that brings a text whose widest word is [widest] (at
/// [scaler]) within [maxWidth], never below 80% of the reader's own size,
/// or null when it fits already (_wholeWords).
TextScaler? _fitWidest(TextScaler scaler, TextStyle style, double widest, double maxWidth) {
  if (!maxWidth.isFinite || maxWidth <= 0 || widest <= maxWidth) return null;
  final size = style.fontSize ?? AppTheme.hankoBodySize;
  final factor = scaler.scale(size) / size;
  return TextScaler.linear(math.max(0.8 * factor, factor * maxWidth / widest * 0.995));
}

/// Words on up to [maxLines] lines whose last line fades out at its end when
/// they run longer, instead of an ellipsis: Shippori draws "…" as the
/// centred Japanese ⋯ (AppTheme.hankoSerif). Flutter's own TextOverflow.fade
/// on a multi-line Text fades the bottom half of the last line instead, so
/// the words are split after their last full line and that line is set on
/// its own, one line with TextOverflow.fade. Home's _FadeTitle (P2), for
/// Detail's strips (P4).
class _FadeLines extends StatelessWidget {
  const _FadeLines(this.text, {required this.style, required this.maxLines, this.textAlign});

  final String text;
  final TextStyle style;
  final int maxLines;

  /// A cut last line is always as wide as the box, so it starts at the left
  /// edge and fades at the right whatever the alignment.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every word whole: a name wider than the box is set a little
        // smaller rather than broken between its letters. Measured on a
        // layout of its own with no width: in the box's layout a word too
        // wide is already broken, and that layout reports its pieces (seen
        // on the web at 1.3×, "Evergarde / n").
        final scaler = _wholeWords(MediaQuery.textScalerOf(context), text, style, constraints.maxWidth);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: maxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        final lines = overflows ? painter.computeLineMetrics() : null;
        // The last line's first character, found by its position on that
        // line (P2 found getLineBoundary answers with the line before at a
        // soft-wrapped line's first offset).
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
              textScaler: scaler,
              textAlign: textAlign,
              maxLines: maxLines,
              softWrap: maxLines > 1,
              overflow: TextOverflow.fade);
        }
        return Column(
          crossAxisAlignment:
              textAlign == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text.substring(0, lastStart).trimRight(),
                style: style, textScaler: scaler, textAlign: textAlign, maxLines: maxLines - 1),
            Text(text.substring(lastStart).trimLeft(),
                style: style, textScaler: scaler, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
          ],
        );
      },
    );
  }
}

// ── Episodes Tab ─────────────────────────────────────────────
class _EpisodesTab extends StatelessWidget {
  final Anime anime;
  final int? currentEpisode;
  const _EpisodesTab({required this.anime, required this.currentEpisode});

  @override
  Widget build(BuildContext context) {
    final total   = anime.episodes;
    final watched = currentEpisode ?? 0;
    // No count: say so instead of inventing 12 rows. The copy gives no
    // reason, since AniList having none isn't the only way to get here: a
    // list-entry stub that hasn't refreshed (or can't) carries a null too.
    if (total == null || total <= 0) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.format_list_numbered_rounded,
                color: AppTheme.textMuted.withValues(alpha: 0.5), size: 56),
            const SizedBox(height: 16),
            Text('No episode count yet',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: total,
      itemBuilder: (_, i) {
        final ep = i + 1;
        final isWatched = ep <= watched;
        // Hanko: a plain row per episode, no card and no green; watched ones
        // carry a check and the word, so it never rests on colour.
        return SizedBox(
          height: AppTheme.hankoTouch,
          child: Row(children: [
            SizedBox(
              width: 32,
              child: isWatched
                  ? const Icon(Icons.check_sharp, color: AppTheme.hankoWashi, size: 18)
                  : Text('$ep', style: AppTheme.hankoSans(fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone, tabular: true)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Episode $ep', style: AppTheme.hankoSans(weight: FontWeight.w500))),
            if (isWatched)
              Text('Watched', style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
          ]),
        );
      },
    );
  }
}

// ── Cast Tab ─────────────────────────────────────────────────
class _CastTab extends StatelessWidget {
  final Map<String, dynamic>? staffData;
  final bool isLoading;
  const _CastTab({required this.staffData, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.hankoWashi, strokeWidth: 1.5));
    final characters = staffData?['characters']?['edges'] as List? ?? [];
    final staff      = staffData?['staff']?['edges'] as List? ?? [];

    // Visible empty state so the tab is never just blank.
    if (characters.isEmpty && staff.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Icons.people_outline_rounded,
                color: AppTheme.textMuted.withValues(alpha: 0.5), size: 56),
            const SizedBox(height: 16),
            Text('Cast information unavailable',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            // Names no cause the app can't verify (the SAVED DATA report's
            // copy rule): it was "check your connection".
            Text(
              staffData == null
                  ? 'Couldn\'t load the cast just now.'
                  : 'No cast data for this title.',
              style: AppTheme.sans(fontSize: 12, color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (characters.isNotEmpty) ...[
          const _HankoSectionHead(title: 'Cast and voices', aside: null),
          for (final e in characters.take(8)) ...[_CastRow(edge: e as Map<String, dynamic>), const SizedBox(height: 4)],
          const SizedBox(height: 24),
        ],
        if (staff.isNotEmpty) ...[
          const _HankoSectionHead(title: 'Staff', aside: null),
          for (final e in staff.take(8)) ...[_StaffRow(edge: e as Map<String, dynamic>), const SizedBox(height: 4)],
        ],
      ],
    );
  }
}

class _CastRow extends StatelessWidget {
  final Map<String, dynamic> edge;
  const _CastRow({required this.edge});

  @override
  Widget build(BuildContext context) {
    final char = edge['node'] as Map?;
    final vas  = edge['voiceActors'] as List? ?? [];
    final va   = vas.isNotEmpty ? vas[0] as Map : null;
    final vaId   = va?['id'] as int?;
    final vaName = va?['name']?['full'] as String? ?? '';
    // Hanko: a plain row, no card; the voice actor's name is a link in
    // washi with the edge underline, not coral.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        _Avatar(url: char?['image']?['medium'] as String?, name: char?['name']?['full'] as String? ?? '?'),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(char?['name']?['full'] as String? ?? '—', style: AppTheme.hankoSans(weight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Character', style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
        ])),
        if (va != null) ...[
          const SizedBox(width: 8),
          MouseRegion(
            cursor: vaId != null ? SystemMouseCursors.click : MouseCursor.defer,
            // The voice actor: a link to their page, as its own semantics
            // node with the InkWell's tap and focus inside it (question 139,
            // R5B's pattern, as the header's links): with a GestureDetector
            // the keyboard couldn't reach it. Without a page it is a name
            // with no tap. The words and the face are left out of the tree,
            // since the label says them; the Material is the ink's layer.
            child: Semantics(
              container: true,
              link: vaId != null,
              label: 'Voice actor, ${vaName.isNotEmpty ? vaName : 'unknown'}',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: vaId != null ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => StaffDetailScreen(staffId: vaId, staffName: vaName))) : null,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                  child: ExcludeSemantics(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                          Text(vaName.isNotEmpty ? vaName : '—',
                              style: AppTheme.hankoSans(fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w500).copyWith(
                                decoration: vaId != null ? TextDecoration.underline : null,
                                decorationColor: AppTheme.hankoEdge,
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('Voice', style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
                        ]),
                        const SizedBox(width: 8),
                        _Avatar(url: va['image']?['medium'] as String?, name: vaName),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _StaffRow extends StatelessWidget {
  final Map<String, dynamic> edge;
  const _StaffRow({required this.edge});

  @override
  Widget build(BuildContext context) {
    final node = edge['node'] as Map?;
    final role = edge['role'] as String? ?? '—';
    // Its own semantics node (container), named by the name and role, with
    // the InkWell's tap and focus inside it (question 139, R5B's pattern):
    // with a GestureDetector the keyboard couldn't reach it. The row's words
    // and face are left out, since the label says them; the Material is the
    // ink's layer.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        container: true,
        button: true,
        label: '${node?['name']?['full'] as String? ?? 'Unknown'}, $role',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () { final id = node?['id'] as int?; final name = node?['name']?['full'] as String? ?? ''; if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => StaffDetailScreen(staffId: id, staffName: name))); },
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            child: ExcludeSemantics(
              // Hanko: a plain row, no card.
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.transparent,
                child: Row(children: [
                  _Avatar(url: node?['image']?['medium'] as String?, name: node?['name']?['full'] as String? ?? '?'),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(node?['name']?['full'] as String? ?? '—', style: AppTheme.hankoSans(weight: FontWeight.w500)),
                    Text(role, style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
                  ])),
                  const Icon(Icons.chevron_right_sharp, color: AppTheme.hankoStone, size: 20),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(width: 40, height: 40,
        child: url != null
            ? CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover, errorWidget: (_, _, _) => _fb())
            : _fb(),
      ),
    );
  }

  Widget _fb() => Container(color: AppTheme.surfaceMid, child: Center(child: Text(name.isNotEmpty ? name[0] : '?', style: AppTheme.sans(fontSize: 14, weight: FontWeight.w700))));
}

// ── Related Tab ──────────────────────────────────────────────
class _RelatedTab extends StatelessWidget {
  final List<Anime> anime;
  final bool isLoading;

  /// The staff request failed, so there's nothing to say about whether the
  /// show has recommendations.
  final bool failed;
  const _RelatedTab({required this.anime, required this.isLoading, required this.failed});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.hankoWashi, strokeWidth: 1.5));
    if (anime.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            failed ? 'Recommendations didn\'t load just now.' : 'No recommendations yet.',
            textAlign: TextAlign.center,
            style: AppTheme.hankoSans(color: AppTheme.hankoStone),
          ),
        ),
      );
    }
    // Hanko: AniList users' recommendations (Stage 1c), as 2 px posters up
    // to 120 px wide, three across on a phone; the note says whose they are.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recommended by AniList users',
              style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 120, childAspectRatio: 0.52, crossAxisSpacing: 12, mainAxisSpacing: 16),
            itemCount: anime.length,
            itemBuilder: (_, i) => _RelatedCard(anime: anime[i]),
          ),
        ],
      ),
    );
  }
}

class _RelatedCard extends StatefulWidget {
  final Anime anime;
  const _RelatedCard({required this.anime});

  @override
  State<_RelatedCard> createState() => _RelatedCardState();
}

class _RelatedCardState extends State<_RelatedCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: widget.anime))),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_hovered ? 1.03 : 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hanko: a 2 px poster and the title on up to two lines; the
              // 9 px genre caps go.
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                child: widget.anime.imageUrl != null
                    ? CachedNetworkImage(imageUrl: widget.anime.imageUrl!, fit: BoxFit.cover, width: double.infinity, errorWidget: (_, _, _) => Container(color: AppTheme.hankoSumi3))
                    : Container(color: AppTheme.hankoSumi3),
              )),
              const SizedBox(height: 6),
              // Two lines kept for every title, so the posters line up
              // whatever their titles' lengths.
              SizedBox(
                height: 2 * MediaQuery.textScalerOf(context).scale(AppTheme.hankoLabelSize) * 1.25,
                child: Text(widget.anime.titleEnglish ?? widget.anime.title,
                    style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, weight: FontWeight.w500, height: 1.25),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small Widgets ────────────────────────────────────────────
class _StatusTile extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _StatusTile({required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? color : color.withValues(alpha: 0.3)),
          ),
          child: Text(label, textAlign: TextAlign.center, style: AppTheme.sans(fontSize: 14, weight: FontWeight.w600, color: selected ? Colors.white : color)),
        ),
      ),
    );
  }
}

// ── Episode input dialog — delayed focus for a smooth keyboard entrance ──
class _EpisodeInputDialog extends StatefulWidget {
  final int? total;
  final int initial;
  final Future<void> Function(int clamped) onSave;

  const _EpisodeInputDialog({
    required this.total,
    required this.initial,
    required this.onSave,
  });

  @override
  State<_EpisodeInputDialog> createState() => _EpisodeInputDialogState();
}

class _EpisodeInputDialogState extends State<_EpisodeInputDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.toString());
    // Let the dialog's entrance animation finish first, THEN raise the
    // keyboard — so the two animations play in sequence, not on top of
    // each other (which is what reads as lag).
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    return AlertDialog(
      backgroundColor: AppTheme.surfaceMid,
      title: Text('Current episode',
          style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total != null && total > 0
                ? 'Which episode are you on? (1–$total)'
                : 'Which episode are you on?',
            style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            style: AppTheme.sans(
                fontSize: 18,
                weight: FontWeight.w700,
                color: AppTheme.textPrimary),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surfaceLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                borderSide: BorderSide.none,
              ),
              hintText: 'Episode number',
              hintStyle:
                  AppTheme.sans(fontSize: 14, color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child:
              Text('Cancel', style: AppTheme.sans(color: AppTheme.textMuted)),
        ),
        TextButton(
          onPressed: () {
            final v = int.tryParse(_controller.text.trim());
            Navigator.pop(context);
            if (v == null || v < 0) return;
            final clamped =
                (total != null && total > 0) ? v.clamp(0, total) : v;
            widget.onSave(clamped);
          },
          // Washi, not coral: in Hanko coral is only your seal.
          child: Text('Save',
              style: AppTheme.sans(
                  color: AppTheme.hankoWashi, weight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? iconColor;
  final String? badge;
  const _IconBtn({required this.icon, required this.onTap, required this.color, this.iconColor, this.badge});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(30), border: Border.all(color: AppTheme.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: iconColor ?? AppTheme.textSecondary, size: 18),
            if (badge != null) ...[const SizedBox(width: 4), Text(badge!, style: AppTheme.sans(fontSize: 12, weight: FontWeight.w600, color: iconColor ?? AppTheme.textSecondary))],
          ]),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final bool dark;
  final bool accent;
  const _StatBox({required this.value, required this.label, this.dark = false, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final bg = accent ? AppTheme.primary : dark ? AppTheme.surface : AppTheme.surfaceLight;
    final vc = accent ? Colors.white : AppTheme.textPrimary;
    final lc = accent ? Colors.white.withValues(alpha: 0.7) : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: AppTheme.serif(fontSize: 24, weight: FontWeight.w700, color: vc)),
        const SizedBox(height: 4),
        Text(label, style: AppTheme.mono(fontSize: 9, color: lc, letterSpacing: 0.5)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.8)),
      const Spacer(),
      Text(value, style: AppTheme.sans(fontSize: 14, weight: FontWeight.w500)),
    ]);
  }
}

class _SynopsisText extends StatefulWidget {
  final String text;
  const _SynopsisText({super.key, required this.text});

  @override
  State<_SynopsisText> createState() => _SynopsisTextState();
}

class _SynopsisTextState extends State<_SynopsisText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(widget.text, maxLines: 5, overflow: TextOverflow.ellipsis, style: AppTheme.sans(fontSize: 14, color: AppTheme.textSecondary, height: 1.7)),
          secondChild: Text(widget.text, style: AppTheme.sans(fontSize: 14, color: AppTheme.textSecondary, height: 1.7)),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        // Hanko's link: washi with an edge-coloured underline, in a 48 dp
        // target; no coral.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Align(
              widthFactor: 1,
              alignment: Alignment.centerLeft,
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: AppTheme.hankoSans(fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w500).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.hankoEdge,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Simple Tab Bar ───────────────────────────────────────────
class _SimpleTabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTap;
  const _SimpleTabBar({required this.selected, required this.onTap});

  static const _tabs = ['Overview', 'Episodes', 'Cast', 'You May Like'];

  // The Episodes tab is switched off (round seven). It listed "Episode 1"
  // to the last as rows that did nothing; Shahid, 2026-11-03: "not sure why
  // we have this option of episode list doesn't do anything, we can have the
  // number of episodes somewhere on the detail screen remove it". The count
  // is in the header's facts and on each season in the Seasons strip. Kept,
  // not deleted (CLAUDE.md); true brings it back as it was.
  static const bool _showEpisodes = false;

  /// The tabs shown, as indices into [_tabs]. They are also _TabContent's
  /// cases, so a hidden tab keeps its number and its code.
  static const List<int> shown = [0, if (_showEpisodes) 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          Row(
            children: List.generate(shown.length, (at) {
              final i = shown[at];
              final isSelected = selected == i;
              return Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  // Its own semantics node (container), named by the tab and
                  // keeping its selected state, with the InkWell's tap and
                  // focus inside it (question 139, R5B's pattern): with a
                  // GestureDetector the keyboard couldn't switch tabs. The
                  // word drawn is left out, since the label says it. The
                  // transparent Material is the InkWell's ink layer, over
                  // the bar's fill; the cell has none of its own now, as it
                  // would hide the ink, and the bar's is the same colour.
                  child: Semantics(
                    container: true,
                    button: true,
                    selected: isSelected,
                    label: _tabs[i],
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () => onTap(i),
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: AppTheme.hankoPressWash,
                        child: ExcludeSemantics(
                          child: Padding(
                            // 14 + 14 around the label: a 48 dp target (H3).
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                            // One line, scaled down to its quarter when large
                            // text would wrap it: at 1.3x "You May Like" wrapped
                            // and overflowed the header by 23 px (H2 QA, §1c).
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _tabs[i],
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.center,
                                style: AppTheme.sans(
                                  fontSize: 13,
                                  weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                  // Hanko: washi for the tab you're on, stone for
                                  // the rest; coral is only your seal now.
                                  color: isSelected ? AppTheme.hankoWashi : AppTheme.hankoStone,
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
            }),
          ),
          // Indicator row
          Row(
            children: List.generate(shown.length, (at) {
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2,
                  color: selected == shown[at] ? AppTheme.hankoWashi : Colors.transparent,
                ),
              );
            }),
          ),
          Container(height: 1, color: AppTheme.border),
        ],
      ),
    );
  }
}

// ── Tab Content ──────────────────────────────────────────────
class _TabContent extends StatelessWidget {
  final int selectedIndex;
  final Anime anime;
  final Map<String, dynamic>? staffData;
  final bool isLoadingStaff;
  final String Function(String) cleanDescription;
  final int? currentEpisode;
  final List<Anime> relatedAnime;
  final bool isLoadingRelated;
  final DateTime? nextAiringAt;
  final int? nextEpisodeNum;
  final ValueListenable<Duration> timeUntilAiring;
  final List<String> characterImages;

  const _TabContent({
    required this.selectedIndex,
    required this.anime,
    required this.staffData,
    required this.isLoadingStaff,
    required this.cleanDescription,
    required this.currentEpisode,
    required this.relatedAnime,
    required this.isLoadingRelated,
    this.nextAiringAt,
    this.nextEpisodeNum,
    required this.timeUntilAiring,
    this.characterImages = const [],
  });

  @override
  Widget build(BuildContext context) {
    switch (selectedIndex) {
      case 0:
        return _OverviewTab(
          anime: anime,
          staffData: staffData,
          isLoadingStaff: isLoadingStaff,
          cleanDescription: cleanDescription,
          currentEpisode: currentEpisode,
          nextAiringAt: nextAiringAt,
          nextEpisodeNum: nextEpisodeNum,
          timeUntilAiring: timeUntilAiring,
          characterImages: characterImages,
          relatedAnime: relatedAnime,
        );
      case 1:
        return _EpisodesTab(anime: anime, currentEpisode: currentEpisode);
      case 2:
        return _CastTab(staffData: staffData, isLoading: isLoadingStaff);
      case 3:
        return _RelatedTab(
          anime: relatedAnime,
          isLoading: isLoadingRelated,
          failed: staffData == null && !isLoadingStaff,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Streaming Buttons ─────────────────────────────────────────

class _StreamingButtons extends StatelessWidget {
  final Anime anime;
  const _StreamingButtons({required this.anime});

  String get _searchTitle => Uri.encodeComponent(anime.titleEnglish ?? anime.title);

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StreamButton(
            label: 'Search on Crunchyroll',
            emoji: '🟠',
            color: const Color(0xFFF47521),
            bgColor: const Color(0xFF1A0C02),
            onTap: () => _launch(
                'https://www.crunchyroll.com/search?q=$_searchTitle'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StreamButton(
            label: 'Search on Netflix',
            emoji: '🔴',
            color: const Color(0xFFE50914),
            bgColor: const Color(0xFF1A0202),
            onTap: () => _launch(
                'https://www.netflix.com/search?q=$_searchTitle'),
          ),
        ),
      ],
    );
  }
}

class _StreamButton extends StatelessWidget {
  final String label;
  final String emoji;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _StreamButton({
    required this.label,
    required this.emoji,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: AppTheme.sans(
                    fontSize: 13,
                    weight: FontWeight.w600,
                    color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Next Episode Countdown ────────────────────────────────────

class _NextEpisodeCountdown extends StatefulWidget {
  final String animeId;
  final int episode;
  final DateTime airingAt;
  final ValueListenable<Duration> timeUntil;

  const _NextEpisodeCountdown({
    required this.animeId,
    required this.episode,
    required this.airingAt,
    required this.timeUntil,
  });

  @override
  State<_NextEpisodeCountdown> createState() => _NextEpisodeCountdownState();
}

class _NextEpisodeCountdownState extends State<_NextEpisodeCountdown> {
  bool _reminderOn = false;

  @override
  void initState() {
    super.initState();
    _loadReminder();
  }

  Future<void> _loadReminder() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts').doc(widget.animeId)
        .get();
    if (mounted && doc.exists) {
      setState(() => _reminderOn = doc.exists);
    }
  }

  Future<void> _saveReminder(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts').doc(widget.animeId);
    if (value) {
      await ref.set({
        'animeId': widget.animeId,
        'episode': widget.episode,
        // toUtc() before toIso8601String(): widget.airingAt is a local
        // DateTime (AniList's epoch through fromMillisecondsSinceEpoch), and
        // toIso8601String() on a local DateTime emits no offset, so the value
        // stored was the writer's wall clock wearing no timezone. See AUDIT.md
        // 6e A1. Legacy documents still hold naive strings.
        'airingAt': widget.airingAt.toUtc().toIso8601String(),
        'addedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// When the episode airs, by Home's rules (Coming up's `_when`, question
  /// 111): "Today at 13:00", "Tomorrow at 13:00", the weekday from 2 to 6
  /// days on ("Friday at 13:00"), else the date ("13 Nov at 13:00"), by the
  /// device's own calendar and its 24-hour clock. The date is the header's
  /// own (`HankoDetailHeader._date`), so the two lines agree. It used to
  /// count whole 24-hour spans, so an episode tomorrow at 13:00, seen after
  /// 13:00 today, read "Today at 1:00 PM".
  String _friendlyDate() {
    final now = DateTime.now();
    final diff = widget.airingAt.difference(now);
    final local = widget.airingAt.toLocal();

    if (diff.isNegative) return 'Airing now';
    final days = DateTime.utc(local.year, local.month, local.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    final day = switch (days) {
      <= 0 => 'Today',
      1 => 'Tomorrow',
      < 7 => HankoDetailHeader._weekdays[local.weekday - 1],
      _ => HankoDetailHeader._date(local),
    };
    return '$day at ${_timeStr(local)}';
  }

  /// The 24-hour clock, as Home's: "13:00".
  String _timeStr(DateTime dt) => '${_pad(dt.hour)}:${_pad(dt.minute)}';

  /// The clock's digits, drawn over a copy of themselves in zeros that is
  /// laid out but never painted (question 115). The copy gives the clock its
  /// size, which tabular figures keep the same whatever the digits (Jost's
  /// are all 0.6 em), so the digits get tight constraints, which make them
  /// their own relayout boundary, and a RepaintBoundary of their own. A new
  /// second then lays out and repaints the digits alone: before, the clock's
  /// layout ran up to the screen's scroll view, which repainted the whole
  /// page every second (about 2 ms of layout and 6–8 ms of paint per tick
  /// on the phone).
  Widget _clock(Duration timeUntil) {
    final d = timeUntil.inDays;
    final h = timeUntil.inHours % 24;
    final m = timeUntil.inMinutes % 60;
    final s = timeUntil.inSeconds % 60;
    Widget units(String Function(int) digits) => Row(
          children: [
            if (d > 0) ...[
              _CountUnit(digits(d), 'D'),
              const SizedBox(width: 6),
            ],
            _CountUnit(digits(h), 'H'),
            const SizedBox(width: 6),
            _CountUnit(digits(m), 'M'),
            if (d == 0) ...[
              const SizedBox(width: 6),
              _CountUnit(digits(s), 'S'),
            ],
          ],
        );
    return Stack(
      children: [
        Opacity(opacity: 0, child: units((n) => '0' * _pad(n).length)),
        Positioned.fill(child: RepaintBoundary(child: units(_pad))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The card builds once, and again when the bell changes. On a tick only
    // its two parts that show the time can rebuild, and only when what they
    // show changes (question 115): the clock once a minute while it shows
    // days and once a second when it shows seconds, the date line when its
    // words or colour turn. The whole card used to rebuild every second.
    return _buildCard(context);
  }

  Widget _buildCard(BuildContext context) {
    Future<void> toggle() async {
      final newVal = !_reminderOn;
      setState(() => _reminderOn = newVal);
      final saving = _saveReminder(newVal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newVal
              ? 'Reminder set for Episode ${widget.episode}'
              : 'Reminder removed for Episode ${widget.episode}'),
          backgroundColor: AppTheme.surfaceLight,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
          duration: const Duration(seconds: 2),
        ),
      );
      // Question 84, with question 83's pattern: the write is awaited and
      // caught. Unawaited, a refused write (by the rules, say) went to
      // PlatformDispatcher.onError, which main.dart reports to Crashlytics as
      // fatal, and the bell went on showing a reminder that wasn't saved. Now
      // the bell goes back and the message says so, naming no cause. Offline,
      // the write waits for the connection and the bell stays as tapped.
      try {
        await saving;
      } catch (_) {
        if (!context.mounted) return;
        setState(() => _reminderOn = !newVal);
        // In place of "Reminder set" if it's still showing.
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
            ),
          );
      }
    }

    // Hanko: a sumi 2 field with 2 px corners. No coral border and no
    // blurred glow (blur is the app's costliest raster effect, PERF.md); an
    // imminent episode shows in its date line, in washi.
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi2,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'Next episode',
                style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, color: AppTheme.hankoStone),
              ),
              const Spacer(),
              // Notification bell: a square that is filled when on, 48 dp
              // to touch, its state in its name for screen readers. It is
              // its own semantics node (question 104; Coming up's bell since
              // 0111ffc). Folded into the card, the bell's name and state
              // made the whole card one switch with no tap, so a screen
              // reader couldn't set the reminder. The InkWell's tap and focus
              // are inside that node (question 119, as Profile's rows in
              // 878a397): a tap given on the node over excluded semantics
              // reached a screen reader, but the keyboard couldn't reach the
              // bell. The transparent Material is the InkWell's own ink
              // layer: ink is drawn under a Material's children, and the
              // nearest Material was the Scaffold's, under the card's fill,
              // which would have hidden the bell's focus and press washes.
              // It hovers with the press wash, as Home's and the Calendar's
              // bells do (question 152).
              Semantics(
                container: true,
                button: true,
                toggled: _reminderOn,
                label: 'Remind me when episode ${widget.episode} airs',
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: toggle,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: AppTheme.hankoPressWash,
                    hoverColor: AppTheme.hankoPressWash,
                    child: ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: AppTheme.hankoTouch,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: _reminderOn ? AppTheme.hankoWashi : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                              border: _reminderOn ? null : Border.all(color: AppTheme.hankoEdge),
                            ),
                            child: Icon(
                              _reminderOn ? Icons.notifications_sharp : Icons.notifications_none_outlined,
                              color: _reminderOn ? AppTheme.hankoSumi : AppTheme.hankoWashi,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          // Episode + date
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Episode ${widget.episode}',
                style: AppTheme.hankoSerif(fontSize: 22),
              ),
              const Spacer(),
              // Countdown clock (see _clock), none before the first tick
              // when the time has already passed.
              _CountdownPart(
                timeUntil: widget.timeUntil,
                shown: (t) => t.isNegative
                    ? null
                    : (
                        t.inDays > 0 ? t.inDays : null,
                        t.inHours % 24,
                        t.inMinutes % 60,
                        t.inDays == 0 ? t.inSeconds % 60 : null,
                      ),
                builder: (context, t) =>
                    t.isNegative ? const SizedBox.shrink() : _clock(t),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Friendly date string, in washi within the hour
          _CountdownPart(
            timeUntil: widget.timeUntil,
            shown: (t) => (_friendlyDate(), t.inHours < 1),
            builder: (context, t) {
              final isImminent = t.inHours < 1;
              return Row(
                children: [
                  Icon(
                    Icons.schedule_sharp,
                    size: 14,
                    color: isImminent ? AppTheme.hankoWashi : AppTheme.hankoStone,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _friendlyDate(),
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        color: isImminent ? AppTheme.hankoWashi : AppTheme.hankoStone),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A part of the countdown card that shows the time. It listens to the
/// ticks itself and rebuilds only when [shown], what it picks out of the
/// time left, changes (question 115).
class _CountdownPart extends StatefulWidget {
  const _CountdownPart({required this.timeUntil, required this.shown, required this.builder});

  final ValueListenable<Duration> timeUntil;
  final Object? Function(Duration timeUntil) shown;
  final Widget Function(BuildContext context, Duration timeUntil) builder;

  @override
  State<_CountdownPart> createState() => _CountdownPartState();
}

class _CountdownPartState extends State<_CountdownPart> {
  Object? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.shown(widget.timeUntil.value);
    widget.timeUntil.addListener(_tick);
  }

  @override
  void didUpdateWidget(_CountdownPart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeUntil != widget.timeUntil) {
      oldWidget.timeUntil.removeListener(_tick);
      widget.timeUntil.addListener(_tick);
    }
    _shown = widget.shown(widget.timeUntil.value);
  }

  @override
  void dispose() {
    widget.timeUntil.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final shown = widget.shown(widget.timeUntil.value);
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.timeUntil.value);
}

class _CountUnit extends StatelessWidget {
  final String value;
  final String label;

  const _CountUnit(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hanko: washi tabular figures; units at 11, not 8.
        Text(
          value,
          style: AppTheme.hankoSans(
              fontSize: 16,
              weight: FontWeight.w500,
              tabular: true),
        ),
        Text(
          label,
          style: AppTheme.hankoSans(fontSize: AppTheme.hankoDataSmallSize, color: AppTheme.hankoStone),
        ),
      ],
    );
  }
}

// ── Image Gallery ─────────────────────────────────────────────────────────────
// Full-screen swipeable image viewer.
// Opened by tapping the cover poster or any character thumbnail.
// Swipe left/right to browse, pinch to zoom, tap X or swipe down to close.

void _openGallery(BuildContext context, List<String> images, int initialIndex) {
  if (images.isEmpty) return;
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _ImageGalleryScreen(
        images: images,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 220),
    ),
  );
}

class _ImageGalleryScreen extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _ImageGalleryScreen({required this.images, required this.initialIndex});

  @override
  State<_ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<_ImageGalleryScreen> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Swipeable pages ──────────────────────────────────
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) => _ZoomableImage(url: widget.images[i]),
          ),

          // ── Top bar ──────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  // Counter
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Save button
                  GestureDetector(
                    onTap: () => _saveImage(context, widget.images[_current]),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.download_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Dot indicators ───────────────────────────────────
          if (widget.images.length > 1)
            Positioned(
              bottom: 32,
              left: 0, right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) {
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.hankoWashi
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveImage(BuildContext context, String url) async {
    // Show loading indicator on the button while saving
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saving…'),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF1A1A1A),
        ),
      );
    }
    try {
      // Request permission (required on Android < 13)
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permission needed to save images')),
            );
          }
          return;
        }
      }
      // Download image bytes
      final resp = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 200) {
        await Gal.putImageBytes(resp.bodyBytes, name: 'hanj_${DateTime.now().millisecondsSinceEpoch}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved to gallery'),
              backgroundColor: Color(0xFF1A1A1A),
            ),
          );
        }
      } else {
        throw Exception('Download failed');
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save image')),
        );
      }
    }
  }
}

// ── Zoomable image page ───────────────────────────────────────
class _ZoomableImage extends StatefulWidget {
  final String url;
  const _ZoomableImage({required this.url});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final screenH = MediaQuery.sizeOf(context).height;
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1.0,
      maxScale: 4.0,
      // Lock image to screen — prevents drifting while swiping between pages
      boundaryMargin: EdgeInsets.zero,
      child: SizedBox(
        width: screenW,
        height: screenH,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: widget.url,
            width: screenW,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(
                color: AppTheme.hankoWashi,
                strokeWidth: 2,
              ),
            ),
            errorWidget: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white30, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
