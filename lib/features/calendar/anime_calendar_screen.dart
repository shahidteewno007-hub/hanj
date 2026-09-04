import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';

class AnimeCalendarScreen extends StatefulWidget {
  const AnimeCalendarScreen({super.key});

  @override
  State<AnimeCalendarScreen> createState() => _AnimeCalendarScreenState();
}

class _AnimeCalendarScreenState extends State<AnimeCalendarScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _scheduleByDay = {};
  final Set<String> _remindersOn = {}; // animeId strings

  static const _days = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY'
  ];

  static const _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  int _selectedDay = DateTime.now().weekday - 1; // 0=Mon

  @override
  void initState() {
    super.initState();
    _loadSchedule();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts')
        .get();
    if (mounted) {
      setState(() => _remindersOn.addAll(snap.docs.map((d) => d.id)));
    }
  }

  Future<void> _toggleReminder(String animeId, String title, int episode, bool newVal) async {
    setState(() {
      if (newVal) _remindersOn.add(animeId); else _remindersOn.remove(animeId);
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts').doc(animeId);
    if (newVal) {
      await ref.set({
        'animeId': animeId,
        'title': title,
        'episode': episode,
        'addedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    try {
      // Get user's watching list
      final snapshot =
          await _firestoreService.getAnimeByStatus('WATCHING').first;
      final watchingIds = snapshot.docs
          .map((d) => (d.data() as Map)['animeId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (watchingIds.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch airing schedule from AniList
      const query = r'''
      query ($page: Int) {
        Page(page: $page, perPage: 50) {
          airingSchedules(notYetAired: true, sort: TIME) {
            airingAt
            episode
            media {
              id
              title { romaji english }
              coverImage { medium }
              averageScore
              genres
              episodes
            }
          }
        }
      }
      ''';

      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': query, 'variables': {'page': 1}}),
      );

      if (response.statusCode != 200) throw Exception('Failed');

      final data = jsonDecode(response.body);
      final schedules =
          data['data']['Page']['airingSchedules'] as List;

      // Filter to only user's watching list + group by day
      final Map<String, List<Map<String, dynamic>>> byDay = {};
      for (final day in _days) {
        byDay[day] = [];
      }

      for (final schedule in schedules) {
        final mediaId = schedule['media']['id'].toString();
        if (!watchingIds.contains(mediaId)) continue;

        final airingAt =
            DateTime.fromMillisecondsSinceEpoch(schedule['airingAt'] * 1000);
        final dayIndex = airingAt.weekday - 1; // 0=Mon
        final dayKey = _days[dayIndex];

        byDay[dayKey]!.add({
          'media': schedule['media'],
          'episode': schedule['episode'],
          'airingAt': airingAt,
        });
      }

      // If watching list has items but none are in the schedule,
      // show all currently airing anime as fallback
      final hasAny = byDay.values.any((list) => list.isNotEmpty);
      if (!hasAny) {
        // Fallback: show all from schedule grouped by day
        for (final schedule in schedules.take(50)) {
          final airingAt = DateTime.fromMillisecondsSinceEpoch(
              schedule['airingAt'] * 1000);
          final dayIndex = airingAt.weekday - 1;
          final dayKey = _days[dayIndex];
          byDay[dayKey]!.add({
            'media': schedule['media'],
            'episode': schedule['episode'],
            'airingAt': airingAt,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _scheduleByDay = byDay;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anime Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSchedule,
          ),
        ],
      ),
      body: Column(
        children: [
          // Day selector
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: AppTheme.surface,
            child: Row(
              children: List.generate(7, (i) {
                final isSelected = _selectedDay == i;
                final isToday = today == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDay = i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(
                              _dayLabels[i],
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppTheme.textMuted,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (_scheduleByDay[_days[i]]?.isNotEmpty == true)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Schedule list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildDaySchedule(),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule() {
    final dayKey = _days[_selectedDay];
    final items = _scheduleByDay[dayKey] ?? [];

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📅', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 20),
            const Text(
              'No episodes today',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Check other days or add more\nanime to your watching list',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final media = item['media'] as Map<String, dynamic>;
        final episode = item['episode'] as int;
        final airingAt = item['airingAt'] as DateTime;
        final title = media['title']['english'] ??
            media['title']['romaji'] ?? 'Unknown';
        final imageUrl = media['coverImage']['medium'] as String?;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              final anime = Anime(
                id: media['id'].toString(),
                title: media['title']['romaji'] ?? 'Unknown',
                titleEnglish: media['title']['english'],
                imageUrl: imageUrl,
                averageScore: (media['averageScore'] as num?)?.toDouble(),
                genres: media['genres'] != null
                    ? List<String>.from(media['genres'])
                    : [],
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AnimeDetailScreen(anime: anime)),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  // Poster
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        width: 52,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 52,
                          height: 72,
                          color: AppTheme.surface,
                        ),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'Ep $episode',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(airingAt),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Builder(builder: (ctx) {
                    final mediaId = media['id'].toString();
                    final isOn = _remindersOn.contains(mediaId);
                    return GestureDetector(
                      onTap: () {
                        final newVal = !isOn;
                        _toggleReminder(mediaId, title, episode, newVal);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(newVal
                              ? 'Reminder set for $title Ep $episode'
                              : 'Reminder removed for $title Ep $episode'),
                          backgroundColor: const Color(0xFF1A1612),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppTheme.primary, width: 1),
                          ),
                          duration: const Duration(seconds: 2),
                        ));
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: isOn ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary.withValues(alpha: isOn ? 1.0 : 0.3)),
                          boxShadow: isOn ? [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.4), blurRadius: 8)] : [],
                        ),
                        child: Icon(
                          isOn ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                          color: isOn ? Colors.white : AppTheme.primary,
                          size: 16,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}
