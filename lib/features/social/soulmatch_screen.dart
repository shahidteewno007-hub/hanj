import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Soulmatch Screen
// ─────────────────────────────────────────────────────────────

class SoulmatchScreen extends StatefulWidget {
  const SoulmatchScreen({super.key});

  @override
  State<SoulmatchScreen> createState() => _SoulmatchScreenState();
}

class _SoulmatchScreenState extends State<SoulmatchScreen> {
  final _codeCtrl = TextEditingController();
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  SoulmatchResult? _result;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _myCode {
    if (_uid == null) return '';
    final raw = _uid!.replaceAll('-', '').toUpperCase();
    return raw.length >= 8 ? raw.substring(0, 8) : raw.padRight(8, '0');
  }

  Future<void> _match() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a friend\'s code');
      return;
    }
    if (code == _myCode) {
      setState(() => _error = 'That\'s your own code!');
      return;
    }

    setState(() { _isLoading = true; _error = null; _result = null; });

    try {
      // Find friend by share code
      final usersSnap = await FirebaseFirestore.instance
          .collection('users').get();

      String? friendUid;
      String? friendName;

      for (final doc in usersSnap.docs) {
        final uid = doc.id;
        final raw = uid.replaceAll('-', '').toUpperCase();
        final friendCode = raw.length >= 8 ? raw.substring(0, 8) : raw.padRight(8, '0');
        if (friendCode == code) {
          friendUid = uid;
          friendName = doc.data()['displayName'] as String? ?? 'Anonymous';
          break;
        }
      }

      if (friendUid == null) {
        setState(() { _error = 'No user found with that code'; _isLoading = false; });
        return;
      }

      // Load both lists
      final mySnap = await FirebaseFirestore.instance
          .collection('users').doc(_uid).collection('animeList').get();
      final friendSnap = await FirebaseFirestore.instance
          .collection('users').doc(friendUid).collection('animeList').get();

      final result = SoulmatchAnalyzer.analyze(
        myDocs: mySnap.docs,
        friendDocs: friendSnap.docs,
        friendName: friendName!,
      );

      setState(() { _result = result; _isLoading = false; });
    } catch (e) {
      setState(() { _error = 'Something went wrong. Try again.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Soulmatch 🪞',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    AppTheme.surfaceMid,
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Find Your Anime Soulmate',
                      style: AppTheme.serif(
                          fontSize: 22, weight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(
                    'Enter a friend\'s share code to see how compatible your anime taste is.',
                    style: AppTheme.sans(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  // My code
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        Text('YOUR CODE: ',
                            style: AppTheme.mono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                                letterSpacing: 1)),
                        Text(_myCode,
                            style: AppTheme.mono(
                                fontSize: 14,
                                color: AppTheme.primary,
                                letterSpacing: 3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Input
            Text('Friend\'s Code',
                style: AppTheme.sans(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    style: AppTheme.mono(fontSize: 16, letterSpacing: 3),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    decoration: InputDecoration(
                      hintText: 'XXXXXXXX',
                      hintStyle: AppTheme.mono(
                          fontSize: 16,
                          color: AppTheme.textMuted,
                          letterSpacing: 3),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _match,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(80, 52),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Match'),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: AppTheme.sans(
                      color: AppTheme.error, fontSize: 13)),
            ],

            if (_result != null) ...[
              const SizedBox(height: 32),
              _SoulmatchResultCard(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Soulmatch Analyzer
// ─────────────────────────────────────────────────────────────

class SoulmatchAnalyzer {
  static SoulmatchResult analyze({
    required List<QueryDocumentSnapshot> myDocs,
    required List<QueryDocumentSnapshot> friendDocs,
    required String friendName,
  }) {
    final myMap = {
      for (final d in myDocs)
        (d.data() as Map<String, dynamic>)['animeId']?.toString() ?? '':
            d.data() as Map<String, dynamic>
    };
    final friendMap = {
      for (final d in friendDocs)
        (d.data() as Map<String, dynamic>)['animeId']?.toString() ?? '':
            d.data() as Map<String, dynamic>
    };

    // Shared anime
    final sharedIds = myMap.keys
        .where((id) => friendMap.containsKey(id) && id.isNotEmpty)
        .toList();

    // Genre overlap
    final myGenres    = _collectGenres(myMap.values.toList());
    final friendGenres = _collectGenres(friendMap.values.toList());
    final sharedGenres = myGenres.keys
        .where((g) => friendGenres.containsKey(g))
        .toList();

    // Rating similarity on shared anime
    double ratingScore = 0;
    int ratingCount = 0;
    for (final id in sharedIds) {
      final myR = (myMap[id]?['userRating'] as num?)?.toDouble();
      final frR = (friendMap[id]?['userRating'] as num?)?.toDouble();
      if (myR != null && frR != null) {
        final diff = (myR - frR).abs();
        ratingScore += (1 - diff / 10);
        ratingCount++;
      }
    }
    final avgRatingMatch = ratingCount > 0 ? ratingScore / ratingCount : 0.5;

    // Compute score
    final total = (myMap.length + friendMap.length) / 2;
    final overlapScore  = total > 0 ? sharedIds.length / total : 0.0;
    final genreScore    = myGenres.length > 0
        ? sharedGenres.length / myGenres.length
        : 0.0;
    final compatibility = ((overlapScore * 0.4 +
            genreScore * 0.4 +
            avgRatingMatch * 0.2) *
        100)
        .round()
        .clamp(5, 99);

    // Shared anime details
    final sharedAnime = sharedIds.take(6).map((id) => {
      'title': myMap[id]?['title'] as String? ?? 'Unknown',
      'imageUrl': myMap[id]?['imageUrl'] as String?,
    }).toList();

    // Disagreements (both watched but different status)
    final disagreements = sharedIds.where((id) {
      final myStatus = myMap[id]?['status'] as String?;
      final frStatus = friendMap[id]?['status'] as String?;
      return myStatus != frStatus;
    }).take(3).map((id) => myMap[id]?['title'] as String? ?? '').toList();

    // Unique recommendations (friend completed, I haven't watched)
    final recommendations = friendMap.keys
        .where((id) =>
            !myMap.containsKey(id) &&
            friendMap[id]?['status'] == 'COMPLETED')
        .take(4)
        .map((id) => {
              'title': friendMap[id]?['title'] as String? ?? '',
              'imageUrl': friendMap[id]?['imageUrl'] as String?,
            })
        .toList();

    return SoulmatchResult(
      friendName:      friendName,
      compatibility:   compatibility,
      sharedCount:     sharedIds.length,
      myTotal:         myMap.length,
      friendTotal:     friendMap.length,
      sharedGenres:    sharedGenres.take(5).toList(),
      sharedAnime:     sharedAnime,
      disagreements:   disagreements,
      recommendations: recommendations,
    );
  }

  static Map<String, int> _collectGenres(List<Map<String, dynamic>> docs) {
    final map = <String, int>{};
    for (final d in docs) {
      final genres = (d['genres'] as List<dynamic>?)?.cast<String>() ?? [];
      for (final g in genres) map[g] = (map[g] ?? 0) + 1;
    }
    return map;
  }
}

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────

class SoulmatchResult {
  final String friendName;
  final int compatibility;
  final int sharedCount;
  final int myTotal;
  final int friendTotal;
  final List<String> sharedGenres;
  final List<Map<String, dynamic>> sharedAnime;
  final List<String> disagreements;
  final List<Map<String, dynamic>> recommendations;

  const SoulmatchResult({
    required this.friendName,
    required this.compatibility,
    required this.sharedCount,
    required this.myTotal,
    required this.friendTotal,
    required this.sharedGenres,
    required this.sharedAnime,
    required this.disagreements,
    required this.recommendations,
  });
}

// ─────────────────────────────────────────────────────────────
// Result Card
// ─────────────────────────────────────────────────────────────

class _SoulmatchResultCard extends StatelessWidget {
  final SoulmatchResult result;
  const _SoulmatchResultCard({required this.result});

  Color get _scoreColor {
    if (result.compatibility >= 80) return const Color(0xFF4A9B6F);
    if (result.compatibility >= 60) return AppTheme.primary;
    if (result.compatibility >= 40) return AppTheme.accent;
    return AppTheme.error;
  }

  String get _scoreLabel {
    if (result.compatibility >= 90) return 'Soulmates 🔥';
    if (result.compatibility >= 75) return 'Great Match ✨';
    if (result.compatibility >= 60) return 'Compatible 👍';
    if (result.compatibility >= 40) return 'Some Overlap 🤝';
    return 'Different Tastes 💀';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Score card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _scoreColor.withValues(alpha: 0.2),
                AppTheme.surfaceMid,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: _scoreColor.withValues(alpha: 0.4)),
          ),
          child: Column(
            children: [
              Text(
                '${result.compatibility}%',
                style: TextStyle(
                  color: _scoreColor,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(height: 8),
              Text(_scoreLabel,
                  style: AppTheme.serif(
                      fontSize: 20, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'You and ${result.friendName} are ${result.compatibility}% compatible',
                style: AppTheme.sans(
                    color: AppTheme.textSecondary,
                    fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _StatPill('${result.sharedCount}', 'in common'),
                  _StatPill('${result.myTotal}', 'your list'),
                  _StatPill('${result.friendTotal}', 'their list'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Shared genres
        if (result.sharedGenres.isNotEmpty) ...[
          Text('Shared Taste',
              style: AppTheme.serif(
                  fontSize: 16, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: result.sharedGenres.map((g) => Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(g,
                  style: AppTheme.sans(
                      fontSize: 12,
                      color: AppTheme.primary,
                      weight: FontWeight.w500)),
            )).toList(),
          ),
          const SizedBox(height: 20),
        ],

        // Shared anime
        if (result.sharedAnime.isNotEmpty) ...[
          Text('Both Watched',
              style: AppTheme.serif(
                  fontSize: 16, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: result.sharedAnime.length,
              itemBuilder: (_, i) {
                final anime = result.sharedAnime[i];
                return Container(
                  width: 66,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: anime['imageUrl'] != null
                            ? Image.network(
                                anime['imageUrl']!,
                                width: 66,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(
                                        width: 66,
                                        height: 80,
                                        color: AppTheme.surfaceLight),
                              )
                            : Container(
                                width: 66,
                                height: 80,
                                color: AppTheme.surfaceLight),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Disagreements
        if (result.disagreements.isNotEmpty) ...[
          Text('You Disagree On',
              style: AppTheme.serif(
                  fontSize: 16, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...result.disagreements.map((title) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Text('⚔️', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: AppTheme.sans(
                          fontSize: 13,
                          color: AppTheme.textSecondary)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 20),
        ],

        // Recommendations from friend
        if (result.recommendations.isNotEmpty) ...[
          Text('Watch From Their List',
              style: AppTheme.serif(
                  fontSize: 16, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${result.friendName} completed these — you haven\'t seen them yet',
            style: AppTheme.sans(
                color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: result.recommendations.length,
              itemBuilder: (_, i) {
                final anime = result.recommendations[i];
                return Container(
                  width: 80,
                  margin: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: anime['imageUrl'] != null
                            ? Image.network(
                                anime['imageUrl']!,
                                width: 80,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    Container(
                                        width: 80,
                                        height: 100,
                                        color: AppTheme.surfaceLight),
                              )
                            : Container(
                                width: 80,
                                height: 100,
                                color: AppTheme.surfaceLight),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        anime['title'] as String? ?? '',
                        style: AppTheme.sans(fontSize: 10),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  const _StatPill(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTheme.sans(
                fontSize: 20,
                weight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        Text(label,
            style: AppTheme.mono(
                fontSize: 9, color: AppTheme.textMuted, letterSpacing: 0.5)),
      ],
    );
  }
}
