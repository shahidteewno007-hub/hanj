// Tier lists: picking characters.
//
// Search an anime and open its cast, or search characters by name across
// every anime. Picks are kept while you move between searches, so one visit
// can gather a whole cross-anime list ("Add 8"). Searches wait until typing
// pauses (450 ms) and answers are kept (tier_list_anilist.dart), so going
// back to a search costs no request.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import 'tier_list_anilist.dart';
import 'tier_list_model.dart';
import 'tier_list_widgets.dart';

/// Suggested first searches, from the list's template.
class TierSearchIdeas {
  const TierSearchIdeas({this.anime = const [], this.characters = const []});
  final List<String> anime;
  final List<String> characters;
  bool get isEmpty => anime.isEmpty && characters.isEmpty;
}

/// The tier a pick is for (round nine): what was picked lands there, and
/// the header names it in the tier's own colour.
class TierPickTarget {
  const TierPickTarget({required this.label, required this.pigment});
  final String label;
  final TierPigment pigment;
}

enum _Mode { anime, characters }

class TierCharacterPickerScreen extends StatefulWidget {
  const TierCharacterPickerScreen({
    super.key,
    required this.alreadyOnList,
    required this.room,
    this.ideas = const TierSearchIdeas(),
    this.target,
    this.waiting = const [],
    this.listAnime = const [],
    this.fromOtherLists = const [],
    this.single = false,
    this.current,
  });

  /// Character ids already on the list; shown as such and not pickable.
  final Set<int> alreadyOnList;

  /// How many more the list can take.
  final int room;
  final TierSearchIdeas ideas;

  /// Round nine: the tier these picks are for, or null for the tray.
  final TierPickTarget? target;

  /// Quick picks, shown before anything is typed (round nine), none of
  /// them a request: characters waiting in the tray (picking one moves them
  /// to [target]), the anime already on the list (tap opens the cast), and
  /// characters from the person's other lists.
  final List<TierCharacter> waiting;
  final List<TierAnime> listAnime;
  final List<TierCharacter> fromOtherLists;

  /// One pick, and the picker closes with it (a gauntlet's slot). Remove
  /// closes with an empty list.
  final bool single;

  /// Who holds the slot now, in [single] mode.
  final TierCharacter? current;

  @override
  State<TierCharacterPickerScreen> createState() => _TierCharacterPickerScreenState();
}

class _TierCharacterPickerScreenState extends State<TierCharacterPickerScreen> {
  final _field = TextEditingController();
  final _fieldFocus = FocusNode();
  Timer? _debounce;

  _Mode _mode = _Mode.anime;
  String _query = '';
  bool _loading = false;
  int? _fail;
  bool _stale = false;
  List<TierAnime> _anime = const [];
  List<TierPick> _people = const [];

  // An open cast.
  TierAnime? _open;
  final List<TierPick> _cast = [];
  int _castPage = 0;
  bool _castMore = false;
  bool _castLoading = false;
  int? _castFail;

  final Map<int, TierCharacter> _picked = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onType(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _query = '';
        _loading = false;
        _fail = null;
        _anime = const [];
        _people = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(q));
  }

  void _setMode(_Mode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _open = null;
      _anime = const [];
      _people = const [];
      _fail = null;
    });
    final q = _field.text.trim();
    if (q.length >= 2) _search(q);
  }

  Future<void> _search(String q) async {
    final mode = _mode;
    setState(() {
      _query = q;
      _loading = true;
      _fail = null;
      _open = null;
    });
    bool wanted() => mounted && _query == q && _mode == mode;
    if (mode == _Mode.anime) {
      final r = await TierListAnilist.instance.searchAnime(q, stillWanted: wanted);
      if (!wanted()) return;
      setState(() {
        _loading = false;
        _anime = r.value ?? const [];
        _fail = r.failStatus;
        _stale = r.stale;
      });
    } else {
      final r = await TierListAnilist.instance.searchCharacters(q, stillWanted: wanted);
      if (!wanted()) return;
      setState(() {
        _loading = false;
        _people = r.value ?? const [];
        _fail = r.failStatus;
        _stale = r.stale;
      });
    }
  }

  void _useIdea(String text, _Mode mode) {
    _debounce?.cancel();
    _field.text = text;
    _field.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _mode = mode);
    _search(text);
  }

  Future<void> _openCast(TierAnime a) async {
    setState(() {
      _open = a;
      _cast.clear();
      _castPage = 0;
      _castMore = false;
      _castFail = null;
    });
    await _loadCast();
  }

  Future<void> _loadCast() async {
    final a = _open;
    if (a == null || _castLoading) return;
    setState(() => _castLoading = true);
    final page = _castPage + 1;
    final r = await TierListAnilist.instance.cast(a.id, page: page);
    if (!mounted || _open?.id != a.id) return;
    setState(() {
      _castLoading = false;
      final v = r.value;
      if (v != null) {
        _castPage = page;
        final have = _cast.map((p) => p.character.id).toSet();
        _cast.addAll(v.picks.where((p) => have.add(p.character.id)));
        _castMore = v.hasNextPage;
      }
      _castFail = r.failStatus;
    });
  }

  bool _onList(int id) => widget.alreadyOnList.contains(id);

  late final Set<int> _waitingIds = {for (final c in widget.waiting) c.id};

  void _toggle(TierCharacter c) {
    if (_onList(c.id)) return;
    if (widget.single) {
      Navigator.of(context).pop(<TierCharacter>[c]);
      return;
    }
    setState(() {
      if (_picked.remove(c.id) == null) {
        if (_picked.length >= widget.room) {
          tierToast(context, widget.room <= 0
              ? 'This list is full (${TierList.maxCharacters} characters).'
              : 'That’s all this list has room for.');
          return;
        }
        _picked[c.id] = c;
      }
    });
  }

  void _pickMain() {
    var n = 0;
    setState(() {
      for (final p in _cast) {
        if (p.role != 'MAIN' || _onList(p.character.id) || _picked.containsKey(p.character.id)) continue;
        if (_picked.length >= widget.room) break;
        _picked[p.character.id] = p.character;
        n++;
      }
    });
    if (n == 0) tierToast(context, 'The main cast is already picked.');
  }

  void _done() => Navigator.of(context).pop(_picked.values.toList());

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _open != null) setState(() => _open = null);
      },
      child: Scaffold(
        backgroundColor: AppTheme.hankoSumi,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                children: [
                  _topBar(),
                  _searchBar(),
                  Expanded(child: _open != null ? _castView() : _resultsView()),
                  _footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, color: AppTheme.hankoWashi),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: widget.target == null
                ? Semantics(
                    header: true,
                    child: Text('Add characters', style: AppTheme.hankoSerif(fontSize: 20)),
                  )
                : _targetTitle(widget.target!),
          ),
        ],
      ),
    );
  }

  /// "Add to [S]", the tier as a chip in its own colour (round nine).
  Widget _targetTitle(TierPickTarget t) {
    final verb = widget.single ? 'Pick for' : 'Add to';
    return Semantics(
      header: true,
      label: '$verb ${t.label}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(verb, style: AppTheme.hankoSerif(fontSize: 20)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.pigment.color,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                ),
                child: Text(
                  t.label,
                  style: AppTheme.hankoSerif(fontSize: 17, color: t.pigment.ink, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ModeTab(
                label: 'Anime',
                selected: _mode == _Mode.anime,
                onTap: () => _setMode(_Mode.anime),
              ),
              const SizedBox(width: 6),
              _ModeTab(
                label: 'Characters',
                selected: _mode == _Mode.characters,
                onTap: () => _setMode(_Mode.characters),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TierTextSelection(
            child: TextField(
              controller: _field,
              focusNode: _fieldFocus,
              autofocus: true,
              onChanged: _onType,
              onSubmitted: (t) {
                _debounce?.cancel();
                if (t.trim().length >= 2) _search(t.trim());
              },
              textInputAction: TextInputAction.search,
              style: AppTheme.hankoSans(fontSize: 16),
              cursorColor: AppTheme.hankoWashi,
              decoration: InputDecoration(
                hintText: _mode == _Mode.anime ? 'Search an anime' : 'Search a character',
                hintStyle: AppTheme.hankoSans(fontSize: 16, color: AppTheme.hankoAsh),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.hankoStone),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _field,
                  builder: (_, v, _) => v.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded, color: AppTheme.hankoStone),
                          onPressed: () {
                            _field.clear();
                            _onType('');
                            _fieldFocus.requestFocus();
                          },
                        ),
                ),
                filled: true,
                fillColor: AppTheme.hankoSumi2,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  borderSide: const BorderSide(color: AppTheme.hankoHairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  borderSide: const BorderSide(color: AppTheme.hankoHairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  borderSide: const BorderSide(color: AppTheme.hankoEdge, width: 1.5),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 2,
            child: (_loading || _castLoading)
                ? const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.hankoWashi,
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_query.isEmpty) return _ideas();
    if (_fail != null && (_mode == _Mode.anime ? _anime.isEmpty : _people.isEmpty)) {
      return _problem(_fail, () => _search(_query));
    }
    final note = _stale ? _staleNote() : null;
    if (_mode == _Mode.anime) {
      if (_anime.isEmpty) return _loading ? const SizedBox.shrink() : _nothing('No anime called “$_query”.');
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _anime.length + (note == null ? 0 : 1),
        itemBuilder: (_, i) {
          if (note != null && i == 0) return note;
          final a = _anime[i - (note == null ? 0 : 1)];
          return _AnimeRow(anime: a, onTap: () => _openCast(a));
        },
      );
    }
    if (_people.isEmpty) return _loading ? const SizedBox.shrink() : _nothing('No characters called “$_query”.');
    return _grid(_people, header: note, showAnime: true);
  }

  Widget _castView() {
    final a = _open!;
    final tint = a.color == null ? null : AppTheme.hankoCoverTint(Color(a.color!));
    // One pick at a time has no use for the whole main cast.
    final mainLeft = !widget.single &&
        _cast.any((p) => p.role == 'MAIN' && !_onList(p.character.id) && !_picked.containsKey(p.character.id));
    final header = Container(
      decoration: tint == null
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint, tint.withValues(alpha: 0)],
              ),
            ),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Back to results',
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.hankoWashi),
            onPressed: () => setState(() => _open = null),
          ),
          if (a.cover != null)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 4),
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 44,
                  height: 66,
                  child: CachedNetworkImage(imageUrl: a.cover!, fit: BoxFit.cover),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Semantics(header: true, child: Text(a.title, style: AppTheme.hankoSerif(fontSize: 18, height: 1.2))),
                const SizedBox(height: 4),
                Text(_facts(a), style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStoneHi)),
                if (mainLeft) ...[
                  const SizedBox(height: 10),
                  TierGhostButton(label: 'Pick the main cast', icon: Icons.done_all_rounded, dense: true, onTap: _pickMain),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (_cast.isEmpty) {
      return Column(
        children: [
          header,
          Expanded(
            child: _castLoading
                ? const SizedBox.shrink()
                : _castFail != null
                    ? _problem(_castFail, _loadCast)
                    : _nothing('AniList lists no characters for this one yet.'),
          ),
        ],
      );
    }
    return _grid(_cast, header: header, footer: _castMore || _castFail != null ? _more() : null);
  }

  Widget _more() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Center(
        child: _castFail != null
            ? Column(
                children: [
                  Text(AnilistService.messageFor(_castFail) ?? '',
                      textAlign: TextAlign.center,
                      style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone)),
                  const SizedBox(height: 8),
                  TierGhostButton(label: 'Try again', icon: Icons.refresh_rounded, dense: true, onTap: _loadCast),
                ],
              )
            : TierGhostButton(
                label: _castLoading ? 'Loading…' : 'Load more characters',
                icon: Icons.expand_more_rounded,
                dense: true,
                onTap: _castLoading ? null : _loadCast,
              ),
      ),
    );
  }

  Widget _grid(List<TierPick> picks, {Widget? header, Widget? footer, bool showAnime = false}) {
    return LayoutBuilder(builder: (context, box) {
      final cols = (box.maxWidth / 116).floor().clamp(3, 7);
      final s = MediaQuery.textScalerOf(context);
      // Portrait (2:3), then two lines of name and one of anime or role,
      // at this text size.
      final extent = (box.maxWidth - 24 - (cols - 1) * 8) / cols * 1.5 +
          5 + s.scale(13) * 1.2 * 2 + s.scale(11) * 1.3 + 8;
      return CustomScrollView(
        slivers: [
          if (header != null) SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
                mainAxisExtent: extent,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final p = picks[i];
                  return _PickTile(
                    pick: p,
                    picked: _picked.containsKey(p.character.id),
                    onList: _onList(p.character.id),
                    waiting: _waitingIds.contains(p.character.id),
                    showAnime: showAnime,
                    onTap: () => _toggle(p.character),
                  );
                },
                childCount: picks.length,
              ),
            ),
          ),
          if (footer != null) SliverToBoxAdapter(child: footer),
        ],
      );
    });
  }

  Widget _ideas() {
    final ideas = widget.ideas;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      children: [
        Text(
          _mode == _Mode.anime
              ? (widget.single
                  ? 'Find an anime, then pick from its cast.'
                  : 'Find an anime, then pick from its cast. Your picks stay while you search another, so one list can mix shows.')
              : 'Find anyone by name, from any anime.',
          style: AppTheme.hankoSans(fontSize: 14, color: AppTheme.hankoStone, height: 1.4),
        ),
        ..._quickPicks(),
        if (!ideas.isEmpty) ...[
          const SizedBox(height: 20),
          if (ideas.characters.isNotEmpty) ...[
            const TierEyebrow('Try these characters'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in ideas.characters)
                  _IdeaChip(label: s, onTap: () => _useIdea(s, _Mode.characters)),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (ideas.anime.isNotEmpty) ...[
            const TierEyebrow('Try these anime'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in ideas.anime) _IdeaChip(label: s, onTap: () => _useIdea(s, _Mode.anime)),
              ],
            ),
          ],
        ],
      ],
    );
  }

  /// Round nine's quick picks, before anything is typed. None asks AniList
  /// anything: the tray, the anime already on the list (their casts are
  /// kept six hours) and the person's other lists.
  List<Widget> _quickPicks() {
    final waiting = [for (final c in widget.waiting) if (!_onList(c.id)) c];
    final others = [for (final c in widget.fromOtherLists) if (!_onList(c.id)) c];
    return [
      if (waiting.isNotEmpty) ...[
        const SizedBox(height: 20),
        TierEyebrow('Waiting in unranked  ·  ${waiting.length}'),
        const SizedBox(height: 8),
        _strip(waiting),
      ],
      if (widget.listAnime.isNotEmpty) ...[
        const SizedBox(height: 20),
        const TierEyebrow('Anime on this list'),
        const SizedBox(height: 2),
        for (final a in widget.listAnime) _AnimeRow(anime: a, onTap: () => _openCast(a)),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 20),
        const TierEyebrow('From your other lists'),
        const SizedBox(height: 8),
        _strip(others),
      ],
    ];
  }

  /// A row of pickable faces that scrolls sideways.
  Widget _strip(List<TierCharacter> people) {
    final s = MediaQuery.textScalerOf(context);
    const w = 64.0;
    // The tile's portrait, two lines of name and one of anime, as _grid
    // measures them.
    final h = w * 1.5 + 5 + s.scale(13) * 1.2 * 2 + s.scale(11) * 1.3 + 4;
    return SizedBox(
      height: h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = people[i];
          return SizedBox(
            width: w,
            child: _PickTile(
              pick: TierPick(c),
              picked: _picked.containsKey(c.id),
              onList: false,
              waiting: false,
              showAnime: true,
              onTap: () => _toggle(c),
            ),
          );
        },
      ),
    );
  }

  Widget _staleNote() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          'Saved results. ${AnilistService.messageFor(_fail) ?? ''}',
          style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoStone),
        ),
      );

  Widget _nothing(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: AppTheme.hankoSans(fontSize: 14, color: AppTheme.hankoStone, height: 1.4)),
      );

  Widget _problem(int? status, VoidCallback retry) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
        child: Column(
          children: [
            Text(
              AnilistService.messageFor(status) ?? 'Fresh data can’t load right now. Try again shortly.',
              textAlign: TextAlign.center,
              style: AppTheme.hankoSans(fontSize: 14, color: AppTheme.hankoStone, height: 1.4),
            ),
            const SizedBox(height: 12),
            TierGhostButton(label: 'Try again', icon: Icons.refresh_rounded, dense: true, onTap: retry),
          ],
        ),
      );

  /// One pick closes the picker, so there is no Add: just who is there now,
  /// with Remove.
  Widget _singleFooter() {
    final now = widget.current;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.hankoSumi2,
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch + 20),
      child: Row(
        children: [
          Expanded(
            child: now == null
                ? Text(
                    'Tap someone to choose them.',
                    style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone),
                  )
                : Row(
                    children: [
                      ExcludeSemantics(child: CharacterPortrait(character: now, width: 26, showName: false)),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Now: ${now.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w500, color: AppTheme.hankoStoneHi),
                        ),
                      ),
                    ],
                  ),
          ),
          if (now != null) ...[
            const SizedBox(width: 10),
            TierGhostButton(
              label: 'Remove',
              icon: Icons.close_rounded,
              dense: true,
              onTap: () => Navigator.of(context).pop(const <TierCharacter>[]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer() {
    if (widget.single) return _singleFooter();
    final n = _picked.length;
    final faces = _picked.values.toList().reversed.take(5).toList();
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.hankoSumi2,
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: n == 0
                ? Text(
                    'Tap characters to pick them.',
                    style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone),
                  )
                : Row(
                    children: [
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 42,
                          width: 22.0 + 14 * (faces.length - 1) + 6,
                          child: Stack(
                            children: [
                              for (var i = faces.length - 1; i >= 0; i--)
                                Positioned(
                                  left: 14.0 * i,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: AppTheme.hankoSumi2, width: 1.5),
                                    ),
                                    child: CharacterPortrait(character: faces[i], width: 26, showName: false),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          n == 1 ? '1 picked' : '$n picked',
                          style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w500, color: AppTheme.hankoStoneHi),
                        ),
                      ),
                    ],
                  ),
          ),
          TierMainButton(
            label: n == 0 ? 'Add' : 'Add $n',
            icon: Icons.check_rounded,
            onTap: n == 0 ? null : _done,
          ),
        ],
      ),
    );
  }

  static String _facts(TierAnime a) {
    final f = switch (a.format) {
      null => null,
      'TV' => 'TV',
      'TV_SHORT' => 'TV short',
      'MOVIE' => 'Movie',
      'SPECIAL' => 'Special',
      'OVA' => 'OVA',
      'ONA' => 'ONA',
      'MUSIC' => 'Music',
      final other => other,
    };
    return [if (a.year != null) '${a.year}', ?f].join('  ·  ');
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TierPressable(
      label: 'Search ${label.toLowerCase()}',
      selected: selected,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTheme.hankoSans(
                  fontSize: 14,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppTheme.hankoWashi : AppTheme.hankoStone,
                ),
              ),
              const SizedBox(height: 4),
              Container(width: 24, height: 2, color: selected ? AppTheme.hankoWashi : Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }
}

class _IdeaChip extends StatelessWidget {
  const _IdeaChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TierPressable(
      label: 'Search $label',
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
        child: Center(
          widthFactor: 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoChipHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.hankoSumi2,
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              border: Border.all(color: AppTheme.hankoHairline),
            ),
            child: Text(label, style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

class _AnimeRow extends StatelessWidget {
  const _AnimeRow({required this.anime, required this.onTap});
  final TierAnime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final facts = _TierCharacterPickerScreenState._facts(anime);
    final tint = anime.color == null ? AppTheme.hankoEdge : Color(anime.color!);
    return TierPressable(
      label: '${anime.title}${facts.isEmpty ? '' : ', $facts'}',
      hint: 'Opens its characters',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 66,
              decoration: BoxDecoration(
                color: AppTheme.hankoSumi3,
                border: Border(bottom: BorderSide(color: tint, width: 2)),
              ),
              child: anime.cover == null
                  ? null
                  : CachedNetworkImage(imageUrl: anime.cover!, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.hankoSerif(fontSize: AppTheme.hankoListTitleSize, height: 1.25)),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(facts, style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoStone)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.hankoAsh),
          ],
        ),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.pick,
    required this.picked,
    required this.onList,
    required this.waiting,
    required this.showAnime,
    required this.onTap,
  });

  final TierPick pick;
  final bool picked;
  final bool onList;

  /// In the unranked tray (round nine): pickable, and picking moves them.
  final bool waiting;
  final bool showAnime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = pick.character;
    final role = switch (pick.role) {
      'MAIN' => 'Main',
      'SUPPORTING' => 'Supporting',
      'BACKGROUND' => 'Background',
      _ => null,
    };
    final sub = showAnime ? c.mediaTitle : role;
    final state = onList
        ? 'already on this list'
        : '${waiting ? 'waiting in unranked, ' : ''}${picked ? 'picked' : 'not picked'}';
    return TierPressable(
      label: '${c.name}${sub == null ? '' : ', $sub'}, $state',
      selected: picked,
      onTap: onList ? null : onTap,
      child: LayoutBuilder(builder: (context, box) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: onList ? 0.35 : 1,
                  child: CharacterPortrait(character: c, width: box.maxWidth, showName: false),
                ),
                if (picked || onList)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: picked ? AppTheme.hankoWashi : AppTheme.hankoEdge,
                          width: picked ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
                if (picked)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(color: AppTheme.hankoWashi, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 16, color: AppTheme.hankoSumi),
                    ),
                  ),
                if (onList || waiting)
                  Positioned(
                    left: 6,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      color: AppTheme.hankoSumi,
                      child: Text(onList ? 'On list' : 'Unranked',
                          style: AppTheme.hankoSans(fontSize: 11, weight: FontWeight.w500)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              c.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w500, height: 1.2),
            ),
            if (sub != null)
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.hankoSans(fontSize: 11, color: AppTheme.hankoStone, height: 1.3),
              ),
          ],
        );
      }),
    );
  }
}
