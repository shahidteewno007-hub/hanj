// Tier lists: the start screen, at the '/tierlist' route (Profile's
// "Tier lists" row opens it).
//
// Your saved lists first, each with a strip of its top tiers, then the
// templates in four shelves: start here, power scaling, hot takes, and
// ranked like the show. Picking a template opens a new list straight into
// the character picker; nothing is saved until the list has something in it.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tier_list_editor_screen.dart';
import 'tier_list_model.dart';
import 'tier_list_store.dart';
import 'tier_list_templates.dart';
import 'tier_list_widgets.dart';

class TierListHomeScreen extends StatefulWidget {
  const TierListHomeScreen({super.key});

  @override
  State<TierListHomeScreen> createState() => _TierListHomeScreenState();
}

class _TierListHomeScreenState extends State<TierListHomeScreen> {
  List<TierList>? _lists;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await TierListStore.instance.idle;
    final lists = await TierListStore.instance.loadAll();
    if (mounted) setState(() => _lists = lists);
  }

  Future<void> _open(TierList list, {bool fresh = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TierListEditorScreen(list: list, openPickerFirst: fresh),
    ));
    if (mounted) await _load();
  }

  void _start(TierListTemplate t) {
    if ((_lists?.length ?? 0) >= TierListStore.maxLists) {
      tierToast(context,
          'This device keeps up to ${TierListStore.maxLists} tier lists. Delete one to start another.');
      return;
    }
    _open(t.create(id: TierListStore.freshId()), fresh: true);
  }

  Future<void> _listMenu(TierList list, String action) async {
    switch (action) {
      case 'duplicate':
        if ((_lists?.length ?? 0) >= TierListStore.maxLists) {
          tierToast(context, 'This device keeps up to ${TierListStore.maxLists} tier lists.');
          return;
        }
        final copy = TierList.fromJson(jsonDecode(jsonEncode(list.toJson())));
        if (copy == null) return;
        final now = DateTime.now();
        final dup = TierList(
          id: TierListStore.freshId(),
          title: '${list.title} (copy)'.length > TierList.maxTitleLength
              ? list.title
              : '${list.title} (copy)',
          prompt: copy.prompt,
          templateId: copy.templateId,
          tiers: copy.tiers,
          unranked: copy.unranked,
          characters: copy.characters,
          createdAt: now,
          updatedAt: now,
        );
        final ok = await TierListStore.instance.save(dup);
        if (!mounted) return;
        if (!ok) tierToast(context, 'Couldn’t copy it. Try again.');
        await _load();
      case 'delete':
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.hankoSumi2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoSheetRadius)),
            title: Text('Delete this tier list?', style: AppTheme.hankoSerif(fontSize: 20)),
            content: Text(
              '“${list.title}” will be gone from this device. This can’t be undone.',
              style: AppTheme.hankoSans(color: AppTheme.hankoStone),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Keep it', style: AppTheme.hankoSans(weight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Delete', style: AppTheme.hankoSans(weight: FontWeight.w600)),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) return;
        final ok = await TierListStore.instance.delete(list.id);
        if (!mounted) return;
        if (!ok) tierToast(context, 'Couldn’t delete it. Try again.');
        await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _hero()),
                if (lists != null && lists.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _sectionHead('Your tier lists', '${lists.length}')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppTheme.hankoGutter, 0, AppTheme.hankoGutter, 8),
                    sliver: SliverList.separated(
                      itemCount: lists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _SavedListCard(
                        list: lists[i],
                        onOpen: () => _open(lists[i]),
                        onMenu: (a) => _listMenu(lists[i], a),
                      ),
                    ),
                  ),
                ],
                for (final kind in TierTemplateKind.values) ...[
                  SliverToBoxAdapter(
                    child: _sectionHead(
                      kind.heading,
                      null,
                      lead: kind == TierTemplateKind.starter && (lists?.isNotEmpty ?? false)
                          ? 'Start another'
                          : null,
                    ),
                  ),
                  SliverToBoxAdapter(child: _shelf(kind)),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    // A small tier list as the masthead: the palette, in a real scheme.
    const sample = [
      ('Universe level', 0),
      ('Planet level', 1),
      ('City level', 2),
      ('Street level', 3),
    ];
    return Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: TierDotGrid(step: 16, alpha: 0.05))),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, AppTheme.hankoGutter, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.hankoWashi),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              else
                const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.hankoGutter - 4, 4, 0, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const TierEyebrow('Tier lists'),
                          const SizedBox(height: 8),
                          Semantics(
                            header: true,
                            child: Text('Rank anyone.\nPost the proof.',
                                style: AppTheme.hankoSerif(fontSize: 26, height: 1.2)),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Pick a template, search any anime, drop its characters into tiers, and save the picture.',
                            style: AppTheme.hankoSans(fontSize: 14, color: AppTheme.hankoStone, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    ExcludeSemantics(
                      child: MediaQuery.withNoTextScaling(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            children: [
                              for (final (label, p) in sample)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    children: [
                                      TierPlate(
                                        label: label.split(' ').first,
                                        pigment: TierPigment.at(p),
                                        width: 58,
                                        minHeight: 24,
                                        fontSize: 9,
                                      ),
                                      Container(
                                        width: 34 - p * 7.0,
                                        height: 24,
                                        color: AppTheme.hankoSumi3,
                                      ),
                                    ],
                                  ),
                                ),
                            ],
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
      ],
    );
  }

  Widget _sectionHead(String title, String? count, {String? lead}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.hankoGutter, 22, AppTheme.hankoGutter, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(lead ?? title, style: AppTheme.hankoSerif(fontSize: AppTheme.hankoSectionSize + 2)),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: TierEyebrow(count),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shelf(TierTemplateKind kind) {
    final templates = [for (final t in kTierTemplates) if (t.kind == kind) t];
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter - 4),
      // One height for the whole shelf, the tallest card's.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in templates)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _TemplateCard(template: t, width: narrow ? 212 : 236, onTap: () => _start(t)),
              ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.width, required this.onTap});
  final TierListTemplate template;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = template;
    final p = t.pigmentsOrRamp;
    final shown = t.tiers.length > 5 ? 4 : t.tiers.length;
    final more = t.tiers.length - shown;
    final named = [for (final l in t.tiers) if (l.isNotEmpty) l];
    return TierPressable(
      label: '${t.name}. ${t.prompt}'
          '${named.isEmpty ? ' ${t.tiers.length} unnamed tiers.' : ' Tiers: ${named.join(', ')}.'}',
      hint: 'Starts a new list',
      onTap: onTap,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppTheme.hankoSumi2,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          border: Border.all(color: AppTheme.hankoHairline),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(t.icon, size: 18, color: TierPigment.at(p.first).color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.hankoSerif(fontSize: 17, height: 1.2)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              t.prompt,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.3),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < shown; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 22),
                  color: TierPigment.at(p[i]).color,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    t.tiers[i].isEmpty ? ' ' : t.tiers[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.hankoSans(
                      fontSize: 11.5,
                      weight: FontWeight.w600,
                      color: TierPigment.at(p[i]).ink,
                    ),
                  ),
                ),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+ $more more', style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoAsh)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SavedListCard extends StatelessWidget {
  const _SavedListCard({required this.list, required this.onOpen, required this.onMenu});
  final TierList list;
  final VoidCallback onOpen;
  final ValueChanged<String> onMenu;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final d = list.updatedAt;
    final template = tierTemplateById(list.templateId);
    final facts = [
      list.rankedCount == 1 ? '1 ranked' : '${list.rankedCount} ranked',
      if (list.unranked.isNotEmpty) '${list.unranked.length} waiting',
      'edited ${d.day} ${_months[d.month - 1]}',
    ].join('  ·  ');
    // The first rows that have anyone in them, up to three.
    final rows = [for (final t in list.tiers) if (t.characterIds.isNotEmpty) t].take(3).toList();
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi2,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        border: Border.all(color: AppTheme.hankoHairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TierPressable(
              label: '${list.title}. $facts',
              hint: 'Opens the list',
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.hankoSerif(fontSize: 17, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(
                      template == null ? facts : '${template.name}  ·  $facts',
                      style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoStone),
                    ),
                    if (rows.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final t in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              MediaQuery.withNoTextScaling(
                                child: TierPlate(
                                  label: t.label,
                                  pigment: TierPigment.at(t.pigment),
                                  width: 52,
                                  minHeight: 36,
                                  fontSize: 9.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: ClipRect(
                                    child: Row(
                                      children: [
                                        for (final id in t.characterIds.take(8))
                                          if (list.characters[id] case final TierCharacter c)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 3),
                                              child: CharacterPortrait(character: c, width: 24, showName: false),
                                            ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options for ${list.title}',
            icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.hankoStone),
            color: AppTheme.hankoSumi3,
            onSelected: onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'duplicate',
                child: Text('Make a copy', style: AppTheme.hankoSans()),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: AppTheme.hankoSans()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
