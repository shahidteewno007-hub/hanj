import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_match.dart';
import '../models/cadre_pool.dart';
import '../services/cadre_roster_service.dart';
import '../widgets/cadre_fighter_card.dart';

/// Which kind of pool is being built.
enum CadrePoolMode {
  /// Exactly one anime. Picking a new one replaces the old.
  single,

  /// Two or more anime.
  crossover,
}

/// Build the draft pool.
class CadrePoolScreen extends StatefulWidget {
  final CadrePool pool;
  final CadrePoolMode mode;

  const CadrePoolScreen({
    super.key,
    required this.pool,
    required this.mode,
  });

  @override
  State<CadrePoolScreen> createState() => _CadrePoolScreenState();
}

class _CadrePoolScreenState extends State<CadrePoolScreen> {
  final _controller = TextEditingController();
  final _service = CadreRosterService.instance;

  late CadrePool _pool = widget.pool;
  List<CadreAnimeSummary> _results = const <CadreAnimeSummary>[];
  String? _error;
  bool _searching = false;
  int? _adding;

  static const _suggested = <String>[
    'Naruto',
    'One Piece',
    'Bleach',
    'Jujutsu Kaisen',
    'Demon Slayer',
    'Attack on Titan',
    'Death Note',
    'Hunter x Hunter',
    'My Hero Academia',
    'Fullmetal Alchemist',
    'Chainsaw Man',
    'Frieren',
    'Vinland Saga',
    'Spy x Family',
    'Mob Psycho 100',
    'Code Geass',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await _service.searchAnime(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) _error = 'Nothing matched "$query".';
      });
    } on CadreRosterException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _searching = false;
      });
    }
  }

  bool get _isSingle => widget.mode == CadrePoolMode.single;

  /// Loose match on purpose: the chip says "Frieren", AniList says
  /// "Frieren: Beyond Journey's End". Close enough for a visual hint.
  bool _alreadyIn(String suggestion) {
    final needle = suggestion.toLowerCase();
    return _pool.rosters.any(
      (r) => r.title.toLowerCase().contains(needle),
    );
  }

  bool get _satisfied => _isSingle
      ? _pool.rosters.length == 1
      : _pool.rosters.length >= 2;

  Future<void> _add(CadreAnimeSummary anime) async {
    if (_pool.contains(anime.id)) return;
    setState(() => _adding = anime.id);
    try {
      final roster = await _service.fetchById(anime.id);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        // Single mode is a choice, not a collection: a new pick replaces
        // whatever was there.
        _pool = _isSingle ? CadrePool.single(roster) : _pool.add(roster);
        _adding = null;
        // The choice is made, so the results have done their job. Clearing
        // back to the suggestions makes the next pick one tap instead of
        // another search.
        _controller.clear();
        _results = const <CadreAnimeSummary>[];
        _error = null;
      });
    } on CadreRosterException catch (e) {
      if (!mounted) return;
      setState(() {
        _adding = null;
        _error = e.message;
      });
    }
  }

  void _remove(int animeId) {
    HapticFeedback.selectionClick();
    setState(() => _pool = _pool.remove(animeId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CadreColors.bg,
      appBar: AppBar(
        backgroundColor: CadreColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: CadreColors.ivory),
        title: Text(
          _isSingle ? 'Choose an anime' : 'Build a crossover',
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryDim,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: _SearchField(
                controller: _controller,
                onSubmit: () => _search(_controller.text),
              ),
            ),
            if (_pool.isNotEmpty)
              _PoolStrip(
                pool: _pool,
                single: _isSingle,
                onRemove: _remove,
              ),
            if (!_isSingle && _pool.rosters.length == 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Add one more anime to make it a crossover.',
                  style: GoogleFonts.dmSans(
                    color: CadreColors.ivoryFaint,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: GestureDetector(
          onTap: _satisfied ? () => Navigator.pop(context, _pool) : null,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _satisfied
                  ? const LinearGradient(
                      colors: [CadreColors.ember, CadreColors.coral],
                    )
                  : null,
              color: _satisfied ? null : CadreColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: _satisfied
                  ? null
                  : Border.all(color: CadreColors.hairline),
            ),
            child: Text(
              _satisfied
                  ? 'Use this pool  \u00B7  ${_pool.length} characters'
                  : (_isSingle
                      ? 'Pick an anime'
                      : 'Pick at least two anime'),
              style: GoogleFonts.dmSans(
                color: _satisfied ? Colors.white : CadreColors.ivoryFaint,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: CadreColors.coral,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: GoogleFonts.dmSans(
                  color: CadreColors.ivoryDim,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'POPULAR CASTS',
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryFaint,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final title in _suggested)
                  _SuggestionChip(
                    title: title,
                    added: _alreadyIn(title),
                    onTap: () {
                      _controller.text = title;
                      _search(title);
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final anime = _results[i];
        return _ResultRow(
          anime: anime,
          added: _pool.contains(anime.id),
          single: _isSingle,
          busy: _adding == anime.id,
          onAdd: () => _add(anime),
          onRemove: () => _remove(anime.id),
        );
      },
    );
  }
}

class _PoolStrip extends StatelessWidget {
  final CadrePool pool;
  final bool single;
  final void Function(int animeId) onRemove;

  const _PoolStrip({
    required this.pool,
    required this.single,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: CadreColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CadreColors.coralEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            single
                ? 'SELECTED  \u00B7  ${pool.length} CHARACTERS'
                : (pool.isCrossover
                    ? 'CROSSOVER  \u00B7  ${pool.length} CHARACTERS'
                    : '${pool.length} CHARACTERS'),
            style: GoogleFonts.dmSans(
              color: CadreColors.coral,
              fontSize: 10,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final roster in pool.rosters)
                GestureDetector(
                  onTap: single ? null : () => onRemove(roster.animeId),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: CadreColors.bg,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            roster.title,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              color: CadreColors.ivory,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (!single) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.close,
                            size: 15,
                            color: CadreColors.ivoryFaint,
                          ),
                        ],
                      ],
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

class _ResultRow extends StatelessWidget {
  final CadreAnimeSummary anime;
  final bool added;
  final bool single;
  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _ResultRow({
    required this.anime,
    required this.added,
    required this.single,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy || (added && single) ? null : (added ? onRemove : onAdd),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: CadreColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: added ? CadreColors.coralEdge : CadreColors.hairline,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 62,
                child: anime.coverUrl.isEmpty
                    ? const ColoredBox(color: CadreColors.bg)
                    : CachedNetworkImage(
                        imageUrl: anime.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const ColoredBox(color: CadreColors.bg),
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: CadreColors.bg),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      color: CadreColors.ivory,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  if (anime.seasonYear != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${anime.seasonYear}',
                      style: GoogleFonts.spaceGrotesk(
                        color: CadreColors.ivoryFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  _CastBadge(
                    drawable: anime.drawableFor(
                      CadreRosterService.defaultCastLimit,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              height: 34,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CadreColors.coral,
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: added ? CadreColors.coral : CadreColors.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        added ? Icons.check : Icons.add,
                        size: 18,
                        color: added ? Colors.white : CadreColors.ivoryDim,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tells you what a cast buys you before you commit to it.
///
/// A raw character count means nothing to a player, so this says it in rounds.
/// Searching a popular series returns the show plus its films and spinoffs,
/// and a film's cast is thin — picking one gives a short match, which reads as
/// the game being shallow rather than the pick being wrong.
///
/// Deliberately shows rather than filters. Hiding non-TV results would also
/// bury the ONAs and specials that do carry a full cast.
class _CastBadge extends StatelessWidget {
  /// Characters that could actually be drafted, already capped at the fetch
  /// limit. Null when AniList didn't return a count — then nothing is shown,
  /// because a guess here is worse than silence.
  final int? drawable;

  const _CastBadge({required this.drawable});

  @override
  Widget build(BuildContext context) {
    final n = drawable;
    if (n == null) return const SizedBox.shrink();

    final playable = n >= CadreMatch.minRosterSize;
    final full = n >= CadreMatch.fullMatchRosterSize;

    final String label;
    if (!playable) {
      label = 'Too few characters to play';
    } else if (full) {
      label = 'Full cast';
    } else {
      // "Up to", not "is": the count includes characters who get dropped for
      // having no usable art, so the real match can be shorter than this.
      label = 'Up to $n \u00B7 about ${CadreMatch.roundsFor(n)} rounds';
    }

    final color = full ? CadreColors.ivoryFaint : CadreColors.coral;

    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            full ? Icons.check_circle_outline : Icons.info_outline_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;

  const _SearchField({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSubmit(),
      textInputAction: TextInputAction.search,
      style: GoogleFonts.dmSans(color: CadreColors.ivory, fontSize: 15),
      cursorColor: CadreColors.coral,
      decoration: InputDecoration(
        hintText: 'Search anime',
        hintStyle: GoogleFonts.dmSans(
          color: CadreColors.ivoryFaint,
          fontSize: 15,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: CadreColors.ivoryFaint,
          size: 20,
        ),
        filled: true,
        fillColor: CadreColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CadreColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CadreColors.coralEdge),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String title;
  final bool added;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.title,
    required this.added,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 10, added ? 10 : 14, 10),
        decoration: BoxDecoration(
          color: CadreColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: added ? CadreColors.coralEdge : CadreColors.hairline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: GoogleFonts.dmSans(
                color: added ? CadreColors.coral : CadreColors.ivoryDim,
                fontSize: 13,
                fontWeight: added ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (added) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, size: 14, color: CadreColors.coral),
            ],
          ],
        ),
      ),
    );
  }
}
