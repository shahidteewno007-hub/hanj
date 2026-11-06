import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/responsive.dart';
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
    // Pressing Match clears the last match first (question 107): a Match
    // that failed one of these checks set its message but left the
    // previous friend's match on screen under it, as if it still applied.
    // The checks that reach the network already cleared it.
    if (code.isEmpty) {
      setState(() { _error = 'Enter a friend\'s code'; _result = null; });
      return;
    }
    if (code == _myCode) {
      setState(() { _error = 'That\'s your own code!'; _result = null; });
      return;
    }

    setState(() { _isLoading = true; _error = null; _result = null; });

    try {
      // Find friend by share code
      final usersSnap = await FirebaseFirestore.instance
          .collection('users').get();
      if (!mounted) return;

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
      if (!mounted) return;

      final result = SoulmatchAnalyzer.analyze(
        myDocs: mySnap.docs,
        friendDocs: friendSnap.docs,
        friendName: friendName!,
      );

      setState(() { _result = result; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Something went wrong. Try again.'; _isLoading = false; });
    }
  }

  /// Soulmatch before Hanko (question 100): a coral gradient header with
  /// your code in coral, the theme's coral Match pill, the score on a
  /// gradient card in one of four colours by range, emoji in the title and
  /// the verdicts, coral genre pills and ⚔️ rows. Kept switched off as
  /// design history; _buildPreHanko() holds it.
  static const bool _preHanko = false;

  /// Soulmatch in Hanko (question 100), one page in Profile's grammar: what
  /// it does in a Shippori line, your code, a friend's code, and Match as
  /// the page's one washi action. A match follows below the screen's one
  /// hairline as a record: the percentage in Shippori, its verdict in
  /// words, the sentence that names your friend, the three counts, then
  /// what you share, what is on both lists, where your lists differ and
  /// what to watch from theirs, each under a Shippori head, with space
  /// between and no boxes.
  ///
  /// Gone: the gradients, the emoji, the coral code and pills, and the
  /// score's four colours (green, coral, gold, pink), since the verdict's
  /// words already say how close you are. One meaning per colour: coral is
  /// only your seal, your verdict on a show, and nothing here is one, so
  /// nothing here is coral. Its reads, its states and its taps are as before.
  @override
  Widget build(BuildContext context) {
    if (_preHanko) return _buildPreHanko();
    final code = _myCode;
    final error = _error;
    final result = _result;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_sharp, color: AppTheme.hankoWashi),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Soulmatch', style: AppTheme.hankoSerif(fontSize: 20)),
      ),
      // The page scrolls at full width, so a wheel anywhere moves it; on a
      // wide window its column keeps Profile's 440 and hangs on the left.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 48),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: Responsive.proseMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Find your anime soulmate',
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoFeaturedSize, height: 1.25)),
                const SizedBox(height: 8),
                Text(
                  'Enter a friend\'s share code to see how compatible your '
                  'anime taste\u00A0is.',
                  style: AppTheme.hankoSans(
                      color: AppTheme.hankoStone, height: 1.5),
                ),
                if (code.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _HankoYourCode(code),
                ],
                const SizedBox(height: 28),
                Text('Friend\'s code',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        color: AppTheme.hankoStone,
                        height: 1.3)),
                const SizedBox(height: 8),
                _hankoCodeField(),
                // The form's message, in washi words: what went wrong is in
                // the words, not in a colour. Announced when it appears.
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(_sentence(error),
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize, height: 1.4)),
                  ),
                ],
                const SizedBox(height: 16),
                _HankoMatchButton(
                    loading: _isLoading, onTap: _isLoading ? null : _match),
                if (result != null) ...[
                  const SizedBox(height: 32),
                  const ColoredBox(
                    color: AppTheme.hankoHairline,
                    child: SizedBox(height: 1, width: double.infinity),
                  ),
                  const SizedBox(height: 24),
                  _HankoResult(result: result),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The friend's code field in Hanko: Jost 500 at 20 with tabular figures
  /// and Social's spacing, on sumi 2 inside a 1 px edge outline (4.0:1 on
  /// sumi, so the field stands out at AA's 3:1 for controls), washi at 2 px
  /// while you type in it, 2 px corners. The coral focus ring and cursor are
  /// gone: coral is only your seal. The placeholder is ash, 5.0:1 on sumi 2.
  Widget _hankoCodeField() {
    OutlineInputBorder outline(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          borderSide: BorderSide(color: color, width: width),
        );
    final codeStyle = AppTheme.hankoSans(
        fontSize: 20,
        weight: FontWeight.w500,
        letterSpacing: 3,
        tabular: true);
    return TextField(
      controller: _codeCtrl,
      style: codeStyle,
      cursorColor: AppTheme.hankoWashi,
      textCapitalization: TextCapitalization.characters,
      maxLength: 8,
      decoration: InputDecoration(
        hintText: 'XXXXXXXX',
        hintStyle: codeStyle.copyWith(color: AppTheme.hankoAsh),
        counterText: '',
        filled: true,
        fillColor: AppTheme.hankoSumi2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: outline(AppTheme.hankoEdge, 1),
        enabledBorder: outline(AppTheme.hankoEdge, 1),
        focusedBorder: outline(AppTheme.hankoWashi, 2),
      ),
    );
  }

  /// _match()'s messages as Hanko writes a sentence: a full stop at the
  /// end, never "!". The messages themselves are unchanged.
  static String _sentence(String message) {
    final m = message.trimRight();
    if (m.endsWith('!')) return '${m.substring(0, m.length - 1)}.';
    return m.endsWith('.') ? m : '$m.';
  }

  /// The screen before Hanko (_preHanko).
  Widget _buildPreHanko() {
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

/// Whether a stored rating lands on Hanj's 1–10 scale at its nearest half
/// step, as the seal register places it (Profile's rule, stage H5; the same
/// test as taste_profile.dart's, which is private to that file).
bool _onScale(double rating) {
  final step = (rating * 2).round() / 2;
  return step >= 1 && step <= 10;
}

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

    // Rating similarity on shared anime. Only pairs where both ratings are
    // on Hanj's 1–10 scale count (question 105), as in Ranking Cards and the
    // Taste analysis (question 96): an imported rating on another scale
    // (D20: a 70 from a 100-point list) against a 7 counted as 63 points
    // apart, which pulled the whole match down. A pair with one is left out.
    double ratingScore = 0;
    int ratingCount = 0;
    for (final id in sharedIds) {
      final myR = (myMap[id]?['userRating'] as num?)?.toDouble();
      final frR = (friendMap[id]?['userRating'] as num?)?.toDouble();
      if (myR != null && frR != null && _onScale(myR) && _onScale(frR)) {
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
              // Hanko's numerals (question 136): Jost tabular at its
              // heaviest shipped weight, through AppTheme.mono(), in place
              // of a 'SpaceGrotesk' family literal that no font was ever
              // registered under. This card is drawn only by the pre-Hanko
              // screen (_preHanko).
              Text(
                '${result.compatibility}%',
                style: AppTheme.mono(
                  fontSize: 72,
                  weight: FontWeight.w600,
                  color: _scoreColor,
                  letterSpacing: 0,
                ).copyWith(height: 1),
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

// ─────────────────────────────────────────────────────────────
// Soulmatch in Hanko (question 100)
// ─────────────────────────────────────────────────────────────

/// Your own code, for a friend to type: "Your code" in Jost 13 stone, then
/// the code in Jost 500 washi with tabular figures, in Social's two groups of
/// four. It was coral; coral is only your seal now. A screen reader hears it
/// a character at a time, as on Social.
class _HankoYourCode extends StatelessWidget {
  const _HankoYourCode(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final safe = code.padRight(8, '0');
    return Semantics(
      label: 'Your share code: ${safe.split('').join(' ')}',
      excludeSemantics: true,
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Your code',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoStone,
                  height: 1.3)),
          Text('${safe.substring(0, 4)} ${safe.substring(4, 8)}',
              style: AppTheme.hankoSans(
                  fontSize: 17,
                  weight: FontWeight.w500,
                  letterSpacing: 2,
                  height: 1.2,
                  tabular: true)),
        ],
      ),
    );
  }
}

/// Match, the page's one main action as Hanko draws it (Social's Copy code):
/// a washi tile with sumi words, 15.34:1, 2 px corners, at least 48 px,
/// pressed with a sumi wash and no ripple. It was the theme's coral pill.
/// While a match is worked out, a sumi spinner takes its icon's place and
/// taps are ignored, as before.
///
/// Its own semantics node (container), named by its word, with the InkWell's
/// tap and focus inside it, as Profile's Retry tile (dd45bd1). Not a label
/// over excluded semantics: that node could be tapped but not focused, so on
/// the web a Match that showed an error left the code field focused for the
/// app but not for the browser, and what you typed next never arrived.
class _HankoMatchButton extends StatelessWidget {
  const _HankoMatchButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          hoverColor: AppTheme.hankoSumi.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: AppTheme.hankoTouch,
                minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(
                                color: AppTheme.hankoSumi, strokeWidth: 2),
                          )
                        : const Icon(Icons.join_inner_sharp,
                            size: 20, color: AppTheme.hankoSumi),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Match',
                      style: AppTheme.hankoSans(
                        fontSize: 15,
                        weight: FontWeight.w600,
                        color: AppTheme.hankoSumi,
                        height: 1.2,
                      ),
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
}

/// A match as a record. Washi and stone on sumi throughout (15.3:1 and
/// 6.9:1): the old card coloured the score green, coral, gold or pink by
/// range, and its verdicts carried emoji; here the verdict's words say it.
class _HankoResult extends StatelessWidget {
  const _HankoResult({required this.result});

  final SoulmatchResult result;

  /// The verdict, on the same thresholds as the old card's _scoreLabel, in
  /// sentence case and without its emoji.
  String get _verdict {
    final c = result.compatibility;
    if (c >= 90) return 'Soulmates';
    if (c >= 75) return 'Great match';
    if (c >= 60) return 'Compatible';
    if (c >= 40) return 'Some overlap';
    return 'Different tastes';
  }

  @override
  Widget build(BuildContext context) {
    final quiet = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize,
        color: AppTheme.hankoStone,
        height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${result.compatibility}%',
            style: AppTheme.hankoSerif(fontSize: 56, height: 1.05)),
        const SizedBox(height: 6),
        Text(_verdict,
            style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoLedeSize, height: 1.2)),
        const SizedBox(height: 8),
        // Announced when a match arrives.
        Semantics(
          liveRegion: true,
          child: Text(
              'You and ${result.friendName} are '
              '${result.compatibility}%\u00A0compatible.',
              style: AppTheme.hankoSans(
                  color: AppTheme.hankoStone, height: 1.5)),
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _HankoFigure('${result.sharedCount}', 'in common')),
            Expanded(
                child: _HankoFigure('${result.myTotal}', 'on your list')),
            Expanded(
                child:
                    _HankoFigure('${result.friendTotal}', 'on their list')),
          ],
        ),
        if (result.sharedGenres.isNotEmpty) ...[
          const SizedBox(height: 32),
          const _HankoHead('Shared taste'),
          // A genre's own words never part, and each dot stays with the
          // genre before it, as on the Taste Card.
          Text(
              result.sharedGenres
                  .map((g) => g.replaceAll(' ', '\u00A0'))
                  .join('\u00A0· '),
              style: AppTheme.hankoSans(height: 1.5)),
        ],
        if (result.sharedAnime.isNotEmpty) ...[
          const SizedBox(height: 32),
          // "On both lists", not "Both watched" (question 106): the shows
          // are every title on both lists, so a show you both only plan
          // to watch is among them.
          const _HankoHead('On both lists'),
          _HankoCovers(items: result.sharedAnime),
        ],
        if (result.disagreements.isNotEmpty) ...[
          const SizedBox(height: 32),
          const _HankoHead('You disagree on'),
          Text('On both lists, with a different status on\u00A0each.',
              style: quiet),
          const SizedBox(height: 10),
          for (final title in result.disagreements)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title,
                  style: AppTheme.hankoSans(fontSize: 15, height: 1.3)),
            ),
        ],
        if (result.recommendations.isNotEmpty) ...[
          const SizedBox(height: 32),
          const _HankoHead('Watch from their list'),
          Text(
              '${result.friendName} completed these. You haven’t seen '
              'them\u00A0yet.',
              style: quiet),
          const SizedBox(height: 12),
          _HankoCovers(items: result.recommendations),
        ],
      ],
    );
  }
}

/// A section head as the Taste page's: Shippori 16 in washi.
class _HankoHead extends StatelessWidget {
  const _HankoHead(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(title,
            style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoSectionSize, height: 1.3)),
      ),
    );
  }
}

/// A figure, as the Taste page's: the number in Shippori 22, washi, over
/// its words in Jost 12, stone. No pill.
class _HankoFigure extends StatelessWidget {
  const _HankoFigure(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.hankoSerif(fontSize: 22, height: 1.15)),
          const SizedBox(height: 4),
          Text(label,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: AppTheme.hankoStone,
                  height: 1.3)),
        ],
      ),
    );
  }
}

/// Shows as covers with their titles under them, four to a row on a phone
/// (fewer as text grows), all in view: the old rows scrolled sideways, which hid
/// most of them on a phone and can't be scrolled with a mouse wheel, and
/// "Both watched" gave no titles at all. Covers at AniList's own 230 : 325,
/// with Hanko's 2 px corners on sumi 3, which also shows while one loads or
/// when it can't; no words on the art. Each title in Jost 12 washi, up to
/// two lines, and the cover is left out of the semantics tree, since the
/// title names the show.
class _HankoCovers extends StatelessWidget {
  const _HankoCovers({required this.items});

  final List<Map<String, dynamic>> items;

  static const double _gap = 10;

  /// The titles' size before the reader's text scale.
  static const double _titleSize = AppTheme.hankoLabelSize;

  @override
  Widget build(BuildContext context) {
    // As many to a row as leave each title room for its words at the
    // reader's text size: four on a phone at 1.0x, three at 1.3x, two at
    // 2.0x. Four at 1.3x broke "Steins;Gate" inside the word.
    final scale = MediaQuery.textScalerOf(context).scale(_titleSize) /
        _titleSize;
    return LayoutBuilder(builder: (context, constraints) {
      final room = constraints.maxWidth / scale;
      final perRow = room >= 300 ? 4 : room >= 200 ? 3 : 2;
      final width = (constraints.maxWidth - (perRow - 1) * _gap) / perRow;
      final height = width * 325 / 230;
      return Wrap(
        spacing: _gap,
        runSpacing: 16,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTheme.hankoRadius),
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: ColoredBox(
                          color: AppTheme.hankoSumi3,
                          child: _cover(item['imageUrl'] as String?),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['title'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.hankoSans(
                        fontSize: _titleSize, height: 1.25),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  static Widget _cover(String? url) => url == null || url.isEmpty
      ? const SizedBox.expand()
      : CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => const SizedBox.expand(),
        );
}
