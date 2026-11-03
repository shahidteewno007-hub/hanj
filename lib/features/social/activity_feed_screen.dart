import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/hanko_seal.dart';

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen>
    with SingleTickerProviderStateMixin {
  final _firestoreService = FirestoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _friendsActivity = [];
  bool _isLoadingFriends = true;

  // Hanko's press: an 8% washi wash, no ripple, square corners (Profile's).
  static const ButtonStyle _pressStyle = ButtonStyle(
    overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
    splashFactory: NoSplash.splashFactory,
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    )),
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFriendsActivity();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFriendsActivity() async {
    setState(() => _isLoadingFriends = true);
    try {
      final activity = await _firestoreService.getFriendsActivity();
      if (!mounted) return;
      setState(() {
        _friendsActivity = activity;
        _isLoadingFriends = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingFriends = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Detail's tabs in Hanko (H3): Jost 13, washi and 600 for the tab you're
    // on, stone for the other, a square 2 px washi line under it and the
    // border's rule across. No coral (it marks only your verdicts now) and
    // no ripple: Hanko presses with an 8% washi wash.
    final tabs = TabBar(
      controller: _tabController,
      labelColor: AppTheme.hankoWashi,
      unselectedLabelColor: AppTheme.hankoStone,
      labelStyle: AppTheme.hankoSans(
          fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w600),
      unselectedLabelStyle:
          AppTheme.hankoSans(fontSize: AppTheme.hankoMetaSize),
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppTheme.hankoWashi, width: 2),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: AppTheme.border,
      dividerHeight: 1,
      overlayColor: const WidgetStatePropertyAll(AppTheme.hankoPressWash),
      splashFactory: NoSplash.splashFactory,
      tabs: const [
        Tab(text: 'Friends'),
        Tab(text: 'My Activity'),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        // Detail's back arrow (Hanko H3), with the same pop as BackButton.
        leading: IconButton(
          tooltip: 'Back',
          style: _pressStyle,
          icon: const Icon(Icons.arrow_back_sharp, color: AppTheme.hankoWashi),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Activity Feed'),
        // On a wide window the two tabs keep the page's column instead of
        // splitting the whole width between them.
        bottom: Responsive.isDesktop(context)
            ? PreferredSize(
                preferredSize: tabs.preferredSize,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxWidth: Responsive.proseMaxWidth +
                            2 * AppTheme.hankoGutter),
                    child: tabs,
                  ),
                ),
              )
            : tabs,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildMyActivityTab(),
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    if (_isLoadingFriends) {
      return _spinner();
    }

    // Hanko's empty state: one Mincho sentence at the top of the page and a
    // quiet line, no emoji. The line says what the tab is for rather than
    // asking you to follow someone, which nothing in the app can do yet.
    // Refresh keeps its callback, as a secondary tile instead of coral.
    if (_friendsActivity.isEmpty) {
      return _note(
        'No activity from friends yet.',
        'When people you follow add or finish a show, it appears\u00A0here.',
        action: _TextTile(label: 'Refresh', onTap: _loadFriendsActivity),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriendsActivity,
      color: AppTheme.hankoWashi,
      backgroundColor: AppTheme.hankoSumi3,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _friendsActivity.length,
        itemBuilder: (context, index) =>
            _ActivityCard(data: _friendsActivity[index]),
      ),
    );
  }

  Widget _buildMyActivityTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getMyActivity(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _spinner();
        }

        // A failed read says so in Profile's words (stage H5), naming no
        // cause the app can't verify. The sentence is Shippori, which draws
        // the typewriter apostrophe as a straight tick, so it takes the
        // typographic one, as Profile's does (question 109).
        if (snapshot.hasError) {
          return _note('Couldn’t load your activity just now.', null);
        }

        // The same words as before, as Hanko's empty state.
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _note('No activity yet.',
              'Start adding anime to your list to see your activity here.');
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _ActivityCard(data: data, showUser: false);
          },
        );
      },
    );
  }

  /// Hanko's loading mark, as Home's: a thin washi ring, 20 px.
  Widget _spinner() => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              color: AppTheme.hankoWashi, strokeWidth: 1.5),
        ),
      );

  /// Hanko's empty and failed states, as Profile's: one Mincho sentence at
  /// the top of the page, a quiet line in stone under it, and an optional
  /// tile, in the page's column. It scrolls, so large text never clips it.
  Widget _note(String sentence, String? line, {Widget? action}) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        _hankoColumn(
          context,
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sentence,
                    style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
                if (line != null) ...[
                  const SizedBox(height: 6),
                  Text(line,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        color: AppTheme.hankoStone,
                        height: 1.4,
                      )),
                ],
                if (action != null) ...[
                  const SizedBox(height: 16),
                  action,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showUser;

  const _ActivityCard({required this.data, this.showUser = true});

  /// The card before Hanko (question 73): a rounded sumi 3 card, a 52 x 72
  /// poster, the line as a RichText with no font family and no text scaler
  /// (so it rendered in the engine's default font at a fixed size), and a
  /// coloured badge with an emoji. Kept, switched off, as design history and
  /// a deletion candidate; build() returns the Hanko line instead.
  static const bool _preHanko = false;

  @override
  Widget build(BuildContext context) {
    if (!_preHanko) return _buildHanko(context);
    final type = data['type'] as String? ?? '';
    final title = data['animeTitle'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final displayName = data['displayName'] as String? ?? 'Someone';
    final rating = (data['rating'] as num?)?.toDouble();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          // Anime poster
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 52,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholderPoster(),
                  )
                : _placeholderPoster(),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action line
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    children: [
                      if (showUser)
                        TextSpan(
                          text: '$displayName ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      TextSpan(
                        text: _getActionText(type),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      TextSpan(
                        text: ' $title',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Type badge + rating
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                _getTypeColor(type).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_getTypeEmoji(type),
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            _getTypeLabel(type),
                            style: TextStyle(
                              color: _getTypeColor(type),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 13),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                    const Spacer(),
                    if (createdAt != null)
                      Text(
                        _formatTime(createdAt),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The line in Hanko (question 73): no card, no badge, no emoji, on the
  /// page's column with space between lines. The sentence is a Text.rich
  /// in Jost, so it takes the app's font and the reader's text size; the old
  /// RichText had neither. The action reads in stone and the title in washi
  /// 500; on Friends the name leads in washi 600. Under it, when it happened,
  /// in stone at 6.9:1 (the old 40% white measured 3.75:1). The status words
  /// are in the sentence, so the badge that repeated them in colour goes. A
  /// rating, when an entry carries one, is a seal at the end: yours filled,
  /// a friend's in outline, as Hanko marks whose verdict it is.
  Widget _buildHanko(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final title = data['animeTitle'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final displayName = data['displayName'] as String? ?? 'Someone';
    final rating = (data['rating'] as num?)?.toDouble();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final line = Text.rich(
      TextSpan(
        style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.4),
        children: [
          if (showUser)
            TextSpan(
              text: '$displayName ',
              style: AppTheme.hankoSans(weight: FontWeight.w600, height: 1.4),
            ),
          TextSpan(text: _getActionText(type)),
          TextSpan(
            text: ' $title',
            style: AppTheme.hankoSans(weight: FontWeight.w500, height: 1.4),
          ),
        ],
      ),
    );

    return MergeSemantics(
      child: _hankoColumn(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.hankoGutter, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _hankoCover(imageUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line,
                    if (createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _formatTime(createdAt),
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          color: AppTheme.hankoStone,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (rating != null) ...[
                const SizedBox(width: 12),
                HankoSeal.score(
                  rating,
                  size: 28,
                  kind: showUser ? HankoSealKind.theirs : HankoSealKind.yours,
                  semanticLabel: showUser
                      ? '$displayName\'s rating, '
                          '${HankoSeal.formatScore(rating)}'
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The cover at 42 x 60 with Hanko's 2 px corners on a sumi 3 ground,
  /// which is also what shows while it loads, when it fails, or when the
  /// entry has none (Profile's covers, stage H5). Left out of the semantics
  /// tree: the sentence names the show, and the cover's image role made a
  /// screen reader announce each line as an image.
  Widget _hankoCover(String? url) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: SizedBox(
          width: 42,
          height: 60,
          child: ColoredBox(
            color: AppTheme.hankoSumi3,
            child: url == null || url.isEmpty
                ? const SizedBox.expand()
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.expand(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderPoster() => Container(
        width: 52,
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.movie_outlined,
            color: AppTheme.textMuted, size: 20),
      );

  String _getActionText(String type) {
    switch (type) {
      case 'WATCHING':
        return 'started watching';
      case 'COMPLETED':
        return 'completed';
      case 'PLAN_TO_WATCH':
        return 'added to watchlist:';
      case 'DROPPED':
        return 'dropped';
      case 'RATED':
        return 'rated';
      default:
        return 'added';
    }
  }

  String _getTypeEmoji(String type) {
    switch (type) {
      case 'WATCHING':      return '👀';
      case 'COMPLETED':     return '✅';
      case 'PLAN_TO_WATCH': return '📌';
      case 'DROPPED':       return '❌';
      case 'RATED':         return '⭐';
      default:              return '📋';
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'WATCHING':      return 'Watching';
      case 'COMPLETED':     return 'Completed';
      case 'PLAN_TO_WATCH': return 'Plan to Watch';
      case 'DROPPED':       return 'Dropped';
      case 'RATED':         return 'Rated';
      default:              return 'Added';
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'WATCHING':      return AppTheme.watching;
      case 'COMPLETED':     return AppTheme.success;
      case 'PLAN_TO_WATCH': return AppTheme.warning;
      case 'DROPPED':       return AppTheme.error;
      case 'RATED':         return Colors.amber;
      default:              return AppTheme.primary;
    }
  }

  /// When it happened, in the words the other screens use (question 134),
  /// by calendar day: "Today"; "Last night" (yesterday from 18:00) or
  /// "Yesterday", as Home's lede says them; the weekday within the week
  /// ("Saturday"); then the date as Profile's diary and Detail write it,
  /// "4 Oct", with the year when it isn't this one ("4 Oct 2025"). It used
  /// to write "1d ago" and "Oct 4", which no other screen does.
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(dt.year, dt.month, dt.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return dt.hour >= 18 ? 'Last night' : 'Yesterday';
    if (days < 7) return DateFormat('EEEE').format(dt);
    return DateFormat(dt.year == now.year ? 'd MMM' : 'd MMM y').format(dt);
  }
}

/// On a wide window (1024 px and up) the page keeps the phone's column,
/// Responsive.proseMaxWidth plus the gutters, hung on the left as Profile's
/// and Home's are. Below 1024 it does nothing (WEB.md §9.2).
Widget _hankoColumn(BuildContext context, Widget child) {
  if (!Responsive.isDesktop(context)) return child;
  return Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
          maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
      child: child,
    ),
  );
}

/// A Hanko secondary tile with a word on it, as Profile's and Home's: sumi 3
/// with a 1 px edge outline, Jost 600 15 washi, 48 dp tall, pressed with the
/// 8% wash. Its own semantics node (container), so a screen reader finds
/// one button named for its word; without it the button folded into the
/// note around it, which then read as one long button.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: AppTheme.hankoSans(
                      fontSize: 15, weight: FontWeight.w600, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
