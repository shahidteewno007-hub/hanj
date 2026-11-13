import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/hanko_board.dart';

enum ImportSource { mal, anilist, csv }

class AnilistImportScreen extends StatefulWidget {
  const AnilistImportScreen({super.key});

  @override
  State<AnilistImportScreen> createState() => _AnilistImportScreenState();
}

class _AnilistImportScreenState extends State<AnilistImportScreen> {
  final _usernameController = TextEditingController();
  final _firestoreService = FirestoreService();

  ImportSource _selectedSource = ImportSource.mal;
  bool _isLoading = false;
  bool _isDone = false;
  String? _error;
  int _imported = 0;
  int _total = 0;
  String _currentAnime = '';

  // MyAnimeList import only. While its shows are being looked up on AniList
  // (_matching), _lookedUp counts the ones done. _unmatched holds the titles
  // AniList had no match for, which are left out of the import.
  bool _matching = false;
  int _lookedUp = 0;
  List<String> _unmatched = const [];

  /// The screen in flat Hanko (the Vibes report's next stage: a form, so no
  /// boards): sumi with sumi 2 panels and 2 px corners, the chosen source
  /// keylined and ticked in washi (CLAUDE.md: never coral, which is only ever
  /// your verdicts), progress washi on sumi 3, Import as the washi main
  /// action, and the done state in words, not a green badge. Each source is
  /// one button for a screen reader and the keyboard. False gives back the
  /// coral tiles, the coral progress bar and the green badge as they were.
  static const bool _printRoom = true;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String get _hintText {
    switch (_selectedSource) {
      case ImportSource.mal:
      case ImportSource.anilist:
        return 'e.g. shahid123';
      case ImportSource.csv:
        return 'CSV import coming soon';
    }
  }

  String get _usernameLabel {
    switch (_selectedSource) {
      case ImportSource.mal:
        return 'Your MyAnimeList username';
      case ImportSource.anilist:
        return 'Your AniList username';
      case ImportSource.csv:
        return 'Upload CSV file';
    }
  }

  Future<void> _importList() async {
    if (_selectedSource == ImportSource.csv) {
      setState(() => _error = 'CSV import coming soon. Use MAL or AniList for now.');
      return;
    }

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _error = 'Please enter your username.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _imported = 0;
      _total = 0;
      _isDone = false;
      _matching = false;
      _lookedUp = 0;
      _unmatched = const [];
      _currentAnime = '';
    });

    try {
      if (_selectedSource == ImportSource.anilist) {
        await _importFromAniList(username);
      } else {
        await _importFromMAL(username);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _matching = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _importFromAniList(String username) async {
    const query = r'''
    query ($username: String) {
      MediaListCollection(userName: $username, type: ANIME) {
        lists {
          entries {
            status score(format: POINT_10_DECIMAL) progress
            media {
              id title { romaji english }
              coverImage { large }
              episodes averageScore genres
              format status seasonYear season
            }
          }
        }
      }
    }
    ''';

    await AnilistService.throttle();
    final response = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'query': query, 'variables': {'username': username}}),
    );
    AnilistService.noteLimits(response.headers);
    if (response.statusCode == 429) {
      AnilistService.backoff(
          int.tryParse(response.headers['retry-after'] ?? '') ?? 10);
    }

    if (response.statusCode != 200) throw Exception('Failed to connect to AniList.');
    final data = jsonDecode(response.body);
    if (data['errors'] != null) throw Exception('User not found on AniList.');

    final lists = data['data']['MediaListCollection']['lists'] as List;
    int total = 0;
    for (final l in lists) {
      total += (l['entries'] as List).length;
    }
    if (mounted) setState(() => _total = total);

    for (final list in lists) {
      for (final entry in list['entries'] as List) {
        final media = entry['media'];
        if (mounted) {
          setState(() => _currentAnime =
            media['title']['english'] ?? media['title']['romaji'] ?? '');
        }

        await _firestoreService.addAnimeToList(
          anime: Anime(
            id: media['id'].toString(),
            title: media['title']['romaji'] ?? 'Unknown',
            titleEnglish: media['title']['english'],
            imageUrl: media['coverImage']['large'],
            averageScore: (media['averageScore'] as num?)?.toDouble(),
            episodes: media['episodes'] as int?,
            status: media['status'],
            seasonYear: media['seasonYear'] as int?,
            season: media['season'],
            format: media['format'],
            genres: media['genres'] != null
                ? List<String>.from(media['genres']) : [],
          ),
          status: _mapAniListStatus(entry['status'] as String),
          rating: _halfStepRating(entry['score'] as num?),
          currentEpisode: entry['progress'] as int?,
        );
        if (mounted) setState(() => _imported++);
      }
    }
    if (mounted) setState(() { _isLoading = false; _isDone = true; });
  }

  // Hanj rates 1–10 in half steps (Detail's slider: 1.0 to 10.0, 18
  // divisions). The query above asks for POINT_10_DECIMAL, so every score
  // arrives on AniList's 0–10 decimal scale whatever format the list's
  // owner uses (100-point, 10-point, 5-star, 3-smiley). Round it to the
  // half step and keep it inside 1–10, since a 100-point 3 arrives as 0.3.
  // 0 or absent means unrated, as before.
  static double? _halfStepRating(num? score) {
    if (score == null || score <= 0) return null;
    final halfStep = (score * 2).round() / 2;
    return halfStep.clamp(1.0, 10.0).toDouble();
  }

  Future<void> _importFromMAL(String username) async {
    // MAL public API v2 - no auth needed for public lists
    final url = 'https://api.myanimelist.net/v2/users/$username/animelist'
        '?fields=list_status,num_episodes,genres,mean,media_type,start_season'
        '&limit=1000&nsfw=true';

    final response = await http.get(
      Uri.parse(url),
      headers: {'X-MAL-CLIENT-ID': '6114d00ca681b7701d1e15fe11a4987e'},
    );

    if (response.statusCode == 404) throw Exception('User not found on MyAnimeList.');
    if (response.statusCode != 200) throw Exception('Failed to connect to MyAnimeList.');

    final data = jsonDecode(response.body);
    final entries = data['data'] as List;
    if (mounted) {
      setState(() {
        _total = entries.length;
        _matching = true;
      });
    }

    // A MyAnimeList id is not an AniList id, and every lookup in the app
    // (Detail and its staff, airing and gallery requests, Home's airing
    // batch) reads a list entry's id as an AniList id. So each show is
    // looked up on AniList by its MyAnimeList id first, then stored under
    // AniList's id with AniList's title and cover, as the AniList import
    // stores it.
    final aniList = await _aniListByMalId(entries
        .map((entry) => (entry['node'] as Map)['id'])
        .whereType<int>()
        .toList());

    // A show with no AniList match is left out, never stored under its
    // MyAnimeList id, which the rest of the app would take for an AniList
    // id. The done screen says how many were left out, and which.
    final matched = <(Map<String, dynamic>, Map<String, dynamic>)>[];
    final unmatched = <String>[];
    for (final entry in entries) {
      final node = entry['node'] as Map<String, dynamic>;
      final media = aniList[node['id']];
      if (media == null) {
        unmatched.add(node['title'] as String? ?? 'Unknown');
      } else {
        matched.add((media, entry['list_status'] as Map<String, dynamic>));
      }
    }
    if (mounted) {
      setState(() {
        _matching = false;
        _total = matched.length;
        _unmatched = unmatched;
      });
    }

    for (final (media, listStatus) in matched) {
      if (mounted) {
        setState(() => _currentAnime =
          media['title']['english'] ?? media['title']['romaji'] ?? '');
      }

      await _firestoreService.addAnimeToList(
        anime: Anime(
          id: media['id'].toString(),
          title: media['title']['romaji'] ?? 'Unknown',
          titleEnglish: media['title']['english'],
          imageUrl: media['coverImage']['large'],
          averageScore: (media['averageScore'] as num?)?.toDouble(),
          episodes: media['episodes'] as int?,
          status: media['status'],
          seasonYear: media['seasonYear'] as int?,
          season: media['season'],
          format: media['format'],
          genres: media['genres'] != null
              ? List<String>.from(media['genres']) : [],
        ),
        status: _mapMALStatus(listStatus['status'] as String),
        rating: listStatus['score'] != null && listStatus['score'] != 0
            ? (listStatus['score'] as num).toDouble() : null,
        currentEpisode: listStatus['num_episodes_watched'] as int?,
      );
      if (mounted) setState(() => _imported++);
    }
    if (mounted) setState(() { _isLoading = false; _isDone = true; });
  }

  static const _malLookupQuery = r'''
  query ($ids: [Int], $page: Int) {
    Page(page: $page, perPage: 50) {
      pageInfo { hasNextPage }
      media(idMal_in: $ids, type: ANIME) {
        id idMal title { romaji english }
        coverImage { large }
        episodes averageScore genres
        format status seasonYear season
      }
    }
  }
  ''';

  // AniList's entry for each MyAnimeList id, found through AniList's own
  // idMal link. 50 ids go in each request (AniList's page size limit), so
  // a list costs about one request per 50 shows. An id missing from the
  // result has no match on AniList. Every lookup finishes before anything
  // is written, so a failed one leaves the user's list as it was.
  Future<Map<int, Map<String, dynamic>>> _aniListByMalId(
      List<int> malIds) async {
    final found = <int, Map<String, dynamic>>{};
    for (var start = 0; start < malIds.length; start += 50) {
      final end = start + 50 < malIds.length ? start + 50 : malIds.length;
      final batch = malIds.sublist(start, end);
      // AniList reports hasNextPage whenever a page comes back full, so a
      // batch stops as soon as all its ids are found: a further page could
      // only repeat one. It goes on only when a full page still leaves ids
      // unfound, which takes two AniList entries sharing a MyAnimeList id.
      // Capped, so a response that never stops saying hasNextPage can't
      // loop forever.
      for (var page = 1; page <= 3; page++) {
        final result = await _malLookupPage(batch, page);
        for (final m in result['media'] as List) {
          final media = m as Map<String, dynamic>;
          final malId = media['idMal'] as int?;
          // For a shared id, keep the first entry: AniList returns them in
          // id order, so that's the older one.
          if (malId != null) found.putIfAbsent(malId, () => media);
        }
        if (result['pageInfo']?['hasNextPage'] != true ||
            batch.every(found.containsKey)) {
          break;
        }
      }
      if (mounted) setState(() => _lookedUp = end);
    }
    return found;
  }

  // One lookup request, built on PulseService._query: the shared throttle,
  // a 15 s timeout, noteStatus and noteLimits on every response, and
  // backoff on a 429. A 429 is retried once its backoff has passed, up to
  // three attempts in all, as AnilistService._post does. Any other failure
  // ends the import.
  Future<Map<String, dynamic>> _malLookupPage(List<int> malIds, int page) async {
    for (var attempt = 1;; attempt++) {
      await AnilistService.throttle();
      final http.Response response;
      try {
        response = await http
            .post(
              Uri.parse('https://graphql.anilist.co'),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'User-Agent': 'Hanj/1.0',
              },
              body: jsonEncode({
                'query': _malLookupQuery,
                'variables': {'ids': malIds, 'page': page},
              }),
            )
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        AnilistService.noteStatus(0, 'import');
        throw Exception(_lookupFailed(0));
      }
      AnilistService.noteStatus(response.statusCode, 'import');
      AnilistService.noteLimits(response.headers);
      if (response.statusCode == 429) {
        AnilistService.backoff(
            int.tryParse(response.headers['retry-after'] ?? '') ?? 10);
        if (attempt < 3) continue;
      }
      if (response.statusCode == 200) {
        try {
          final result = (jsonDecode(response.body) as Map)['data']['Page'];
          if (result is Map<String, dynamic> && result['media'] is List) {
            return result;
          }
        } catch (_) {}
      }
      throw Exception(_lookupFailed(response.statusCode));
    }
  }

  // Says what happened (nothing was written) and then the app's usual
  // per-status line, which names no cause the app can't see.
  static String _lookupFailed(int status) =>
      'Nothing was imported: your shows couldn\'t be looked up on AniList. '
      '${AnilistService.messageFor(status)}';

  String _mapAniListStatus(String s) {
    switch (s) {
      case 'CURRENT':   return 'WATCHING';
      case 'COMPLETED': return 'COMPLETED';
      case 'PLANNING':  return 'PLAN_TO_WATCH';
      case 'DROPPED':   return 'DROPPED';
      case 'PAUSED':    return 'WATCHING';
      default:          return 'PLAN_TO_WATCH';
    }
  }

  String _mapMALStatus(String s) {
    switch (s) {
      case 'watching':     return 'WATCHING';
      case 'completed':    return 'COMPLETED';
      case 'plan_to_watch':return 'PLAN_TO_WATCH';
      case 'dropped':      return 'DROPPED';
      case 'on_hold':      return 'WATCHING';
      default:             return 'PLAN_TO_WATCH';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_printRoom) return _printed(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import library',
                style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
            Text('BRING YOUR LIST',
                style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted,
                    letterSpacing: 1.2)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose a source',
                style: AppTheme.serif(fontSize: 20, weight: FontWeight.w600)),
            const SizedBox(height: 16),

            // Source options
            _SourceTile(
              label: 'MyAnimeList',
              tag: 'MAL',
              tagColor: const Color(0xFF2E51A2),
              subtitle: 'PUBLIC PROFILE · USERNAME',
              selected: _selectedSource == ImportSource.mal,
              onTap: () => setState(() => _selectedSource = ImportSource.mal),
            ),
            const SizedBox(height: 10),
            _SourceTile(
              label: 'AniList',
              tag: 'AL',
              tagColor: const Color(0xFF02A9FF),
              subtitle: 'PUBLIC PROFILE · USERNAME',
              selected: _selectedSource == ImportSource.anilist,
              onTap: () => setState(() => _selectedSource = ImportSource.anilist),
            ),
            const SizedBox(height: 10),
            _SourceTile(
              label: 'CSV file',
              tag: 'CSV',
              tagColor: AppTheme.textMuted,
              subtitle: 'UPLOAD AN EXPORTED FILE',
              selected: _selectedSource == ImportSource.csv,
              onTap: () => setState(() => _selectedSource = ImportSource.csv),
            ),

            const SizedBox(height: 24),

            // What we import info box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WHAT WE\'LL BRING ACROSS',
                      style: AppTheme.mono(fontSize: 10,
                          color: AppTheme.textMuted, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  _ImportFeatureRow('List entries', 'ALL'),
                  const Divider(color: AppTheme.border, height: 20),
                  _ImportFeatureRow('Episode progress', 'SYNCED'),
                  const Divider(color: AppTheme.border, height: 20),
                  _ImportFeatureRow('Personal scores', 'PRESERVED'),
                  const Divider(color: AppTheme.border, height: 20),
                  _ImportFeatureRow('Notes & tags', 'MERGED'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            if (!_isDone) ...[
              Text(_usernameLabel,
                  style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                enabled: !_isLoading && _selectedSource != ImportSource.csv,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: _hintText,
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppTheme.textMuted),
                ),
                onSubmitted: (_) => _isLoading ? null : _importList(),
              ),
              const SizedBox(height: 6),
              Text(
                'Profile must be set to public.',
                style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppTheme.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: AppTheme.sans(
                                fontSize: 13, color: AppTheme.error)),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isLoading) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_matching
                                  ? 'Matching with AniList...'
                                  : 'Importing...',
                              style: AppTheme.sans(
                                  fontSize: 13, color: AppTheme.textSecondary)),
                          Text(_matching
                                  ? '$_lookedUp / $_total'
                                  : '$_imported / $_total',
                              style: AppTheme.sans(
                                  fontSize: 13,
                                  weight: FontWeight.w600,
                                  color: AppTheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _total > 0
                              ? (_matching ? _lookedUp : _imported) / _total
                              : null,
                          backgroundColor: AppTheme.border,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.primary),
                          minHeight: 3,
                        ),
                      ),
                      if (_currentAnime.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_currentAnime,
                            style: AppTheme.mono(
                                fontSize: 11, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _importList,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.download_rounded),
                  label: Text(_isLoading ? 'Importing...' : 'Import library'),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '步 · EXISTING ENTRIES ARE MERGED, NEVER OVERWRITTEN',
                  style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted,
                      letterSpacing: 0.8),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else ...[
              // Success
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTheme.success.withValues(alpha: 0.4),
                            width: 2),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppTheme.success, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text('Import Complete!',
                        style: AppTheme.serif(
                            fontSize: 24, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('$_imported anime imported successfully',
                        style: AppTheme.sans(
                            fontSize: 15, color: AppTheme.textSecondary)),
                    if (_unmatched.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                          _unmatched.length == 1
                              ? '1 show couldn\'t be matched on AniList, '
                                  'so it wasn\'t imported:'
                              : '${_unmatched.length} shows couldn\'t be '
                                  'matched on AniList, so they weren\'t '
                                  'imported:',
                          textAlign: TextAlign.center,
                          style: AppTheme.sans(
                              fontSize: 13, color: AppTheme.textSecondary)),
                      const SizedBox(height: 6),
                      Text(
                          _unmatched.length > 10
                              ? '${_unmatched.take(10).join(' · ')} '
                                  '· and ${_unmatched.length - 10} more'
                              : _unmatched.join(' · '),
                          textAlign: TextAlign.center,
                          style: AppTheme.mono(
                              fontSize: 11, color: AppTheme.textMuted)),
                    ],
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go to My List'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Print Room: the screen in flat Hanko ─────────────────────
  // The source tiles keep 3 dp all round for their keyboard focus ring, so
  // everything else is inset by the same 3 dp and every edge lines up on
  // the 20 dp gutter.
  Widget _printed(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    Widget inset(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: _PrintedSourceTile.ringRoom),
          child: child,
        );
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    OutlineInputBorder edge(Color c, [double width = 1]) => OutlineInputBorder(
          borderRadius: corners,
          borderSide: BorderSide(color: c, width: width),
        );
    final label = HankoBoard.labelStyle(color: AppTheme.hankoStone);
    final meta = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone);
    final heading = AppTheme.hankoSerif(fontSize: AppTheme.hankoSectionSize);

    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      appBar: AppBar(
        backgroundColor: AppTheme.hankoSumi,
        foregroundColor: AppTheme.hankoWashi,
        title: Text('Import library',
            style: AppTheme.hankoSerif(fontSize: AppTheme.hankoFeaturedSize)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter - _PrintedSourceTile.ringRoom, 8,
            AppTheme.hankoGutter - _PrintedSourceTile.ringRoom, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            inset(Text('BRING YOUR LIST', style: label)),
            const SizedBox(height: 6),
            inset(Text('Choose a source', style: heading)),
            const SizedBox(height: 8),

            // Source options
            _PrintedSourceTile(
              label: 'MyAnimeList',
              tag: 'MAL',
              subtitle: 'Public profile, by username',
              selected: _selectedSource == ImportSource.mal,
              onTap: () => setState(() => _selectedSource = ImportSource.mal),
            ),
            const SizedBox(height: 2),
            _PrintedSourceTile(
              label: 'AniList',
              tag: 'AL',
              subtitle: 'Public profile, by username',
              selected: _selectedSource == ImportSource.anilist,
              onTap: () => setState(() => _selectedSource = ImportSource.anilist),
            ),
            const SizedBox(height: 2),
            _PrintedSourceTile(
              label: 'CSV file',
              tag: 'CSV',
              subtitle: 'Upload an exported file',
              selected: _selectedSource == ImportSource.csv,
              onTap: () => setState(() => _selectedSource = ImportSource.csv),
            ),

            const SizedBox(height: 20),

            // What we import, on a sumi 2 panel: no rules, no green ticks.
            inset(Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              decoration: const BoxDecoration(
                  color: AppTheme.hankoSumi2, borderRadius: corners),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WHAT WE’LL BRING ACROSS', style: label),
                  const SizedBox(height: 4),
                  for (final (what, how) in const [
                    ('List entries', 'ALL'),
                    ('Episode progress', 'SYNCED'),
                    ('Personal scores', 'PRESERVED'),
                    ('Notes & tags', 'MERGED'),
                  ])
                    _PrintedFeatureRow(what, how),
                ],
              ),
            )),

            const SizedBox(height: 24),

            if (!_isDone) ...[
              inset(Text(_usernameLabel, style: heading)),
              const SizedBox(height: 10),
              inset(TextField(
                controller: _usernameController,
                enabled: !_isLoading && _selectedSource != ImportSource.csv,
                style: AppTheme.hankoSans(),
                cursorColor: AppTheme.hankoWashi,
                decoration: InputDecoration(
                  hintText: _hintText,
                  hintStyle: AppTheme.hankoSans(color: AppTheme.hankoAsh),
                  filled: true,
                  fillColor: AppTheme.hankoSumi2,
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppTheme.hankoStone),
                  border: edge(AppTheme.hankoEdge),
                  enabledBorder: edge(AppTheme.hankoEdge),
                  disabledBorder: edge(AppTheme.hankoHairline),
                  focusedBorder: edge(AppTheme.hankoWashi, 1.5),
                ),
                onSubmitted: (_) => _isLoading ? null : _importList(),
              )),
              const SizedBox(height: 6),
              inset(Text('Profile must be set to public.',
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      color: AppTheme.hankoStone))),

              // An error says so in words, in the error colour (4.88:1 on
              // sumi 2), on a plain panel: no tinted box.
              if (_error != null) ...[
                const SizedBox(height: 16),
                inset(Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                      color: AppTheme.hankoSumi2, borderRadius: corners),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.error_outline_rounded,
                            color: AppTheme.error, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                color: AppTheme.error)),
                      ),
                    ],
                  ),
                )),
              ],

              // Progress: washi on sumi 3. With animations off, a count not
              // yet known shows an empty track instead of a sweeping one.
              if (_isLoading) ...[
                const SizedBox(height: 16),
                inset(Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: AppTheme.hankoSumi2, borderRadius: corners),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(_matching
                                    ? 'Matching with AniList…'
                                    : 'Importing…',
                                style: meta),
                          ),
                          const SizedBox(width: 12),
                          Text(_matching
                                  ? '$_lookedUp / $_total'
                                  : '$_imported / $_total',
                              style: AppTheme.hankoSans(
                                  fontSize: AppTheme.hankoMetaSize,
                                  weight: FontWeight.w600,
                                  tabular: true)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: corners,
                        child: LinearProgressIndicator(
                          value: _total > 0
                              ? (_matching ? _lookedUp : _imported) / _total
                              : (still ? 0 : null),
                          backgroundColor: AppTheme.hankoSumi3,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              AppTheme.hankoWashi),
                          minHeight: 3,
                        ),
                      ),
                      if (_currentAnime.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_currentAnime,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoLabelSize,
                                color: AppTheme.hankoAsh),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                )),
              ],

              const SizedBox(height: 20),
              inset(_PrintedMainAction(
                label: _isLoading ? 'Importing…' : 'Import library',
                icon: Icons.download_rounded,
                busy: _isLoading,
                onTap: _isLoading ? null : _importList,
              )),
              const SizedBox(height: 12),
              inset(Text(
                'Existing entries are merged, never overwritten.',
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    color: AppTheme.hankoStone),
                textAlign: TextAlign.center,
              )),
            ] else ...[
              // Done: said in words, washi and stone, not a green badge.
              inset(Text('DONE', style: label)),
              const SizedBox(height: 6),
              inset(Text('Import complete',
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoDisplaySize))),
              const SizedBox(height: 8),
              inset(Text('$_imported anime imported successfully',
                  style: AppTheme.hankoSans(color: AppTheme.hankoStone))),
              if (_unmatched.isNotEmpty) ...[
                const SizedBox(height: 16),
                inset(Text(
                    _unmatched.length == 1
                        ? '1 show couldn’t be matched on AniList, '
                            'so it wasn’t imported:'
                        : '${_unmatched.length} shows couldn’t be '
                            'matched on AniList, so they weren’t '
                            'imported:',
                    style: meta)),
                const SizedBox(height: 6),
                inset(Text(
                    _unmatched.length > 10
                        ? '${_unmatched.take(10).join(' · ')} '
                            '· and ${_unmatched.length - 10} more'
                        : _unmatched.join(' · '),
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        color: AppTheme.hankoAsh))),
              ],
              const SizedBox(height: 32),
              inset(_PrintedMainAction(
                label: 'Go to My List',
                onTap: () => Navigator.pop(context),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

/// A source to import from, in flat Hanko: a sumi 2 panel with 2 px corners,
/// keylined in washi and ticked when [selected], hairline otherwise (never
/// coral). One button for a screen reader and the keyboard, its focus shown
/// by a 2 px washi ring just outside the panel, in room it always keeps
/// ([ringRoom]), as hanko_board's printed tabs show theirs.
class _PrintedSourceTile extends StatefulWidget {
  final String label;
  final String tag;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PrintedSourceTile({
    required this.label,
    required this.tag,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  static const double ringRoom = 3;

  @override
  State<_PrintedSourceTile> createState() => _PrintedSourceTileState();
}

class _PrintedSourceTileState extends State<_PrintedSourceTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final selected = widget.selected;
    final corners = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${widget.label}, ${widget.subtitle}',
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused ? AppTheme.hankoWashi : const Color(0x00000000),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(
              AppTheme.hankoRadius + _PrintedSourceTile.ringRoom),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_PrintedSourceTile.ringRoom),
          // The panel is the Material, so the press wash paints over its
          // fill, and its keyline eases between hairline and washi.
          child: Material(
            color: AppTheme.hankoSumi2,
            animationDuration: duration,
            shape: RoundedRectangleBorder(
              borderRadius: corners,
              side: BorderSide(
                  color: selected
                      ? AppTheme.hankoWashi
                      : AppTheme.hankoHairline),
            ),
            child: InkWell(
              onTap: widget.onTap,
              onFocusChange: (v) => setState(() => _focused = v),
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              customBorder: RoundedRectangleBorder(borderRadius: corners),
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: AppTheme.hankoTouch),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.hankoSumi3,
                            borderRadius: corners,
                          ),
                          child: Text(widget.tag,
                              style: AppTheme.hankoSans(
                                  fontSize: AppTheme.hankoLabelSize,
                                  weight: FontWeight.w600,
                                  color: selected
                                      ? AppTheme.hankoWashi
                                      : AppTheme.hankoStone,
                                  letterSpacing: 0.6,
                                  tabular: true)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.label,
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoListTitleSize,
                                      weight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(widget.subtitle,
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoMetaSize,
                                      color: AppTheme.hankoStone)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedContainer(
                          duration: duration,
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.hankoWashi
                                : const Color(0x00000000),
                            borderRadius: corners,
                            border: Border.all(
                              color: selected
                                  ? AppTheme.hankoWashi
                                  : AppTheme.hankoEdge,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded,
                                  color: AppTheme.hankoSumi, size: 14)
                              : null,
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

/// One line of "What we'll bring across" in flat Hanko: a stone tick, the
/// thing in washi and how it comes across as a printed label in stone.
class _PrintedFeatureRow extends StatelessWidget {
  final String label;
  final String value;
  const _PrintedFeatureRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, color: AppTheme.hankoStone, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AppTheme.hankoSans())),
          const SizedBox(width: 8),
          Text(value, style: HankoBoard.labelStyle(color: AppTheme.hankoStone)),
        ],
      ),
    );
  }
}

/// The screen's one main action, as Detail's: a washi tile with sumi words
/// (15.34:1), 2 px corners, pressed with an 8% wash and no ripple, its own
/// button node with the InkWell's tap and focus in it. While [busy] it rests
/// on sumi 3 with stone words (6.4:1) and, with animations on, a stone
/// spinner in place of its icon.
class _PrintedMainAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;

  const _PrintedMainAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final ink = busy ? AppTheme.hankoStone : AppTheme.hankoSumi;
    final icon = this.icon;
    final corners = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: busy ? AppTheme.hankoSumi3 : AppTheme.hankoWashi,
        borderRadius: corners,
        child: InkWell(
          onTap: onTap,
          borderRadius: corners,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          focusColor: AppTheme.hankoSumi.withValues(alpha: 0.12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: double.infinity, minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy && !still) ...[
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ink),
                    ),
                    const SizedBox(width: 8),
                  ] else if (!busy && icon != null) ...[
                    Icon(icon, size: 20, color: ink),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoBodySize,
                            weight: FontWeight.w600,
                            color: ink)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String label;
  final String tag;
  final Color tagColor;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    required this.label,
    required this.tag,
    required this.tagColor,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceMid : AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(tag,
                      style: AppTheme.mono(
                          fontSize: 13,
                          weight: FontWeight.w700,
                          color: tagColor)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: AppTheme.sans(
                            fontSize: 15, weight: FontWeight.w600)),
                    Text(subtitle,
                        style: AppTheme.mono(
                            fontSize: 10, color: AppTheme.textMuted,
                            letterSpacing: 0.8)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppTheme.primary : Colors.transparent,
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.border,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportFeatureRow extends StatelessWidget {
  final String label;
  final String value;
  const _ImportFeatureRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_rounded, color: AppTheme.success, size: 16),
        const SizedBox(width: 10),
        Expanded(
            child: Text(label,
                style: AppTheme.sans(fontSize: 14))),
        Text(value,
            style: AppTheme.mono(
                fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.8)),
      ],
    );
  }
}
