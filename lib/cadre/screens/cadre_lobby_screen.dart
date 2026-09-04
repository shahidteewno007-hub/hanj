import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_fighter.dart';
import '../models/cadre_match.dart';
import '../models/cadre_pool.dart';
import '../models/cadre_squad.dart';
import '../models/cadre_stats.dart';
import '../services/cadre_roster_service.dart';
import '../services/cadre_stats_service.dart';
import '../widgets/cadre_fighter_card.dart';
import 'cadre_clash_screen.dart';
import 'cadre_pool_screen.dart';
import 'cadre_profile_screen.dart';
import 'cadre_roster_screen.dart';
import 'cadre_squad_screen.dart';

/// Cadre's front door.
///
/// Each mode owns its pool rather than sharing one global selection, so
/// choosing a crossover never costs you your single-anime pick.
class CadreLobbyScreen extends StatefulWidget {
  const CadreLobbyScreen({super.key});

  @override
  State<CadreLobbyScreen> createState() => _CadreLobbyScreenState();
}

class _CadreLobbyScreenState extends State<CadreLobbyScreen> {
  final _rosters = CadreRosterService.instance;
  final _store = CadreStatsService.instance;

  CadrePool _solo = const CadrePool.empty();
  CadrePool _crossover = const CadrePool.empty();
  CadrePoolMode _active = CadrePoolMode.single;
  CadreStats _stats = CadreStats.empty;
  bool _loading = true;
  String? _error;

  static const _soloSlot = 'solo';
  static const _crossoverSlot = 'crossover';

  /// Seeded the first time Cadre opens, so the lobby is never a dead end.
  static const _defaultAnime = 'Naruto';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<CadrePool> _rebuild(List<int> ids) async {
    var pool = const CadrePool.empty();
    for (final id in ids) {
      try {
        pool = pool.add(await _rosters.fetchById(id));
      } catch (_) {
        // One dead id shouldn't cost the whole pool.
      }
    }
    return pool;
  }

  CadrePool get _activePool =>
      _active == CadrePoolMode.single ? _solo : _crossover;

  bool get _activeReady {
    final pool = _activePool;
    if (pool.length < CadreMatch.minRosterSize) return false;
    return _active == CadrePoolMode.single
        ? pool.rosters.length == 1
        : pool.rosters.length >= 2;
  }

  /// Squad deals eight to each side out of one pool, so it needs 16 where
  /// Clash needs 6. Checked here rather than inside the tile so the tile can
  /// say so before it is tapped instead of after.
  bool get _squadReady =>
      _activePool.length >= CadreSquadMatch.minRosterSize;

  String _slotFor(CadrePoolMode mode) =>
      mode == CadrePoolMode.single ? _soloSlot : _crossoverSlot;

  /// Opens the read-only roster for whichever pool is active.
  void _openRoster(CadrePool pool) {
    if (pool.isEmpty) return;
    HapticFeedback.selectionClick();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CadreRosterScreen(pool: pool)),
    );
  }

  void _switchTo(CadrePoolMode mode) {
    if (mode == _active) return;
    HapticFeedback.selectionClick();
    setState(() => _active = mode);
    _store.saveActiveSlot(_slotFor(mode));
  }

  Future<void> _boot() async {
    final stats = await _store.load();
    final activeSlot = await _store.loadActiveSlot();
    var solo = const CadrePool.empty();
    var crossover = const CadrePool.empty();
    String? error;

    try {
      final soloIds = await _store.loadPoolIds(_soloSlot);
      solo = await _rebuild(soloIds);
      if (solo.isEmpty) {
        solo = CadrePool.single(await _rosters.fetchByTitle(_defaultAnime));
      }
      crossover = await _rebuild(await _store.loadPoolIds(_crossoverSlot));
    } on CadreRosterException catch (e) {
      error = e.message;
    }

    if (!mounted) return;
    setState(() {
      _stats = stats;
      _solo = solo;
      _crossover = crossover;
      _active = activeSlot == _crossoverSlot
          ? CadrePoolMode.crossover
          : CadrePoolMode.single;
      _error = error;
      _loading = false;
    });
  }

  Future<void> _editPool(CadrePoolMode mode) async {
    final current = mode == CadrePoolMode.single ? _solo : _crossover;
    final result = await Navigator.of(context).push<CadrePool>(
      MaterialPageRoute<CadrePool>(
        builder: (_) => CadrePoolScreen(pool: current, mode: mode),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (mode == CadrePoolMode.single) {
        _solo = result;
      } else {
        _crossover = result;
      }
      _error = null;
    });
    _store.savePoolIds(_slotFor(mode), result.animeIds);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CadreProfileScreen()),
    );
    if (!mounted) return;
    setState(() => _stats = _store.cached);
  }

  void _play(CadrePool pool) {
    if (pool.length < CadreMatch.minRosterSize) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: CadreColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _OpponentSheet(
        onPick: (mode) async {
          Navigator.pop(sheetContext);
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CadreClashScreen(pool: pool, mode: mode),
            ),
          );
          if (!mounted) return;
          setState(() => _stats = _store.cached);
        },
      ),
    );
  }

  /// Squad has one opponent, so it skips the sheet Clash needs and deals
  /// straight away.
  Future<void> _playSquad(CadrePool pool) async {
    if (pool.length < CadreSquadMatch.minRosterSize) {
      _comingSoon(
        'Squad',
        'needs ${CadreSquadMatch.minRosterSize} characters, '
            'this pool has ${pool.length}',
      );
      return;
    }
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CadreSquadScreen(pool: pool)),
    );
    if (!mounted) return;
    setState(() => _stats = _store.cached);
  }

  void _comingSoon(String mode, String note) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: CadreColors.surface,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            '$mode \u2014 $note',
            style: GoogleFonts.dmSans(
              color: CadreColors.ivory,
              fontSize: 13,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: CadreColors.bg,
        body: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: CadreColors.coral,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: CadreColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
          children: [
            _Header(stats: _stats, onProfile: _openProfile),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: GoogleFonts.dmSans(
                  color: CadreColors.coral,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _SectionLabel('MODES'),
            const SizedBox(height: 12),
            _ClashTile(
              active: _active,
              pool: _activePool,
              artPool: _activePool.isEmpty ? _solo : _activePool,
              ready: _activeReady,
              onSwitch: _switchTo,
              onPlay: () => _play(_activePool),
              onEditPool: () => _editPool(_active),
              onViewRoster: () => _openRoster(_activePool),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SmallModeTile(
                    title: 'Squad',
                    line: 'Draft five, assign roles',
                    status: _squadReady
                        ? 'PLAY'
                        : 'NEEDS ${CadreSquadMatch.minRosterSize}',
                    live: _squadReady,
                    onTap: () => _playSquad(_activePool),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SmallModeTile(
                    title: 'Scenario',
                    line: 'Send a team at a mission',
                    status: 'IN DEVELOPMENT',
                    live: false,
                    onTap: () => _comingSoon('Scenario', 'in design'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final CadreStats stats;
  final VoidCallback onProfile;

  const _Header({required this.stats, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    // Shown only when Cadre was pushed onto a stack, so the sandbox entry
    // point — where the lobby is the root — is unchanged.
    final canPop = Navigator.of(context).canPop();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 44,
              height: 40,
              alignment: Alignment.centerLeft,
              margin: const EdgeInsets.only(bottom: 4),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: CadreColors.ivoryDim,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cadre',
                    style: GoogleFonts.playfairDisplay(
                      color: CadreColors.ivory,
                      fontSize: 38,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [CadreColors.ember, CadreColors.coral],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _RecordRibbon(stats: stats),
                ],
              ),
            ),
            GestureDetector(
              onTap: onProfile,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: CadreColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: CadreColors.coralEdge),
                ),
                child: const Icon(
                  Icons.bar_chart_rounded,
                  size: 21,
                  color: CadreColors.ivoryDim,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The record read as a fight record rather than a paragraph.
class _RecordRibbon extends StatelessWidget {
  final CadreStats stats;
  const _RecordRibbon({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (!stats.hasRecord) {
      return Text(
        'No matches yet',
        style: GoogleFonts.dmSans(
          color: CadreColors.ivoryFaint,
          fontSize: 13,
        ),
      );
    }

    return Row(
      children: [
        _Figure(value: stats.won, label: 'W', accent: true),
        _divider(),
        _Figure(value: stats.lost, label: 'L'),
        if (stats.currentStreak >= 2) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: CadreColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CadreColors.coralEdge),
            ),
            child: Text(
              '${stats.currentStreak} in a row',
              style: GoogleFonts.dmSans(
                color: CadreColors.coral,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 13,
        margin: const EdgeInsets.symmetric(horizontal: 11),
        color: CadreColors.hairline,
      );
}

class _Figure extends StatelessWidget {
  final int value;
  final String label;
  final bool accent;

  const _Figure({
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: GoogleFonts.spaceGrotesk(
            color: accent ? CadreColors.coral : CadreColors.ivory,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.dmSans(
        color: CadreColors.ivoryFaint,
        fontSize: 11,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The hero tile, furnished with real art from the pool it's pointed at.
///
/// Single and Crossover live inside one tile rather than as two, because the
/// art-backed card is the strongest thing on the screen and a second copy of
/// it halves the effect. The segmented control rewrites the description as it
/// switches, so it explains itself without needing a label.
class _ClashTile extends StatelessWidget {
  final CadrePoolMode active;
  final CadrePool pool;
  final CadrePool artPool;
  final bool ready;
  final void Function(CadrePoolMode mode) onSwitch;
  final VoidCallback onPlay;
  final VoidCallback onEditPool;
  final VoidCallback onViewRoster;

  const _ClashTile({
    required this.active,
    required this.pool,
    required this.artPool,
    required this.ready,
    required this.onSwitch,
    required this.onPlay,
    required this.onEditPool,
    required this.onViewRoster,
  });

  bool get _single => active == CadrePoolMode.single;

  String get _line => _single
      ? 'One anime. Eleven cards each, ten rounds.'
      : 'Two or more casts, shuffled into one deck.';

  String get _emptyLine =>
      _single ? 'Pick an anime' : 'Pick at least two anime';

  @override
  Widget build(BuildContext context) {
    final art = _pickArt(artPool);

    return Container(
      decoration: BoxDecoration(
        color: CadreColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ready ? CadreColors.coralEdge : CadreColors.hairline,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          children: [
            for (var i = 0; i < art.length; i++)
              Positioned(
                right: 4.0 + (i * 52),
                top: 14.0 + (i * 8),
                child: Transform.rotate(
                  angle: (i - 1) * 0.13,
                  child: Opacity(
                    opacity: 0.5 - (i * 0.11),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 86,
                        height: 128,
                        child: CachedNetworkImage(
                          imageUrl: art[i],
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              const ColoredBox(color: CadreColors.surface),
                          errorWidget: (_, __, ___) =>
                              const ColoredBox(color: CadreColors.surface),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: [0.0, 0.55, 1.0],
                    colors: [
                      Color(0xFF141210),
                      Color(0xE6141210),
                      Color(0x40141210),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Clash',
                    style: GoogleFonts.playfairDisplay(
                      color: CadreColors.ivory,
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 196,
                    child: Text(
                      _line,
                      style: GoogleFonts.dmSans(
                        color: CadreColors.ivoryDim,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Segmented(
                    active: active,
                    onSwitch: onSwitch,
                  ),
                  const SizedBox(height: 12),
                  _PoolRow(
                    pool: pool,
                    emptyLine: _emptyLine,
                    ready: ready,
                    onTap: onEditPool,
                  ),
                  if (!pool.isEmpty) ...[
                    const SizedBox(height: 9),
                    _RosterLink(onTap: onViewRoster),
                  ],
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: ready ? onPlay : onEditPool,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        gradient: ready
                            ? const LinearGradient(
                                colors: [CadreColors.ember, CadreColors.coral],
                              )
                            : null,
                        color: ready ? null : CadreColors.bg,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        ready ? 'Play' : 'Set it up',
                        style: GoogleFonts.dmSans(
                          color: ready ? Colors.white : CadreColors.ivoryFaint,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Up to three characters, spread across the anime in the pool so a
  /// crossover looks like one at a glance.
  List<String> _pickArt(CadrePool pool) {
    if (pool.isEmpty) return const <String>[];
    final picks = <CadreFighter>[];

    for (final roster in pool.rosters) {
      final sorted = List<CadreFighter>.of(roster.fighters)
        ..sort((a, b) => b.power.compareTo(a.power));
      if (sorted.isNotEmpty) picks.add(sorted.first);
      if (picks.length == 3) break;
    }

    if (picks.length < 3) {
      final all = List<CadreFighter>.of(pool.fighters)
        ..sort((a, b) => b.power.compareTo(a.power));
      for (final f in all) {
        if (picks.length == 3) break;
        if (picks.any((p) => p.id == f.id)) continue;
        picks.add(f);
      }
    }

    return <String>[
      for (final f in picks.take(math.min(3, picks.length))) f.imageUrl,
    ];
  }
}

class _Segmented extends StatelessWidget {
  final CadrePoolMode active;
  final void Function(CadrePoolMode mode) onSwitch;

  const _Segmented({required this.active, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 226,
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CadreColors.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: CadreColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'Single',
              selected: active == CadrePoolMode.single,
              onTap: () => onSwitch(CadrePoolMode.single),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'Crossover',
              selected: active == CadrePoolMode.crossover,
              onTap: () => onSwitch(CadrePoolMode.crossover),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [CadreColors.ember, CadreColors.coral],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            color: selected ? Colors.white : CadreColors.ivoryDim,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PoolRow extends StatelessWidget {
  final CadrePool pool;
  final String emptyLine;
  final bool ready;
  final VoidCallback onTap;

  const _PoolRow({
    required this.pool,
    required this.emptyLine,
    required this.ready,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 10),
        decoration: BoxDecoration(
          color: CadreColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ready ? CadreColors.hairline : CadreColors.coralEdge,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready ? pool.title : emptyLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      color: ready ? CadreColors.ivory : CadreColors.coral,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (ready) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${pool.length} characters',
                      style: GoogleFonts.spaceGrotesk(
                        color: CadreColors.ivoryFaint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: CadreColors.ivoryFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet secondary action. Deliberately not a button — the pool row above it
/// and the Play button below it are the loud things in this tile.
class _RosterLink extends StatelessWidget {
  final VoidCallback onTap;

  const _RosterLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_alt_outlined,
              size: 13,
              color: CadreColors.ivoryFaint,
            ),
            const SizedBox(width: 7),
            Text(
              'View roster',
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryDim,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallModeTile extends StatelessWidget {
  final String title;
  final String line;

  /// The state line along the bottom: 'PLAY' once a mode can be entered, or
  /// what is standing in its way.
  final String status;

  /// A playable mode is lit rather than greyed, so the tile stops reading as
  /// a placeholder the moment it stops being one.
  final bool live;

  final VoidCallback onTap;

  const _SmallModeTile({
    required this.title,
    required this.line,
    required this.status,
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 116,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: CadreColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: live ? CadreColors.coralEdge : CadreColors.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.playfairDisplay(
                    color: live ? CadreColors.ivory : CadreColors.ivoryDim,
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  line,
                  style: GoogleFonts.dmSans(
                    color: CadreColors.ivoryFaint,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            Text(
              status,
              style: GoogleFonts.dmSans(
                color: live ? CadreColors.coral : CadreColors.ivoryFaint,
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: live ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpponentSheet extends StatelessWidget {
  final void Function(CadreMode mode) onPick;
  const _OpponentSheet({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Who are you playing?',
            style: GoogleFonts.playfairDisplay(
              color: CadreColors.ivory,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _Choice(
            title: 'The bot',
            line: 'Counts towards your record',
            filled: true,
            onTap: () => onPick(CadreMode.bot),
          ),
          const SizedBox(height: 10),
          _Choice(
            title: 'Two players \u2014 Honor',
            line: 'Both cards face up, no power shown. You both call it.',
            filled: false,
            onTap: () => onPick(CadreMode.honor),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String title;
  final String line;
  final bool filled;
  final VoidCallback onTap;

  const _Choice({
    required this.title,
    required this.line,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  colors: [CadreColors.ember, CadreColors.coral],
                )
              : null,
          color: filled ? null : CadreColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: filled ? null : Border.all(color: CadreColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.dmSans(
                color: filled ? Colors.white : CadreColors.ivory,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              line,
              style: GoogleFonts.dmSans(
                color: filled ? const Color(0xCCFFFFFF) : CadreColors.ivoryFaint,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
