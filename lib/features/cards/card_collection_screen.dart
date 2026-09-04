import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'hanj_card.dart' as hc;
import 'card_share.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum CardRarity { common, rare, epic, legendary, seasonal, secret }

extension CardRarityX on CardRarity {
  String get label {
    switch (this) {
      case CardRarity.common:    return 'COMMON';
      case CardRarity.rare:      return 'RARE';
      case CardRarity.epic:      return 'EPIC';
      case CardRarity.legendary: return 'LEGENDARY';
      case CardRarity.seasonal:  return 'SEASONAL';
      case CardRarity.secret:    return 'SECRET';
    }
  }

  Color get color {
    switch (this) {
      case CardRarity.common:    return const Color(0xFF9E9E9E);
      case CardRarity.rare:      return const Color(0xFF5B8DEF);
      case CardRarity.epic:      return const Color(0xFFB06EE8);
      case CardRarity.legendary: return const Color(0xFFD4A96A);
      case CardRarity.seasonal:  return const Color(0xFF4CAF7D);
      case CardRarity.secret:    return const Color(0xFFE8624A);
    }
  }

  Color get glowColor {
    switch (this) {
      case CardRarity.common:    return const Color(0xFF9E9E9E);
      case CardRarity.rare:      return const Color(0xFF3D6FD4);
      case CardRarity.epic:      return const Color(0xFF9B4FD4);
      case CardRarity.legendary: return const Color(0xFFB8891A);
      case CardRarity.seasonal:  return const Color(0xFF2E8F5D);
      case CardRarity.secret:    return const Color(0xFFE8624A);
    }
  }

  int get points {
    switch (this) {
      case CardRarity.common:    return 10;
      case CardRarity.rare:      return 30;
      case CardRarity.epic:      return 100;
      case CardRarity.legendary: return 300;
      case CardRarity.seasonal:  return 75;
      case CardRarity.secret:    return 100;
    }
  }
}

class HanjCard {
  final String id;
  final String name;
  final String description;
  final CardRarity rarity;
  final String category;
  final int points;
  final bool isSecret;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const HanjCard({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.category,
    required this.points,
    this.isSecret = false,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  factory HanjCard.fromFirestore(Map<String, dynamic> data) {
    final rarityStr = data['rarity'] as String? ?? 'common';
    final rarity = CardRarity.values.firstWhere(
      (r) => r.name == rarityStr,
      orElse: () => CardRarity.common,
    );
    return HanjCard(
      id:          data['id'] as String? ?? '',
      name:        data['name'] as String? ?? '',
      description: data['description'] as String? ?? '',
      rarity:      rarity,
      category:    data['category'] as String? ?? '',
      points:      data['points'] as int? ?? 0,
      isSecret:    data['secret'] as bool? ?? false,
      isUnlocked:  true,
      unlockedAt:  (data['unlockedAt'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full card catalogue (mirrors index.js — for locked card display)
// ─────────────────────────────────────────────────────────────────────────────

const _kAllCards = [
  // Common
  ('first_pull',       'First Pull',           'Every collection starts somewhere.',                   'common',    'watcher'),
  ('the_list_begins',  'The List Begins',       'Ten worlds queued and waiting.',                       'common',    'watcher'),
  ('rated',            'Rated',                 'You have opinions. Share them.',                       'common',    'taste'),
  ('genre_curious',    'Genre Curious',         'Three genres, three different worlds.',                'common',    'genre'),
  // Rare
  ('decade_hopper',    'Decade Hopper',         'From classic to current — you respect the lineage.',  'rare',      'watcher'),
  ('the_critic',       'The Critic',            'Ten ratings. Your taste is documented.',               'rare',      'taste'),
  ('binge_mode',       'Binge Mode',            'Five worlds, one month. No regrets.',                 'rare',      'watcher'),
  ('loyal',            'Loyal',                 'Three months running. The habit has you.',             'rare',      'streak'),
  ('action_purist',    'Action Purist',         'The fight scenes chose you.',                         'rare',      'genre'),
  ('sol_soul',         'Slice of Life Soul',    'You find the extraordinary in the ordinary.',         'rare',      'genre'),
  ('romance_run',      'Hopeless Romantic',     'Love stories hit different.',                         'rare',      'genre'),
  ('fantasy_pilgrim',  'Fantasy Pilgrim',       'You live in worlds that don\'t exist.',               'rare',      'genre'),
  // Epic
  ('the_50_club',      'The 50 Club',           'Fifty worlds completed. You are not a casual.',       'epic',      'watcher'),
  ('genre_lord',       'Genre Lord',            'Twenty deep in one genre. You own it.',               'epic',      'genre'),
  ('harsh_critic',     'Harsh Critic',          'Your bar is high. Most things don\'t clear it.',      'epic',      'taste'),
  ('the_optimist',     'The Optimist',          'You see the best in everything you watch.',           'epic',      'taste'),
  ('decade_scholar',   'Decade Scholar',        'Five decades. You understand where anime came from.', 'epic',      'watcher'),
  ('obsessed',         'Obsessed',              'Ten anime in a single month. You had a month.',       'epic',      'watcher'),
  // Legendary
  ('the_100_club',     'The 100 Club',          'One hundred worlds. Few reach here.',                 'legendary', 'watcher'),
  ('year_of_anime',    'Year of Anime',         'Twelve consecutive months. Anime is a lifestyle.',    'legendary', 'streak'),
  ('all_seasons',      'All Seasons',           'Spring, Summer, Fall, Winter — you watched through all of it.', 'legendary', 'watcher'),
  ('the_200_club',     'The 200 Club',          'Two hundred worlds. You are the library.',            'legendary', 'watcher'),
  // Seasonal
  ('spring_2026_watcher', 'Spring 2026 Watcher', 'You were here for Spring 2026.',                    'seasonal',  'seasonal'),
  ('winter_arc_2026',  'Winter Arc',            'The coldest, longest watch sessions.',                'seasonal',  'seasonal'),
  ('golden_week_2026', 'Golden Week Marathon',  'You did not leave the house.',                        'seasonal',  'seasonal'),
  ('summer_2026_watcher', 'Summer 2026 Watcher', 'Hot outside. You stayed in and watched.',           'seasonal',  'seasonal'),
  // Secret
  ('cant_let_go',      'Can\'t Let Go',         'Dropped it. Came back. Some stories won\'t release you.', 'epic', 'secret'),
  ('resurrection',     'Resurrection',          'Dropped and completed the same anime.',               'epic',      'secret'),
  ('the_long_game',    'The Long Game',         'Plan to Watch for over a year. Patience rewarded.',   'rare',      'secret'),
  ('time_traveller',   'Time Traveller',        'Anime from five different decades.',                  'epic',      'secret'),
  ('the_purist',       'The Purist',            'Original and remake. You honour the source.',         'legendary', 'secret'),
  ('dropout',          'Dropout',               'Ten dropped. No shame — taste is selective.',         'rare',      'secret'),
  ('ghost_of_seasons_past', 'Ghost of Seasons Past', 'Completed an anime on the anniversary of its air date.', 'legendary', 'secret'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Card Collection Screen
// ─────────────────────────────────────────────────────────────────────────────

class CardCollectionScreen extends StatefulWidget {
  const CardCollectionScreen({super.key});

  @override
  State<CardCollectionScreen> createState() => _CardCollectionScreenState();
}

class _CardCollectionScreenState extends State<CardCollectionScreen>
    with SingleTickerProviderStateMixin {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  List<HanjCard> _unlocked = [];
  bool _isLoading = true;
  String _filter  = 'ALL';
  late TabController _tabCtrl;

  static const _filters = ['ALL', 'COMMON', 'RARE', 'EPIC', 'LEGENDARY', 'SEASONAL', 'SECRET'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _filters.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _filter = _filters[_tabCtrl.index]);
      }
    });
    _loadCards();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    try {
      final snap = await _firestore
          .collection('users').doc(uid)
          .collection('cards')
          .get();

      if (!mounted) return;
      setState(() {
        _unlocked  = snap.docs.map((d) => HanjCard.fromFirestore(d.data())).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _unlocked = []; _isLoading = false; });
    }
  }

  // Build full grid including locked cards
  List<({HanjCard? card, String id, String name, String description, CardRarity rarity, String category, bool isSecret})> _buildGrid() {
    final unlockedIds = { for (final c in _unlocked) c.id };

    final all = _kAllCards.map((t) {
      final rarity = CardRarity.values.firstWhere(
        (r) => r.name == t.$4,
        orElse: () => CardRarity.common,
      );
      final isSecret = t.$5 == 'secret';
      final unlocked = _unlocked.firstWhere(
        (c) => c.id == t.$1,
        orElse: () => HanjCard(
          id: t.$1, name: t.$2, description: t.$3,
          rarity: rarity, category: t.$5, points: rarity.points,
          isSecret: isSecret, isUnlocked: false,
        ),
      );
      return (
        card:        unlockedIds.contains(t.$1) ? unlocked : null,
        id:          t.$1,
        name:        t.$2,
        description: t.$3,
        rarity:      rarity,
        category:    t.$5,
        isSecret:    isSecret,
      );
    }).toList();

    if (_filter == 'ALL') return all;
    return all.where((e) => e.rarity.name.toUpperCase() == _filter).toList();
  }

  int get _totalPoints => _unlocked.fold(0, (sum, c) => sum + c.points);

  @override
  Widget build(BuildContext context) {
    final grid = _buildGrid();
    final unlockedCount = _unlocked.length;
    final totalCount    = _kAllCards.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => [
          SliverAppBar(
            backgroundColor: AppTheme.background,
            pinned: true,
            expandedHeight: 160,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppTheme.textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _CollectionHeader(
                unlockedCount: unlockedCount,
                totalCount:    totalCount,
                totalPoints:   _totalPoints,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _RarityTabBar(controller: _tabCtrl, filters: _filters),
            ),
          ),
        ],
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2))
            : grid.isEmpty
                ? _EmptyFilter(filter: _filter)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 200 / 300, // matches HanjCard.kWidth / kHeight
                    ),
                    itemCount: grid.length,
                    itemBuilder: (ctx, i) {
                      final item = grid[i];
                      return _HanjCardTile(
                        id:          item.id,
                        name:        item.name,
                        description: item.description,
                        rarity:      item.rarity,
                        category:    item.category,
                        isSecret:    item.isSecret,
                        isUnlocked:  item.card != null,
                        unlockedAt:  item.card?.unlockedAt,
                        onTap: () => _showCardDetail(context, item.id, item.name,
                            item.description, item.rarity, item.category,
                            item.isSecret, item.card != null, item.card?.unlockedAt),
                      );
                    },
                  ),
      ),
    );
  }

  void _showCardDetail(
    BuildContext context,
    String id, String name, String description,
    CardRarity rarity, String category,
    bool isSecret, bool isUnlocked, DateTime? unlockedAt,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CardDetailSheet(
        id:         id,
        name:       name,
        description: description,
        rarity:     rarity,
        category:   category,
        isSecret:   isSecret,
        isUnlocked: isUnlocked,
        unlockedAt: unlockedAt,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _CollectionHeader extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;
  final int totalPoints;

  const _CollectionHeader({
    required this.unlockedCount,
    required this.totalCount,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    final pct = totalCount > 0 ? unlockedCount / totalCount : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CARD COLLECTION',
                      style: AppTheme.mono(
                          fontSize: 10,
                          color: AppTheme.primary,
                          letterSpacing: 2.0),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hanj Cards',
                      style: GoogleFonts.playfairDisplay(
                        color: AppTheme.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$unlockedCount / $totalCount',
                    style: AppTheme.sans(
                        fontSize: 22,
                        weight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  Text(
                    '$totalPoints pts',
                    style: AppTheme.mono(
                        fontSize: 10,
                        color: AppTheme.primary,
                        letterSpacing: 1.0),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFFD4A96A)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rarity tab bar
// ─────────────────────────────────────────────────────────────────────────────

class _RarityTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> filters;

  const _RarityTabBar({required this.controller, required this.filters});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.5)),
        ),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 2,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        dividerColor: Colors.transparent,
        labelStyle: AppTheme.mono(
            fontSize: 10, letterSpacing: 1.2, color: AppTheme.primary),
        unselectedLabelStyle: AppTheme.mono(
            fontSize: 10, letterSpacing: 1.2, color: AppTheme.textMuted),
        tabs: filters.map((f) => Tab(text: f)).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card tile
// ─────────────────────────────────────────────────────────────────────────────

class _HanjCardTile extends StatelessWidget {
  final String id;
  final String name;
  final String description;
  final CardRarity rarity;
  final String category;
  final bool isSecret;
  final bool isUnlocked;
  final DateTime? unlockedAt;
  final VoidCallback onTap;

  const _HanjCardTile({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.category,
    required this.isSecret,
    required this.isUnlocked,
    required this.onTap,
    this.unlockedAt,
  });

  // Map category string → kanji for the new card widget
  String get _kanji {
    switch (category) {
      case 'watcher':  return '眼';
      case 'genre':    return '流';
      case 'streak':   return '火';
      case 'taste':    return '心';
      case 'secret':   return '秘';
      case 'seasonal': return '季';
      default:         return '道';
    }
  }

  // Map id → card number (matches catalogue; fallback to 0)
  int get _cardNumber {
    const nums = {
      'first_pull': 1, 'the_list_begins': 2, 'rated': 3, 'genre_curious': 4,
      'decade_hopper': 214, 'the_critic': 215, 'binge_mode': 216, 'loyal': 217,
      'action_purist': 218, 'sol_soul': 219, 'romance_run': 220, 'fantasy_pilgrim': 221,
      'the_50_club': 50, 'genre_lord': 51, 'harsh_critic': 52, 'the_optimist': 53,
      'decade_scholar': 54, 'obsessed': 55,
      'the_100_club': 100, 'year_of_anime': 365, 'all_seasons': 4, 'the_200_club': 200,
      'spring_2026_watcher': 237, 'winter_arc_2026': 88,
      'golden_week_2026': 312, 'summer_2026_watcher': 401,
    };
    return nums[id] ?? 0;
  }

  int? get _totalCount {
    const totals = {
      'spring_2026_watcher': 2400, 'winter_arc_2026': 1200,
      'golden_week_2026': 800, 'summer_2026_watcher': 2400,
    };
    return totals[id];
  }

  hc.HanjCardData get _cardData => hc.HanjCardData(
    id:          id,
    name:        isSecret && !isUnlocked ? '???' : name,
    description: description,
    rarity:      hc.CardRarity.values.firstWhere(
      (r) => r.name == rarity.name,
      orElse: () => hc.CardRarity.common,
    ),
    category:    category.toUpperCase(),
    kanji:       _kanji,
    cardNumber:  _cardNumber,
    totalCount:  _totalCount,
    unlockedAt:  unlockedAt,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return hc.HanjCard(
            card:       _cardData,
            isUnlocked: isUnlocked,
            width:      constraints.maxWidth,
            height:     constraints.maxHeight,
          );
        },
      ),
    );
  }
}





// ─────────────────────────────────────────────────────────────────────────────
// Card detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CardDetailSheet extends StatelessWidget {
  final String id;
  final String name;
  final String description;
  final CardRarity rarity;
  final String category;
  final bool isSecret;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const _CardDetailSheet({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.category,
    required this.isSecret,
    required this.isUnlocked,
    this.unlockedAt,
  });

  String get _categoryLabel {
    switch (category) {
      case 'watcher':  return 'Watcher';
      case 'genre':    return 'Genre';
      case 'streak':   return 'Streak';
      case 'taste':    return 'Taste';
      case 'secret':   return 'Secret';
      case 'seasonal': return 'Seasonal';
      default:         return category;
    }
  }

  static String _kanjiFor(String cat) {
    switch (cat) {
      case 'watcher':  return '眼';
      case 'genre':    return '流';
      case 'streak':   return '火';
      case 'taste':    return '心';
      case 'secret':   return '秘';
      case 'seasonal': return '季';
      default:         return '道';
    }
  }

  static String _hintFor(String id) {
    const hints = {
      'first_pull':        'Add your first anime to any list.',
      'the_list_begins':   'Add 10 anime to your lists.',
      'rated':             'Rate an anime from your list.',
      'genre_curious':     'Add anime from 3 different genres.',
      'decade_hopper':     'Complete anime from different release decades.',
      'the_critic':        'Rate 10 or more anime.',
      'binge_mode':        'Complete 5 anime in a single month.',
      'loyal':             'Stay active on Hanj for 3 months.',
      'action_purist':     'Complete 10 action anime.',
      'romance_soul':      'Complete 10 romance anime.',
      'slice_of_life':     'Complete 10 slice-of-life anime.',
      'fantasy_lord':      'Complete 10 fantasy anime.',
      'the_50_club':       'Complete 50 anime total.',
      'genre_lord':        'Complete 20 anime in a single genre.',
      'harsh_critic':      'Keep your average rating below 6.',
      'the_optimist':      'Keep your average rating above 8.5.',
      'decade_scholar':    'Complete anime from 5 different decades.',
      'cant_let_go':       'Drop an anime, then add it back.',
      'the_100_club':      'Complete 100 anime total.',
      'year_of_anime':     'Complete anime every month for a full year.',
      'all_seasons':       'Complete anime from all 4 seasons in a year.',
      'the_200_club':      'Complete 200 anime total.',
      'spring_2026_watcher': 'Watch anime airing in Spring 2026.',
      'winter_arc_2026':   'Watch anime airing in Winter 2026.',
      'golden_week_2026':  'Active during Golden Week 2026.',
      'summer_2026_watcher': 'Watch anime airing in Summer 2026.',
    };
    return hints[id] ?? 'Keep watching and exploring.';
  }

  static int _cardNumberFor(String id) {
    const nums = {
      'first_pull': 1, 'the_list_begins': 2, 'rated': 3, 'genre_curious': 4,
      'decade_hopper': 214, 'the_critic': 215, 'binge_mode': 216, 'loyal': 217,
      'action_purist': 218, 'sol_soul': 219, 'romance_run': 220, 'fantasy_pilgrim': 221,
      'the_50_club': 50, 'genre_lord': 51, 'harsh_critic': 52, 'the_optimist': 53,
      'decade_scholar': 54, 'obsessed': 55,
      'the_100_club': 100, 'year_of_anime': 365, 'all_seasons': 4, 'the_200_club': 200,
      'spring_2026_watcher': 237, 'winter_arc_2026': 88,
      'golden_week_2026': 312, 'summer_2026_watcher': 401,
    };
    return nums[id] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C09),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: rarity.color.withValues(alpha: 0.4), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: rarity.color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),

          // Big card preview — uses real HanjCard widget
          SizedBox(
            width:  hc.HanjCard.kWidth,
            height: hc.HanjCard.kHeight,
            child: hc.HanjCard(
              isUnlocked: isUnlocked,
              card: hc.HanjCardData(
                id:          id,
                name:        isSecret && !isUnlocked ? '???' : name,
                description: description,
                rarity: hc.CardRarity.values.firstWhere(
                  (r) => r.name == rarity.name,
                  orElse: () => hc.CardRarity.common,
                ),
                category:   category.toUpperCase(),
                kanji:      _kanjiFor(category),
                cardNumber: _cardNumberFor(id),
                unlockedAt: unlockedAt,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Name
          Text(
            isUnlocked ? name : (isSecret ? '???' : name),
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),

          // Rarity + category chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Chip(label: rarity.label, color: rarity.color),
              const SizedBox(width: 8),
              _Chip(label: _categoryLabel.toUpperCase(),
                  color: AppTheme.textMuted),
              if (isUnlocked) ...[
                const SizedBox(width: 8),
                _Chip(label: '+${rarity.points} PTS',
                    color: const Color(0xFFD4A96A)),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Description / hint
          Text(
            isUnlocked
                ? description
                : (isSecret
                    ? 'This card is hidden. Keep watching to discover it.'
                    : 'Complete the milestone to unlock this card.'),
            textAlign: TextAlign.center,
            style: AppTheme.sans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.6,
            ),
          ),
          // Unlock hint — subtle clue for locked non-secret cards
          if (!isUnlocked && !isSecret) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: rarity.color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: rarity.color.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tips_and_updates_outlined,
                      size: 12, color: rarity.color.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _hintFor(id),
                      textAlign: TextAlign.center,
                      style: AppTheme.mono(
                        fontSize: 10,
                        color: rarity.color.withValues(alpha: 0.6),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Unlocked date
          if (isUnlocked && unlockedAt != null) ...[
            const SizedBox(height: 20),
            Text(
              'UNLOCKED ${unlockedAt!.day.toString().padLeft(2, '0')}'
              '.${unlockedAt!.month.toString().padLeft(2, '0')}'
              '.${unlockedAt!.year}',
              style: AppTheme.mono(
                  fontSize: 9,
                  color: rarity.color.withValues(alpha: 0.5),
                  letterSpacing: 1.2),
            ),
          ],

          if (isUnlocked) ...[
            const SizedBox(height: 20),
            _PinCardButton(
              cardId:      id,
              cardName:    name,
              description: description,
              rarity:      rarity.name,
              category:    category,
              kanji:       _kanjiFor(category),
              cardNumber:  _cardNumberFor(id),
              totalCount:  null, // seasonal cards store this in Firestore already
            ),
            const SizedBox(height: 12),
            // Share — turns a card into a story-format image for IG / Snap / etc.
            GestureDetector(
              onTap: () => openCardShare(
                context,
                accentColor: rarity.color,
                rarityLabel: rarity.label,
                card: hc.HanjCardData(
                  id:          id,
                  name:        name,
                  description: description,
                  rarity: hc.CardRarity.values.firstWhere(
                    (r) => r.name == rarity.name,
                    orElse: () => hc.CardRarity.common,
                  ),
                  category:   category.toUpperCase(),
                  kanji:      _kanjiFor(category),
                  cardNumber: _cardNumberFor(id),
                  unlockedAt: unlockedAt,
                ),
              ),
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF161514),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.ios_share_rounded,
                        size: 17, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'SHARE CARD',
                      style: AppTheme.mono(
                        fontSize: 12,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTheme.mono(
            fontSize: 9, color: color, letterSpacing: 1.0),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pin / Unpin button — shown in card detail sheet for unlocked cards
// Saves up to 3 pinned cards to users/{uid}/pinnedCards in Firestore
// ─────────────────────────────────────────────────────────────────────────────

class _PinCardButton extends StatefulWidget {
  final String cardId, cardName, description, rarity, category, kanji;
  final int cardNumber;
  final int? totalCount;

  const _PinCardButton({
    required this.cardId,
    required this.cardName,
    required this.description,
    required this.rarity,
    required this.category,
    required this.kanji,
    required this.cardNumber,
    this.totalCount,
  });

  @override
  State<_PinCardButton> createState() => _PinCardButtonState();
}

class _PinCardButtonState extends State<_PinCardButton> {
  bool _loading = true;
  bool _isPinned = false;
  List<dynamic> _pinned = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final pinned = (doc.data()?['pinnedCards'] as List<dynamic>?) ?? [];
    if (mounted) {
      setState(() {
        _pinned = pinned;
        _isPinned = pinned.any((c) => c['id'] == widget.cardId);
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_isPinned) {
      // Unpin immediately
      final updated = _pinned.where((c) => c['id'] != widget.cardId).toList();
      setState(() { _pinned = updated; _isPinned = false; });
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'pinnedCards': updated}, SetOptions(merge: true));
      return;
    }

    final newCard = {
      'id':          widget.cardId,
      'name':        widget.cardName,
      'description': widget.description,
      'rarity':      widget.rarity,
      'category':    widget.category,
      'kanji':       widget.kanji,
      'cardNumber':  widget.cardNumber,
      'totalCount':  widget.totalCount,
    };

    // If a card is already pinned, ask to replace it
    if (_pinned.isNotEmpty) {
      final existingName = (_pinned.first['name'] as String?) ?? 'current card';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF0F0C09),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: CardRarity.values
                  .firstWhere((r) => r.name == widget.rarity,
                      orElse: () => CardRarity.common)
                  .color
                  .withValues(alpha: 0.3),
            ),
          ),
          title: Text(
            'Replace card?',
            style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700),
          ),
          content: Text(
            'Replace "$existingName" with "${widget.cardName}" on your profile?',
            style: AppTheme.sans(fontSize: 14, color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: AppTheme.sans(fontSize: 14, color: AppTheme.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Pin it',
                  style: AppTheme.sans(
                      fontSize: 14,
                      color: AppTheme.primary,
                      weight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Pin immediately — optimistic update
    final updated = [newCard];
    setState(() { _pinned = updated; _isPinned = true; });
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'pinnedCards': updated}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 40);

    final color = _isPinned ? AppTheme.primary : AppTheme.accent;
    final label = _isPinned ? 'PINNED ✓' : 'PIN TO PROFILE';
    final icon  = _isPinned ? Icons.push_pin : Icons.push_pin_outlined;

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 8),
            Text(label,
                style: AppTheme.mono(
                    fontSize: 10, color: color, letterSpacing: 1.2)),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  final String filter;
  const _EmptyFilter({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.style_rounded,
                color: AppTheme.textMuted.withValues(alpha: 0.3), size: 48),
            const SizedBox(height: 16),
            Text(
              'No $filter cards yet',
              style: AppTheme.serif(
                  fontSize: 18,
                  weight: FontWeight.w600,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep watching to unlock cards in this tier.',
              textAlign: TextAlign.center,
              style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
