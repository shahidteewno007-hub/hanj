import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../widgets/confetti_overlay.dart';
import '../../models/anime_model.dart';
import '../../services/firestore_service.dart';
import '../../services/anilist_service.dart';
import '../../services/offline_cache_service.dart';
import '../../core/trailer_launcher.dart';
import '../../widgets/share_card.dart';
import '../episode_discussions/episode_discussion_screen.dart';
import '../staff_detail/studio_detail_screen.dart';
import '../staff_detail/staff_detail_screen.dart';
import '../home/home_screen.dart' show showHanjListSheet;

class AnimeDetailScreen extends StatefulWidget {
  final Anime anime;
  const AnimeDetailScreen({super.key, required this.anime});

  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen>
{
  final _firestoreService = FirestoreService();
  final _aniListService   = AnilistService();
  final _confettiKey      = GlobalKey<ConfettiOverlayState>();
  // Full anime details. Starts as whatever was passed in (may be a stub when
  // opened from Continue), then gets enriched via getAnimeById on open.
  late Anime _anime;
  String? _currentStatus;
  double? _userRating;
  int?    _currentEpisode;
  bool    _isLoading       = false;
  int     _selectedTab     = 0;
  int     _swipeDirection  = 1; // 1 = left-to-right, -1 = right-to-left
  Map<String, dynamic>? _staffData;
  bool _isLoadingStaff     = false;
  List<Anime> _relatedAnime = [];
  List<String> _characterImages = [];
  List<String> _galleryImages = []; // high-res poster + banner for the gallery
  bool _isLoadingRelated   = false;

  // Next episode airing data
  DateTime? _nextAiringAt;
  int?      _nextEpisodeNum;
  Timer?    _countdownTimer;
  // Ticks once a second. Held in a ValueNotifier rather than plain state so the
  // per-second update rebuilds only the countdown card, not this whole screen.
  final ValueNotifier<Duration> _timeUntilAiring =
      ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    _anime = widget.anime;
    _loadData();
    // Cache the anime for offline viewing later
    OfflineCacheService.instance.cacheAnimeDetail(widget.anime);
    // Defer network fetches until after the first frame so the synchronous
    // setState(isLoading=true) calls inside them don't fire during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadFullAnime();
      _loadStaffData();
      _loadRelatedAnime();
      _loadAiringData();
      _loadGalleryImages();
    });
  }

  // Enrich the (possibly stub) anime with full details. When opened from
  // Continue, the passed object only has id/title/image/episodes/genres, so
  // score, status, season, romaji, synopsis etc. would be blank without this.
  Future<void> _loadFullAnime() async {
    // Skip if we already have rich data (opened from search/trending).
    if (widget.anime.averageScore != null && widget.anime.status != null) {
      return;
    }
    try {
      final full = await _aniListService.getAnimeById(widget.anime.id);
      if (full != null && mounted) {
        setState(() => _anime = full);
        OfflineCacheService.instance.cacheAnimeDetail(full);
        // Re-run fetches now that we have the real status + genres.
        _loadAiringData();
        _loadRelatedAnime();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _timeUntilAiring.dispose();
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
    final status = await _firestoreService.getAnimeStatus(id);
    final rating = await _firestoreService.getUserRating(id);
    final ep     = await _firestoreService.getEpisodeProgress(id);
    if (mounted) setState(() { _currentStatus = status; _userRating = rating; _currentEpisode = ep; });
  }

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
      final resp = await http.Client().post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: '{"query":"${query.replaceAll('\n', ' ').replaceAll('"', '\\"')}","variables":{"id":$animeId}}',
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      return data['data']['Media']['nextAiringEpisode'] as Map<String, dynamic>?;
    } catch (_) { return null; }
  }

  Future<void> _loadStaffData() async {
    if (mounted) setState(() => _isLoadingStaff = true);
    try {
      final data = await _aniListService.getAnimeStaff(_anime.id);
      if (mounted) {
        final chars = data?['characters']?['edges'] as List? ?? [];
        final imgs = <String>[];
        for (final e in chars) {
          final img = e['node']?['image']?['medium'] as String?;
          if (img != null && imgs.length < 8) imgs.add(img);
        }
        setState(() { _staffData = data; _isLoadingStaff = false; _characterImages = imgs; });
      }
    } catch (_) { if (mounted) setState(() => _isLoadingStaff = false); }
  }

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
      setState(() { _currentStatus = null; _userRating = null; _currentEpisode = null; _isLoading = false; });
    } else {
      // Sheet already saved to Firestore — just update UI immediately
      setState(() => _currentStatus = result);
      if (result == 'COMPLETED') {
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
                await _firestoreService.updateRating(int.parse(widget.anime.id), tempRating);
                setState(() => _userRating = tempRating);
              },
              child: Text('Save', style: AppTheme.sans(color: AppTheme.primary, weight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEpisodeDialog() {
    final total = _anime.episodes;
    showDialog(
      context: context,
      builder: (_) => _EpisodeInputDialog(
        total: total,
        initial: _currentEpisode ?? 0,
        onSave: (clamped) async {
          await _firestoreService.updateEpisodeProgress(
              int.parse(widget.anime.id), clamped);
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
            slivers: [
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
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // Tab bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  _SimpleTabBar(
                    selected: _selectedTab,
                    onTap: (i) => setState(() => _selectedTab = i),
                  ),
                ),
              ),
            // Tab content — swipeable via horizontal drag
            SliverToBoxAdapter(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! < -200 && _selectedTab < 3) {
                    setState(() { _swipeDirection = 1; _selectedTab++; });
                  } else if (details.primaryVelocity! > 200 && _selectedTab > 0) {
                    setState(() { _swipeDirection = -1; _selectedTab--; });
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    final offset = Tween<Offset>(
                      begin: Offset(_swipeDirection * 0.18, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
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
                        anime: anime,
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
          ],
          ),
          ConfettiOverlay(key: _confettiKey),
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
        Container(color: const Color(0xFF0D0B09)),

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
  final Anime anime;
  final Map<String, dynamic>? staffData;
  final bool isLoadingStaff;
  final String Function(String) cleanDescription;
  final int? currentEpisode;
  final DateTime? nextAiringAt;
  final int? nextEpisodeNum;
  final ValueListenable<Duration> timeUntilAiring;
  final List<String> characterImages;

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
  });

  @override
  Widget build(BuildContext context) {
    final studio = (staffData?['studios']?['nodes'] as List?)?.isNotEmpty == true
        ? (staffData!['studios']['nodes'] as List)[0]['name'] as String?
        : null;

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

        // Synopsis
        if (anime.description != null) ...[
          Row(children: [
            Container(width: 3, height: 20, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Text('Synopsis', style: AppTheme.serif(fontSize: 20, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text('A STORY IN MOTION', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          _SynopsisText(text: cleanDescription(anime.description!)),
          const SizedBox(height: 28),
        ],

        // Stat tiles
        Row(children: [
          Expanded(child: _StatBox(value: anime.averageScore != null ? '${(anime.averageScore! / 10 * 10).round()}%' : '—', label: 'MEMBERS\nwatching', dark: true)),
          const SizedBox(width: 8),
          Expanded(child: _StatBox(value: anime.episodes != null ? '${anime.episodes}' : '—', label: 'EPISODES\nthis season')),
          const SizedBox(width: 8),
          Expanded(child: _StatBox(value: anime.status == 'RELEASING' ? '+18%' : '—', label: 'TRENDING\nvs last wk', accent: true)),
        ]),
        const SizedBox(height: 28),

        // Themes
        if (anime.genres.isNotEmpty) ...[
          Text('THEMES', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8,
            children: anime.genres.map((g) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
              child: Text(g, style: AppTheme.sans(fontSize: 13, color: AppTheme.textSecondary)),
            )).toList(),
          ),
          const SizedBox(height: 28),
        ],

        // Information
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

        // Characters are shown in the Cast tab (AniList medium images are too low-res for a gallery strip)

        // Trailer
        if (anime.trailerUrl != null) ...[
          Text('TRAILER', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          TrailerButton(trailerUrl: anime.trailerUrl!),
          const SizedBox(height: 28),
        ],

        // ── Discussion ──────────────────────────────────────
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EpisodeDiscussionScreen(anime: anime, episodeNumber: 0))),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
              child: Row(children: [
                const Icon(Icons.forum_outlined, size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Text('Join the discussion', style: AppTheme.sans(fontSize: 15, weight: FontWeight.w600)),
                const Spacer(),
                Text('→', style: AppTheme.sans(fontSize: 15, color: AppTheme.primary)),
              ]),
            ),
          ),
        ),
      ],
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
    final total   = anime.episodes ?? 12;
    final watched = currentEpisode ?? 0;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: total,
      itemBuilder: (_, i) {
        final ep = i + 1;
        final isWatched = ep <= watched;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isWatched ? AppTheme.completed.withValues(alpha: 0.3) : AppTheme.border),
          ),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: isWatched ? AppTheme.completed.withValues(alpha: 0.15) : AppTheme.surfaceMid, borderRadius: BorderRadius.circular(8)),
              child: Center(child: isWatched ? const Icon(Icons.check_rounded, color: AppTheme.completed, size: 16) : Text('$ep', style: AppTheme.mono(fontSize: 12, weight: FontWeight.w600))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Episode $ep', style: AppTheme.sans(fontSize: 14, weight: FontWeight.w600)),
              Text('24 min', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted)),
            ])),
            if (isWatched) Text('WATCHED', style: AppTheme.mono(fontSize: 9, color: AppTheme.completed, letterSpacing: 0.5)),
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
    if (isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 1.5));
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
            Text(
              staffData == null
                  ? 'Couldn\'t load cast — check your connection.'
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
          Text('CHARACTERS & VOICE ACTORS', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          for (final e in characters.take(8)) ...[_CastRow(edge: e as Map<String, dynamic>), const SizedBox(height: 10)],
          const SizedBox(height: 24),
        ],
        if (staff.isNotEmpty) ...[
          Text('STAFF', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1)),
          const SizedBox(height: 12),
          for (final e in staff.take(8)) ...[_StaffRow(edge: e as Map<String, dynamic>), const SizedBox(height: 10)],
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Row(children: [
        _Avatar(url: char?['image']?['medium'] as String?, name: char?['name']?['full'] as String? ?? '?'),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(char?['name']?['full'] as String? ?? '—', style: AppTheme.sans(fontSize: 13, weight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Character', style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted)),
        ])),
        if (va != null) ...[
          const SizedBox(width: 8),
          MouseRegion(
            cursor: vaId != null ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              onTap: vaId != null ? () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => StaffDetailScreen(staffId: vaId, staffName: vaName))) : null,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(vaName.isNotEmpty ? vaName : '—',
                      style: AppTheme.sans(fontSize: 12, weight: FontWeight.w600,
                          color: vaId != null ? AppTheme.primary : AppTheme.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('VA', style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted)),
                ]),
                const SizedBox(width: 8),
                _Avatar(url: va['image']?['medium'] as String?, name: vaName),
              ]),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () { final id = node?['id'] as int?; final name = node?['name']?['full'] as String? ?? ''; if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => StaffDetailScreen(staffId: id, staffName: name))); },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            _Avatar(url: node?['image']?['medium'] as String?, name: node?['name']?['full'] as String? ?? '?'),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(node?['name']?['full'] as String? ?? '—', style: AppTheme.sans(fontSize: 14, weight: FontWeight.w600)),
              Text(role, style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 16),
          ]),
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
  const _RelatedTab({required this.anime, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 1.5));
    if (anime.isEmpty) return Center(child: Text('No related anime found', style: AppTheme.sans(color: AppTheme.textMuted)));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: anime.length,
      itemBuilder: (_, i) => _RelatedCard(anime: anime[i]),
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
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.anime.imageUrl != null
                    ? CachedNetworkImage(imageUrl: widget.anime.imageUrl!, fit: BoxFit.cover, width: double.infinity, errorWidget: (_, _, _) => Container(color: AppTheme.surfaceLight))
                    : Container(color: AppTheme.surfaceLight),
              )),
              const SizedBox(height: 6),
              Text(widget.anime.titleEnglish ?? widget.anime.title, style: AppTheme.sans(fontSize: 12, weight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.anime.genres.isNotEmpty)
                Text(widget.anime.genres.first.toUpperCase(), style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted, letterSpacing: 0.5)),
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
                borderRadius: BorderRadius.circular(12),
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
          child: Text('Save',
              style: AppTheme.sans(
                  color: AppTheme.primary, weight: FontWeight.w600)),
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
  const _SynopsisText({required this.text});

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
        const SizedBox(height: 10),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(children: [
              Text(_expanded ? 'Show less' : 'Read more', style: AppTheme.sans(fontSize: 13, weight: FontWeight.w600, color: AppTheme.primary)),
              const SizedBox(width: 4),
              Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 16),
            ]),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Column(
        children: [
          Row(
            children: List.generate(_tabs.length, (i) {
              final isSelected = selected == i;
              return Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      color: AppTheme.background,
                      child: Text(
                        _tabs[i],
                        textAlign: TextAlign.center,
                        style: AppTheme.sans(
                          fontSize: 13,
                          weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? AppTheme.primary : AppTheme.textMuted,
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
            children: List.generate(_tabs.length, (i) {
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 2,
                  color: selected == i ? AppTheme.primary : Colors.transparent,
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
        );
      case 1:
        return _EpisodesTab(anime: anime, currentEpisode: currentEpisode);
      case 2:
        return _CastTab(staffData: staffData, isLoading: isLoadingStaff);
      case 3:
        return _RelatedTab(anime: relatedAnime, isLoading: isLoadingRelated);
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

  String _friendlyDate() {
    final now = DateTime.now();
    final diff = widget.airingAt.difference(now);
    final local = widget.airingAt.toLocal();

    if (diff.isNegative) return 'Airing now';
    if (diff.inDays == 0) return 'Today at ${_timeStr(local)}';
    if (diff.inDays == 1) return 'Tomorrow at ${_timeStr(local)}';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[local.weekday - 1]} at ${_timeStr(local)}';
    }
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[local.month - 1]} ${local.day} at ${_timeStr(local)}';
  }

  String _timeStr(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = _pad(dt.minute);
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    // Only this card rebuilds on each tick. Previously the parent screen called
    // setState every second, rebuilding the whole 2,190-line detail screen.
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.timeUntil,
      builder: (context, timeUntil, _) => _buildCard(context, timeUntil),
    );
  }

  Widget _buildCard(BuildContext context, Duration timeUntil) {
    final d = timeUntil.inDays;
    final h = timeUntil.inHours % 24;
    final m = timeUntil.inMinutes % 60;
    final s = timeUntil.inSeconds % 60;
    final isImminent = timeUntil.inHours < 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isImminent
              ? AppTheme.primary.withValues(alpha: 0.5)
              : AppTheme.border,
        ),
        boxShadow: isImminent
            ? [BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.08),
                blurRadius: 12,
              )]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'UP NEXT',
                  style: AppTheme.mono(
                      fontSize: 9,
                      color: AppTheme.primary,
                      letterSpacing: 1.5),
                ),
              ),
              const Spacer(),
              // Notification bell
              GestureDetector(
                onTap: () {
                  final newVal = !_reminderOn;
                  setState(() => _reminderOn = newVal);
                  _saveReminder(newVal);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(newVal
                          ? 'Reminder set for Episode ${widget.episode}'
                          : 'Reminder removed for Episode ${widget.episode}'),
                      backgroundColor: AppTheme.surfaceLight,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: _reminderOn ? AppTheme.primary : AppTheme.surfaceMid,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _reminderOn ? AppTheme.primary : AppTheme.border,
                    ),
                    boxShadow: _reminderOn ? [BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )] : [],
                  ),
                  child: Icon(
                    _reminderOn ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                    color: _reminderOn ? Colors.white : AppTheme.textMuted,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Episode + date
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Episode ${widget.episode}',
                style: AppTheme.serif(fontSize: 22, weight: FontWeight.w700),
              ),
              const Spacer(),
              // Countdown clock
              if (!timeUntil.isNegative)
                Row(
                  children: [
                    if (d > 0) ...[
                      _CountUnit(_pad(d), 'D'),
                      const SizedBox(width: 6),
                    ],
                    _CountUnit(_pad(h), 'H'),
                    const SizedBox(width: 6),
                    _CountUnit(_pad(m), 'M'),
                    if (d == 0) ...[
                      const SizedBox(width: 6),
                      _CountUnit(_pad(s), 'S'),
                    ],
                  ],
                ),
            ],
          ),

          const SizedBox(height: 6),

          // Friendly date string
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 12,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                _friendlyDate(),
                style: AppTheme.mono(
                    fontSize: 11,
                    color: isImminent ? AppTheme.primary : AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
        Text(
          value,
          style: AppTheme.mono(
              fontSize: 16,
              color: AppTheme.primary,
              letterSpacing: 0),
        ),
        Text(
          label,
          style: AppTheme.mono(fontSize: 8, color: AppTheme.textMuted),
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
                          ? const Color(0xFFF97316)
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
                color: Color(0xFFF97316),
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
