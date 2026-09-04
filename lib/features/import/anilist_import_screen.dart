import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/firestore_service.dart';

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
            status score progress
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

    final response = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode({'query': query, 'variables': {'username': username}}),
    );

    if (response.statusCode != 200) throw Exception('Failed to connect to AniList.');
    final data = jsonDecode(response.body);
    if (data['errors'] != null) throw Exception('User not found on AniList.');

    final lists = data['data']['MediaListCollection']['lists'] as List;
    int total = 0;
    for (final l in lists) total += (l['entries'] as List).length;
    if (mounted) setState(() => _total = total);

    for (final list in lists) {
      for (final entry in list['entries'] as List) {
        final media = entry['media'];
        if (mounted) setState(() => _currentAnime =
            media['title']['english'] ?? media['title']['romaji'] ?? '');

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
          rating: (entry['score'] as num?) != null &&
                  (entry['score'] as num) > 0
              ? (entry['score'] as num).toDouble() : null,
          currentEpisode: entry['progress'] as int?,
        );
        if (mounted) setState(() => _imported++);
      }
    }
    if (mounted) setState(() { _isLoading = false; _isDone = true; });
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
    if (mounted) setState(() => _total = entries.length);

    for (final entry in entries) {
      final node = entry['node'] as Map<String, dynamic>;
      final listStatus = entry['list_status'] as Map<String, dynamic>;
      final title = node['title'] as String? ?? 'Unknown';

      if (mounted) setState(() => _currentAnime = title);

      // Get cover image
      final mainPicture = node['main_picture'] as Map<String, dynamic>?;
      final imageUrl = mainPicture?['large'] as String? ??
          mainPicture?['medium'] as String?;

      // Map genres
      final genreList = node['genres'] as List?;
      final genres = genreList
              ?.map((g) => (g as Map)['name'] as String)
              .toList() ??
          [];

      await _firestoreService.addAnimeToList(
        anime: Anime(
          id: node['id'].toString(),
          title: title,
          imageUrl: imageUrl,
          episodes: node['num_episodes'] as int?,
          averageScore: node['mean'] != null
              ? (node['mean'] as num).toDouble() * 10 : null,
          genres: genres,
          format: node['media_type'] as String?,
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
                          Text('Importing...',
                              style: AppTheme.sans(
                                  fontSize: 13, color: AppTheme.textSecondary)),
                          Text('$_imported / $_total',
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
                          value: _total > 0 ? _imported / _total : null,
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
