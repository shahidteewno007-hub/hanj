import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hanko_seal.dart';
import '../anime_detail/anime_detail_screen.dart';
import '../../models/anime_model.dart';
import 'my_list_landing.dart';

class MyListScreen extends StatefulWidget {
  final String? initialStatus;
  /// True when pushed as a route (Home's "SEE ALL →") rather than shown as
  /// the List tab. A pushed copy covers the nav bar and, on web, has no
  /// system back gesture, so it draws its own way back.
  final bool showBackButton;
  const MyListScreen({
    super.key,
    this.initialStatus,
    this.showBackButton = false,
  });

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  /// Vibes for My List (Print Room, r9; Shahid, 2026-11-10: "I loved new
  /// vibes change, if we can bring that change to other tabs/features
  /// wherever needed"): printed status tabs, the selected status as a board
  /// holding its newest covers in a pose that says what the status means,
  /// rows as prints with your rating as your seal (not a gold star), statuses
  /// in words (no status colours), labelled square buttons. False gives back
  /// 07faabe's list as it was.
  static const bool _printRoom = true;

  /// A lighter open for the Vibes list (r9, 2026-11-11; Shahid: "fix My
  /// List"), drawn exactly as before:
  ///  - each snapshot's titles are read once. A document's data() copies the
  ///    whole document each time it's called, and every build called it
  ///    about 3,800 times on a 172-title list (twice per comparison of the
  ///    sort, then for each status count and the board);
  ///  - the counts per status, which only the old list shows, aren't worked
  ///    out;
  ///  - the search field, the status tabs and the two square buttons are
  ///    kept from one build to the next while what they show is unchanged,
  ///    so the list landing (or any rebuild of it) doesn't rebuild them: they
  ///    were about a third of the widgets built the frame it landed in;
  ///  - the frame the list lands in builds only the rows on screen, and the
  ///    rows just below them follow a frame later (MyListLanding).
  /// False gives 27e16b1 back.
  static const bool _lightOpen = true;

  // _lightOpen: the snapshot last read, its titles in its own order, and
  // each title's data, read once.
  QuerySnapshot? _readFrom;
  List<QueryDocumentSnapshot> _readDocs = const [];
  Map<QueryDocumentSnapshot, Map<String, dynamic>> _read = Map.identity();

  // _lightOpen: widgets kept from the last build, by slot, with what they
  // were made from.
  final Map<String, (Object?, Widget)> _kept = {};

  /// [fresh], or with _lightOpen the widget kept in [slot] if it was made
  /// from the same [from]. Flutter doesn't rebuild a widget it's handed
  /// again, so a kept one costs nothing. Only for widgets that depend on
  /// nothing but [from] and the state's own fields.
  Widget _keep(String slot, Object? from, Widget fresh) {
    if (!_lightOpen) return fresh;
    final kept = _kept[slot];
    if (kept != null && kept.$1 == from) return kept.$2;
    _kept[slot] = (from, fresh);
    return fresh;
  }

  // The titles the shuffle button picks from: the list as last built.
  List<QueryDocumentSnapshot> _shuffleFrom = const [];

  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'ALL';
  String _sortBy = 'recent';

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null) {
      _selectedStatus = widget.initialStatus!;
    }
  }

  final _statuses = ['ALL', 'WATCHING', 'COMPLETED', 'PLAN_TO_WATCH', 'DROPPED'];
  final _statusLabels = {
    'ALL': 'All',
    'WATCHING': 'Watching',
    'COMPLETED': 'Completed',
    'PLAN_TO_WATCH': 'Plan',
    'DROPPED': 'Dropped',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatWatchTime(int totalEpisodes) {
    final minutes = totalEpisodes * 24;
    final days = minutes ~/ (60 * 24);
    final hours = (minutes % (60 * 24)) ~/ 60;
    if (days > 0) return '${days}D ${hours}H';
    return '${hours}H';
  }

  List<QueryDocumentSnapshot> _filterAndSort(
      List<QueryDocumentSnapshot> docs) {
    var filtered = docs;

    if (_selectedStatus != 'ALL') {
      filtered = filtered
          .where((d) =>
              (d.data() as Map)['status'] == _selectedStatus)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) {
        final title =
            ((d.data() as Map)['title'] as String? ?? '').toLowerCase();
        return title.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    filtered.sort((a, b) {
      final da = a.data() as Map<String, dynamic>;
      final db = b.data() as Map<String, dynamic>;
      switch (_sortBy) {
        case 'title':
          return (da['title'] as String? ?? '')
              .compareTo(db['title'] as String? ?? '');
        case 'rating':
          final rA = (da['userRating'] as num?)?.toDouble() ?? 0.0;
          final rB = (db['userRating'] as num?)?.toDouble() ?? 0.0;
          return rB.compareTo(rA);
        default:
          final tA = da['addedAt'] as Timestamp?;
          final tB = db['addedAt'] as Timestamp?;
          if (tA == null || tB == null) return 0;
          return tB.compareTo(tA);
      }
    });

    return filtered;
  }

  static Map<String, dynamic> _dataOf(QueryDocumentSnapshot d) =>
      d.data() as Map<String, dynamic>;

  // _lightOpen: the Vibes list as build() makes it, from titles read once.
  // It filters and sorts as _filterAndSort does, on the same lists in the
  // same order, so the order (ties included) is the same: with every status
  // shown and no search, the sort orders allDocs itself, as before.
  Widget _light(BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
    final query = snapshot.data;
    if (!identical(query, _readFrom)) {
      _readFrom = query;
      _readDocs = query?.docs ?? const [];
      _read = Map.identity();
      for (final d in _readDocs) {
        _read[d] = _dataOf(d);
      }
    }
    final read = _read;
    Map<String, dynamic> dataOf(QueryDocumentSnapshot d) => read[d]!;

    final allDocs = List.of(_readDocs);
    var filtered = allDocs;
    if (_selectedStatus != 'ALL') {
      filtered = filtered
          .where((d) => dataOf(d)['status'] == _selectedStatus)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) {
        final title = (dataOf(d)['title'] as String? ?? '').toLowerCase();
        return title.contains(_searchQuery.toLowerCase());
      }).toList();
    }
    filtered.sort((a, b) {
      final da = dataOf(a);
      final db = dataOf(b);
      switch (_sortBy) {
        case 'title':
          return (da['title'] as String? ?? '')
              .compareTo(db['title'] as String? ?? '');
        case 'rating':
          final rA = (da['userRating'] as num?)?.toDouble() ?? 0.0;
          final rB = (db['userRating'] as num?)?.toDouble() ?? 0.0;
          return rB.compareTo(rA);
        default:
          final tA = da['addedAt'] as Timestamp?;
          final tB = db['addedAt'] as Timestamp?;
          if (tA == null || tB == null) return 0;
          return tB.compareTo(tA);
      }
    });

    int totalEps = 0;
    for (final d in allDocs) {
      final data = dataOf(d);
      if (data['status'] == 'COMPLETED') {
        totalEps += (data['episodes'] as int?) ?? 0;
      } else {
        totalEps += (data['currentEpisode'] as int?) ?? 0;
      }
    }

    return _printed(context, snapshot, allDocs, filtered, snapshot.hasData,
        totalEps, dataOf);
  }

  // Print Room (r9): the sort sheet on sumi 2 with Hanko's sheet corners; the
  // order in use is ticked in washi (coral is only ever your verdicts).
  void _showPrintedSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.hankoSumi2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.hankoSheetRadius)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort by',
                style: AppTheme.hankoSerif(
                    fontSize: AppTheme.hankoFeaturedSize)),
            const SizedBox(height: 12),
            for (final option in [
              ('recent', 'Recently Added'),
              ('title', 'Title A–Z'),
              ('rating', 'My Rating'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: _sortBy == option.$1,
                title: Text(option.$2,
                    style: AppTheme.hankoSans(
                        fontSize: 15,
                        weight: _sortBy == option.$1
                            ? FontWeight.w500
                            : FontWeight.w400)),
                trailing: _sortBy == option.$1
                    ? const Icon(Icons.check_rounded,
                        color: AppTheme.hankoWashi)
                    : null,
                onTap: () {
                  setState(() => _sortBy = option.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // Print Room (r9): the shuffle button's pick, as the old header's: any
  // title on the list, opened on Detail.
  void _openRandom(List<QueryDocumentSnapshot> allDocs) {
    if (allDocs.isEmpty) return;
    final random =
        allDocs[DateTime.now().millisecondsSinceEpoch % allDocs.length];
    final data = random.data() as Map<String, dynamic>;
    final anime = Anime(
      id: data['animeId']?.toString() ?? '',
      title: data['title'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      averageScore: (data['averageScore'] as num?)?.toDouble(),
      episodes: data['episodes'] as int?,
      genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
      status: data['status'] as String?,
    );
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => AnimeDetailScreen(anime: anime),
    ));
  }

  // The Vibes list's scroll view: with _lightOpen, one that builds only the
  // rows on screen the frame the list lands in.
  Widget _scroll({required bool landed, required List<Widget> slivers}) =>
      _lightOpen
          ? MyListLanding(landed: landed, slivers: slivers)
          : CustomScrollView(slivers: slivers);

  // ── Print Room (r9): the list on a Vibes board, its rows as prints ──
  Widget _printed(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot> snapshot,
    List<QueryDocumentSnapshot> allDocs,
    List<QueryDocumentSnapshot> filtered,
    bool loaded,
    int totalEps,
    Map<String, dynamic> Function(QueryDocumentSnapshot) dataOf,
  ) {
    _shuffleFrom = allDocs;
    // The selected status's shows, newest first, for its board.
    final mine = [
      for (final d in allDocs)
        if (_selectedStatus == 'ALL' ||
            dataOf(d)['status'] == _selectedStatus)
          dataOf(d),
    ]..sort((a, b) {
        final tA = a['addedAt'] as Timestamp?;
        final tB = b['addedAt'] as Timestamp?;
        if (tA == null || tB == null) return 0;
        return tB.compareTo(tA);
      });
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
          borderRadius: corners,
          borderSide: BorderSide(color: c),
        );
    return _scroll(
      landed: loaded,
      slivers: [
        // ── Header ────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).padding.top + 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.showBackButton)
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: AppTheme.textPrimary, size: 20),
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(context),
                        ),
                      Text('My List',
                          style: AppTheme.serif(
                              fontSize: 28, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      // Hidden, not removed, until the list has loaded, so
                      // the header doesn't jump when it does.
                      Visibility(
                        visible: loaded,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Text(
                          '${allDocs.length} TITLES · ${_formatWatchTime(totalEps)}',
                          style: HankoBoard.labelStyle(
                              color: AppTheme.hankoStone),
                        ),
                      ),
                    ],
                  ),
                ),
                _keep('sort', null, _SquareButton(
                  icon: Icons.swap_vert_rounded,
                  label: 'Sort',
                  onTap: _showPrintedSortSheet,
                )),
                const SizedBox(width: 8),
                _keep('shuffle', null, _SquareButton(
                  icon: Icons.shuffle_rounded,
                  label: 'Open one at random',
                  onTap: () => _openRandom(_shuffleFrom),
                )),
              ],
            ),
          ),
        ),

        // ── Search ────────────────────────────────────
        _keep('search', _searchQuery, SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: AppTheme.hankoSans(),
              decoration: InputDecoration(
                hintText: 'Search your list...',
                hintStyle: AppTheme.hankoSans(color: AppTheme.hankoAsh),
                fillColor: AppTheme.hankoSumi3,
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.hankoStone, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded,
                            color: AppTheme.hankoStone, size: 16),
                        tooltip: 'Clear',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: edge(AppTheme.hankoSumi3),
                enabledBorder: edge(AppTheme.hankoSumi3),
                focusedBorder: edge(AppTheme.hankoWashi),
              ),
            ),
          ),
        )),

        // ── Status tabs ───────────────────────────────
        _keep('tabs', _selectedStatus, SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: HankoTabStrip(
              labels: [for (final s in _statuses) _statusLabels[s] ?? s],
              selected: _statuses.indexOf(_selectedStatus),
              onSelect: (i) => setState(() => _selectedStatus = _statuses[i]),
            ),
          ),
        )),

        // ── The selected status, as a board ───────────
        if (loaded && _searchQuery.isEmpty && mine.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _StatusBoard(
                key: ValueKey(_selectedStatus),
                status: _selectedStatus,
                count: mine.length,
                covers: [
                  for (final m in mine.take(3)) m['imageUrl'] as String? ?? '',
                ],
              ),
            ),
          ),

        // ── List ──────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting)
          // Rows as blank paper while the list loads, as everywhere in Hanko.
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 64,
                          height: 64 * hankoCoverRatio,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: AppTheme.hankoSumi3,
                                borderRadius: corners),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Container(
                            height: 14,
                            margin: const EdgeInsets.only(right: 80),
                            color: AppTheme.hankoSumi3,
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            ),
          )
        // A failed read arrives with no data, so allDocs is empty; this
        // keeps it from reading as an empty list.
        else if (snapshot.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Your list can\'t load right now',
                        textAlign: TextAlign.center,
                        style: AppTheme.hankoSerif(
                            fontSize: AppTheme.hankoFeaturedSize)),
                    const SizedBox(height: 8),
                    Text('Try again shortly.',
                        style: AppTheme.hankoSans(
                            color: AppTheme.hankoStone)),
                  ],
                ),
              ),
            ),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HankoEmptyHand(),
                    const SizedBox(height: 20),
                    Text('Nothing here',
                        style: AppTheme.hankoSerif(
                            fontSize: AppTheme.hankoFeaturedSize)),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No results for "$_searchQuery"'
                          : 'Add some anime to get started',
                      textAlign: TextAlign.center,
                      style: AppTheme.hankoSans(color: AppTheme.hankoStone),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.only(top: 12),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final data = dataOf(filtered[i]);
                  return _ListRow(
                    key: ValueKey(data['animeId']),
                    data: data,
                    firestoreService: _firestoreService,
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort by',
                style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
            const SizedBox(height: 16),
            for (final option in [
              ('recent', 'Recently Added'),
              ('title', 'Title A–Z'),
              ('rating', 'My Rating'),
            ])
              ListTile(
                title: Text(option.$2,
                    style: AppTheme.sans(
                        fontSize: 15,
                        color: _sortBy == option.$1
                            ? AppTheme.primary
                            : AppTheme.textPrimary)),
                trailing: _sortBy == option.$1
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _sortBy = option.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getAnimeList(),
        builder: (context, snapshot) {
          if (_printRoom && _lightOpen) return _light(context, snapshot);
          final allDocs = snapshot.data?.docs ?? [];
          final filtered = _filterAndSort(allDocs);
          // No snapshot yet, or the read failed (an error arrives with no
          // data). allDocs is empty either way, so the counts below would
          // all be 0 for a list that may well have titles in it.
          final loaded = snapshot.hasData;

          // Count per status
          final counts = <String, int>{'ALL': allDocs.length};
          for (final s in _statuses.skip(1)) {
            counts[s] = allDocs
                .where((d) => (d.data() as Map)['status'] == s)
                .length;
          }

          // Total watch time
          int totalEps = 0;
          for (final d in allDocs) {
            final data = d.data() as Map<String, dynamic>;
            if (data['status'] == 'COMPLETED') {
              totalEps += (data['episodes'] as int?) ?? 0;
            } else {
              totalEps += (data['currentEpisode'] as int?) ?? 0;
            }
          }

          if (_printRoom) {
            return _printed(context, snapshot, allDocs, filtered, loaded,
                totalEps, _dataOf);
          }

          return CustomScrollView(
            slivers: [
              // ── Header ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 4, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.showBackButton)
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: AppTheme.textPrimary, size: 20),
                                tooltip: 'Back',
                                onPressed: () => Navigator.pop(context),
                              ),
                            Text('My List',
                                style: AppTheme.serif(
                                    fontSize: 28,
                                    weight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            // Hidden, not removed, until the list has loaded,
                            // so the header doesn't jump when it does.
                            Visibility(
                              visible: loaded,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Text(
                                '${allDocs.length} TITLES · ${_formatWatchTime(totalEps)}',
                                style: AppTheme.mono(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                    letterSpacing: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Sort button
                      GestureDetector(
                        onTap: _showSortSheet,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(Icons.swap_vert_rounded,
                              color: AppTheme.textSecondary, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Random pick button
                      GestureDetector(
                        onTap: () {
                          final allDocs = snapshot.data?.docs ?? [];
                          if (allDocs.isEmpty) return;
                          final random = allDocs[DateTime.now().millisecondsSinceEpoch % allDocs.length];
                          final data = random.data() as Map<String, dynamic>;
                          final anime = Anime(
                            id: data['animeId']?.toString() ?? '',
                            title: data['title'] as String? ?? '',
                            imageUrl: data['imageUrl'] as String?,
                            averageScore: (data['averageScore'] as num?)?.toDouble(),
                            episodes: data['episodes'] as int?,
                            genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
                            status: data['status'] as String?,
                          );
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AnimeDetailScreen(anime: anime),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(Icons.shuffle_rounded,
                              color: AppTheme.textSecondary, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: AppTheme.sans(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search your list...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.textMuted, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: AppTheme.textMuted, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              // ── Status filter tabs ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _statuses.map((s) {
                        final selected = _selectedStatus == s;
                        final count = counts[s] ?? 0;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedStatus = s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.textPrimary
                                    : AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.textPrimary
                                      : AppTheme.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _statusLabels[s] ?? s,
                                    style: AppTheme.sans(
                                      fontSize: 13,
                                      weight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.textInverse
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Same as the header: no count until the
                                  // list has loaded, keeping the chip's width.
                                  Visibility(
                                    visible: loaded,
                                    maintainSize: true,
                                    maintainAnimation: true,
                                    maintainState: true,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppTheme.textInverse
                                                .withValues(alpha: 0.15)
                                            : AppTheme.surfaceMid,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: AppTheme.mono(
                                          fontSize: 10,
                                          weight: FontWeight.w600,
                                          color: selected
                                              ? AppTheme.textInverse
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // ── List ──────────────────────────────────────
              snapshot.connectionState == ConnectionState.waiting
                  ? const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 1.5),
                      ),
                    )
                  // A failed read arrives with no data, so allDocs is empty;
                  // without this it rendered as "Add some anime to get
                  // started", as if the list itself were gone.
                  : snapshot.hasError
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppTheme.textMuted, size: 48),
                                const SizedBox(height: 16),
                                Text('Your list can\'t load right now',
                                    style: AppTheme.serif(
                                        fontSize: 20,
                                        weight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(
                                  'Try again shortly.',
                                  style: AppTheme.sans(
                                      fontSize: 14,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                  : filtered.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('📭',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text('Nothing here',
                                    style: AppTheme.serif(
                                        fontSize: 20,
                                        weight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No results for "$_searchQuery"'
                                      : 'Add some anime to get started',
                                  style: AppTheme.sans(
                                      fontSize: 14,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == 0) {
                                return const SizedBox(height: 16);
                              }
                              final i = index - 1;
                              if (i >= filtered.length) return null;
                              final data = filtered[i].data()
                                  as Map<String, dynamic>;
                              return _ListRow(
                                key: ValueKey(data['animeId']),
                                data: data,
                                firestoreService: _firestoreService,
                              );
                            },
                            childCount: filtered.length + 1,
                          ),
                        ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final FirestoreService firestoreService;

  const _ListRow({super.key, required this.data, required this.firestoreService});

  /// The bar beside "9/12" on a show you're watching, switched off. Shahid,
  /// 2026-11-05: "I don't like the episode count lines that show like how
  /// many episodes you have watched, remove that just have 9 of 12". The
  /// count stays, and says "watched" to a screen reader.
  static const bool _progressBar = false;

  Color _statusColor(String s) {
    switch (s) {
      case 'WATCHING':      return AppTheme.watching;
      case 'COMPLETED':     return AppTheme.completed;
      case 'PLAN_TO_WATCH': return AppTheme.planToWatch;
      case 'DROPPED':       return AppTheme.dropped;
      default:              return AppTheme.textMuted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'WATCHING':      return 'WATCHING';
      case 'COMPLETED':     return 'COMPLETED';
      case 'PLAN_TO_WATCH': return 'PLAN';
      case 'DROPPED':       return 'DROPPED';
      default:              return s;
    }
  }

  void _open(BuildContext context) {
    final anime = Anime(
      id: data['animeId']?.toString() ?? '',
      title: data['title'] as String? ?? 'Unknown',
      imageUrl: data['imageUrl'] as String?,
      episodes: data['episodes'] as int?,
      genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
      averageScore: (data['averageScore'] as num?)?.toDouble(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
    );
  }

  // Print Room (r9): a print and your seal. The cover is a printed card, the
  // status is said in words (no status colours: coral is only your verdict),
  // and your rating is your seal, as on Detail and Profile, not a gold star.
  // Swipe to remove is as before.
  Widget _printed(BuildContext context) {
    final title = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final status = data['status'] as String? ?? '';
    final current = (data['currentEpisode'] as int?) ?? 0;
    final total = data['episodes'] as int?;
    final userRating = (data['userRating'] as num?)?.toDouble();
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final animeId = int.tryParse(data['animeId']?.toString() ?? '0') ?? 0;
    final words = switch (status) {
      'WATCHING' => total != null ? 'Watching · $current of $total' : 'Watching',
      'COMPLETED' => 'Completed',
      'PLAN_TO_WATCH' => 'Plan to watch',
      'DROPPED' => 'Dropped',
      _ => status,
    };
    final meta = [
      if (genres.isNotEmpty) genres.first.toUpperCase(),
      if (total != null) '$total EP',
    ].join(' · ');
    return Dismissible(
      key: ValueKey(animeId),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppTheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.hankoSumi2,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                  Radius.circular(AppTheme.hankoSheetRadius)),
            ),
            title: Text('Remove from list',
                style: AppTheme.hankoSerif(
                    fontSize: AppTheme.hankoFeaturedSize)),
            content: Text('Remove "$title" from your list?',
                style: AppTheme.hankoSans(color: AppTheme.hankoStoneHi)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: AppTheme.hankoSans(weight: FontWeight.w500)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Remove',
                    style: AppTheme.hankoSans(
                        weight: FontWeight.w500, color: AppTheme.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => firestoreService.removeAnimeFromList(animeId),
      child: Semantics(
        container: true,
        button: true,
        label: [
          title,
          words,
          if (userRating != null)
            'your rating ${HankoSeal.formatScore(userRating)}',
        ].join(', '),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _open(context),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            hoverColor: AppTheme.hankoPressWash,
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64 * hankoCoverRatio,
                      child: HankoCard(url: imageUrl),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoListTitleSize,
                              weight: FontWeight.w500,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(meta,
                                style: HankoBoard.labelStyle(
                                    color: AppTheme.hankoStone)),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            words,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              color: AppTheme.hankoStone,
                              tabular: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (userRating != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: HankoSeal.score(userRating, size: 32),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_MyListScreenState._printRoom) return _printed(context);
    final title = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final status = data['status'] as String? ?? '';
    final current = (data['currentEpisode'] as int?) ?? 0;
    final total = data['episodes'] as int?;
    final userRating = (data['userRating'] as num?)?.toDouble();
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final animeId =
        int.tryParse(data['animeId']?.toString() ?? '0') ?? 0;
    final progress = total != null && total > 0
        ? (current / total).clamp(0.0, 1.0)
        : 0.0;
    final statusColor = _statusColor(status);

    return Dismissible(
      key: ValueKey(animeId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded,
            color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surfaceMid,
            title: Text('Remove from list',
                style: AppTheme.serif(
                    fontSize: 18, weight: FontWeight.w600)),
            content: Text('Remove "$title" from your list?',
                style: AppTheme.sans(
                    fontSize: 14, color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: AppTheme.sans(color: AppTheme.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Remove',
                    style: AppTheme.sans(color: AppTheme.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => firestoreService.removeAnimeFromList(animeId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final anime = Anime(
              id: data['animeId']?.toString() ?? '',
              title: title,
              imageUrl: imageUrl,
              episodes: total,
              genres: genres,
              averageScore:
                  (data['averageScore'] as num?)?.toDouble(),
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AnimeDetailScreen(anime: anime)),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 96,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                Container(color: AppTheme.surfaceMid),
                          )
                        : Container(color: AppTheme.surfaceMid),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        style: AppTheme.sans(
                            fontSize: 15, weight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Genre · Season · Episodes
                      Text(
                        [
                          if (genres.isNotEmpty)
                            genres.first.toUpperCase(),
                          if (total != null) '$total EP',
                        ].join(' · '),
                        style: AppTheme.mono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      // Status badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: AppTheme.mono(
                                  fontSize: 9,
                                  weight: FontWeight.w600,
                                  color: statusColor,
                                  letterSpacing: 0.8),
                            ),
                          ),
                          if (userRating != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded,
                                color: AppTheme.accent, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              userRating.toStringAsFixed(1),
                              style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.accent,
                                  weight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                      // Progress bar (watching only). Since 2026-11-05 only
                      // its count shows (_progressBar).
                      if (status == 'WATCHING' && total != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_progressBar) ...[
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: AppTheme.border,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            statusColor),
                                    minHeight: 3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '$current/$total',
                              semanticsLabel: '$current of $total watched',
                              style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Print Room (r9)
// ─────────────────────────────────────────────────────────────

/// A square icon button (Print Room, r9): drawn 40 dp on sumi 3 with Hanko's
/// 2 px corners, touched at 48, and named for a screen reader.
class _SquareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SquareButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        label: label,
        child: SizedBox(
          width: AppTheme.hankoTouch,
          height: AppTheme.hankoTouch,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                child: ExcludeSemantics(
                  child: Ink(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.hankoSumi3,
                      borderRadius:
                          BorderRadius.circular(AppTheme.hankoRadius),
                    ),
                    child:
                        Icon(icon, color: AppTheme.hankoWashi, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The selected status as a Vibes board (Print Room, r9): its name, a line on
/// what it is, its count as a printed label, and its newest covers in a hand
/// posed for what the status means, tinted by them:
///  - Everything: Vibes' fan;
///  - Watching: held like cards in play (a splay);
///  - Completed: upright, shoulder to shoulder, shelved;
///  - Plan to watch: volumes waiting their turn in the dark;
///  - Dropped: falling away under veils.
/// The hand deals in the first time a status shows in a session. One node for
/// a screen reader; the rows below name the shows.
class _StatusBoard extends StatefulWidget {
  final String status;
  final int count;
  final List<String> covers;

  const _StatusBoard({
    super.key,
    required this.status,
    required this.count,
    required this.covers,
  });

  @override
  State<_StatusBoard> createState() => _StatusBoardState();
}

class _StatusBoardState extends State<_StatusBoard> {
  static final Set<String> _dealt = {};
  late final bool _dealIn = _dealt.add(widget.status);

  static (String, String, List<HankoPose>) _words(String status) =>
      switch (status) {
        'WATCHING' => ('Watching', 'In your hands now', HankoPose.splay),
        'COMPLETED' => ('Completed', 'Seen through to the end', HankoPose.level),
        'PLAN_TO_WATCH' => ('Plan to watch', 'Waiting their turn', HankoPose.recede),
        'DROPPED' => ('Dropped', 'Set down for now', HankoPose.fallAway),
        _ => ('Everything', 'All you’ve kept, newest first', HankoPose.fan),
      };

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final (name, tagline, poses) = _words(widget.status);
    final n = widget.count;
    // A status with fewer than three shows holds only those.
    final held = [
      for (final p in poses)
        if (p.cover < widget.covers.length) p,
    ];
    return Semantics(
      container: true,
      label: '$name. $tagline. $n ${n == 1 ? 'title' : 'titles'}',
      child: ExcludeSemantics(
        child: HankoCoverTint(
          urls: widget.covers,
          builder: (context, tint) => HankoBoard(
            tint: tint,
            face: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoFeaturedSize,
                              height: 1.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tagline,
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStoneHi,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$n ${n == 1 ? 'TITLE' : 'TITLES'}',
                          style: HankoBoard.labelStyle(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  HankoHand(
                    poses: held,
                    urls: widget.covers,
                    coverWidth: 40,
                    lifted: false,
                    dealIn: _dealIn && !still,
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
