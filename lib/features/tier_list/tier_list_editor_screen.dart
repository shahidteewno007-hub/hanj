// Tier lists: the board where a list is made.
//
// Tiers run down the screen, each a coloured name plate and a row of
// portraits; the unranked tray sits at the bottom. Three ways to place a
// character, so nobody has to drag:
//  - drag a portrait (press and hold on a phone) onto a tier, or onto
//    another portrait to drop it before or after them;
//  - tap a portrait for its sheet: move to any tier, step left or right,
//    back to the tray, or off the list;
//  - with a keyboard, focus a portrait and use the arrow keys (up and down
//    change tier, left and right reorder; Delete sends it to the tray).
//    Screen readers get the same moves as custom actions.
// Every change saves itself on the device half a second later.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'tier_list_anilist.dart';
import 'tier_list_export_screen.dart';
import 'tier_list_model.dart';
import 'tier_list_picker_screen.dart';
import 'tier_list_store.dart';
import 'tier_list_templates.dart';
import 'tier_list_widgets.dart';

class TierListEditorScreen extends StatefulWidget {
  const TierListEditorScreen({super.key, required this.list, this.openPickerFirst = false});

  final TierList list;

  /// Opens the character picker as soon as the board appears (a new list).
  final bool openPickerFirst;

  @override
  State<TierListEditorScreen> createState() => _TierListEditorScreenState();
}

class _TierListEditorScreenState extends State<TierListEditorScreen> {
  static const _moveUp = CustomSemanticsAction(label: 'Move up a tier');
  static const _moveDown = CustomSemanticsAction(label: 'Move down a tier');
  static const _moveLeft = CustomSemanticsAction(label: 'Move left');
  static const _moveRight = CustomSemanticsAction(label: 'Move right');
  static const _toTray = CustomSemanticsAction(label: 'Send back to unranked');
  static const _editTierAction = CustomSemanticsAction(label: 'Edit tier');

  TierList get _list => widget.list;

  final _scroll = ScrollController();
  final _boardKey = GlobalKey();
  final Map<int, FocusNode> _focus = {};
  final Map<int, GlobalKey> _tokenKeys = {};

  Timer? _saveTimer;
  bool _dirty = false;
  bool _saveFailed = false;

  int? _dragging;
  String? _hoverTier; // a tier id, or _trayId, while something is dragged over it
  int? _insertAt; // the portrait a drop would land beside
  bool _insertAfter = false;
  Timer? _autoScroll;
  double _autoSpeed = 0;

  /// Round nine: Edit tiers, where the board becomes a list of its tiers.
  bool _editing = false;

  static const _trayId = '\u0000tray';

  bool get _touchFirst =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (widget.openPickerFirst) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addCharacters();
      });
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(TierListStore.instance.save(_list));
    _autoScroll?.cancel();
    _scroll.dispose();
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(int id) => _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'tier-token-$id'));

  /// One key per character for as long as the board is open, so moving them
  /// to another row moves the same widget there and keyboard focus goes
  /// with it.
  GlobalKey _keyFor(int id) => _tokenKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tier-token-$id'));

  // ── saving ─────────────────────────────────────────────────
  void _changed() {
    setState(() {});
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    _dirty = false;
    final ok = await TierListStore.instance.save(_list);
    if (!ok) _dirty = true;
    if (mounted && ok == _saveFailed) setState(() => _saveFailed = !ok);
  }

  void _announce(String message) {
    unawaited(SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr)
        .catchError((Object _) {}));
  }

  String _slotName(String? tierId) {
    if (tierId == null || tierId == _trayId) return 'Unranked';
    final t = _list.tierById(tierId);
    if (t == null) return 'Unranked';
    if (t.label.trim().isNotEmpty) return '${t.label} tier';
    // Round nine: an unnamed tier is "Tier 3" everywhere.
    return TierListSwitches.editTiers ? _list.displayName(t) : 'tier ${_list.indexOfTier(t.id) + 1}';
  }

  /// Runs a move, then keeps keyboard focus on the character who moved and
  /// says where they went.
  void _moved(int id, bool Function() move) {
    final hadFocus = _focus[id]?.hasFocus ?? false;
    if (!move()) return;
    _changed();
    final name = _list.characters[id]?.name ?? 'Character';
    _announce('$name: ${_slotName(_list.tierOf(id)?.id)}');
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus[id]?.requestFocus();
      });
    }
  }

  // ── adding ─────────────────────────────────────────────────
  /// The anime already on this list, most-used first, for the picker's
  /// quick picks: their casts are kept, so opening one again is free.
  List<TierAnime> _listAnime() => [
        for (final m in _list.mediaByUse())
          if (_list.sampleOf(m.key) case final TierCharacter c when c.mediaTitle != null)
            TierAnime(id: m.key, title: c.mediaTitle!, cover: c.mediaCover, color: c.mediaColor),
      ].take(4).toList();

  Future<void> _addCharacters() async {
    final template = tierTemplateById(_list.templateId);
    final elsewhere = TierListSwitches.tapToFill
        ? await TierListStore.instance.charactersElsewhere(_list.id, skip: _list.characters.keys.toSet())
        : const <TierCharacter>[];
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<TierCharacter>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TierCharacterPickerScreen(
          alreadyOnList: _list.characters.keys.toSet(),
          room: TierList.maxCharacters - _list.count,
          ideas: TierSearchIdeas(
            characters: template?.characters ?? const [],
            anime: template?.anime ?? const [],
          ),
          listAnime: TierListSwitches.tapToFill ? _listAnime() : const [],
          fromOtherLists: elsewhere,
        ),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    final added = _list.addCharacters(picked);
    if (added > 0) {
      _changed();
      tierToast(context, added == 1 ? 'Added to unranked. Drag or tap to place.' : '$added added to unranked. Drag or tap to place them.');
    }
  }

  /// Round nine: the tier [t] was tapped, so pick who goes in it. Picks
  /// land at its end, characters waiting in the tray included.
  Future<void> _fillTier(Tier t) async {
    final template = tierTemplateById(_list.templateId);
    final placed = {for (final x in _list.tiers) ...x.characterIds};
    final waiting = [
      for (final id in _list.unranked)
        if (_list.characters[id] case final TierCharacter c) c,
    ];
    final elsewhere =
        await TierListStore.instance.charactersElsewhere(_list.id, skip: _list.characters.keys.toSet());
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<TierCharacter>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TierCharacterPickerScreen(
          alreadyOnList: placed,
          room: TierList.maxCharacters - _list.count + waiting.length,
          ideas: TierSearchIdeas(
            characters: template?.characters ?? const [],
            anime: template?.anime ?? const [],
          ),
          target: TierPickTarget(label: _list.displayName(t), pigment: TierPigment.at(t.pigment)),
          waiting: waiting,
          listAnime: _listAnime(),
          fromOtherLists: elsewhere,
        ),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty || _list.tierById(t.id) == null) return;
    final landed = _list.addTo(t.id, picked);
    if (landed > 0) {
      _changed();
      final name = _list.displayName(t);
      tierToast(context, landed == 1 ? 'Added to $name.' : '$landed added to $name.');
    }
  }

  // ── dragging ───────────────────────────────────────────────
  void _setHover(String? tier, {int? at, bool after = false}) {
    if (tier == _hoverTier && at == _insertAt && after == _insertAfter) return;
    setState(() {
      _hoverTier = tier;
      _insertAt = at;
      _insertAfter = after;
    });
  }

  void _dragStarted(int id) => setState(() => _dragging = id);

  void _dragEnded() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _autoSpeed = 0;
    setState(() {
      _dragging = null;
      _hoverTier = null;
      _insertAt = null;
    });
  }

  /// Scrolls the board while a drag sits near its top or bottom edge.
  void _dragUpdate(DragUpdateDetails d) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(d.globalPosition);
    const edge = 72.0;
    var v = 0.0;
    if (local.dy >= 0 && local.dy < edge) {
      v = -(edge - local.dy) / edge;
    } else if (local.dy <= box.size.height && local.dy > box.size.height - edge) {
      v = (local.dy - (box.size.height - edge)) / edge;
    }
    _autoSpeed = v * 16;
    if (_autoSpeed == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients || _autoSpeed == 0) return;
      final p = _scroll.position;
      final to = (p.pixels + _autoSpeed).clamp(p.minScrollExtent, p.maxScrollExtent);
      if (to != p.pixels) _scroll.jumpTo(to);
    });
  }

  /// A drop onto [tierId] (or the tray), beside the portrait [beside] when
  /// given.
  void _drop(int id, String tierId, {int? beside, bool after = false}) {
    final toTier = tierId == _trayId ? null : tierId;
    final dest = toTier == null ? _list.unranked : _list.tierById(toTier)?.characterIds;
    if (dest == null) return;
    int? index;
    if (beside != null && beside != id) {
      index = dest.indexOf(beside);
      if (index < 0) {
        index = null;
      } else {
        final from = dest.indexOf(id);
        if (from >= 0 && from < index) index -= 1;
        if (after) index += 1;
      }
    }
    HapticFeedback.lightImpact();
    _moved(id, () => _list.move(id, toTierId: toTier, index: index));
  }

  // ── sheets ─────────────────────────────────────────────────
  Future<void> _openCharacter(int id) async {
    final c = _list.characters[id];
    if (c == null) return;
    final action = await showTierSheet<_CharacterAction>(
      context,
      (_) => _CharacterSheet(list: _list, character: c),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MoveTo(:final tierId):
        _moved(id, () => _list.move(id, toTierId: tierId));
      case _Nudge(:final step):
        _moved(id, () => _list.nudge(id, step));
      case _Remove():
        if (_list.remove(id)) {
          _tokenKeys.remove(id);
          final node = _focus.remove(id);
          // Disposed after the frame that drops their portrait.
          WidgetsBinding.instance.addPostFrameCallback((_) => node?.dispose());
          _changed();
          _announce('${c.name} removed from the list');
        }
    }
  }

  Future<void> _editTier(Tier tier) async {
    final result = await showTierSheet<_TierEdit>(
      context,
      (_) => _TierSheet(list: _list, tier: tier, onLive: _changed),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case _TierSaved(:final label, :final pigment):
        _list.renameTier(tier.id, label);
        _list.setPigment(tier.id, pigment);
        _changed();
      case _TierMoved(:final step):
        if (_list.moveTier(tier.id, step)) _changed();
      case _TierAddBelow():
        final added = _list.addTier(
          afterTierId: tier.id,
          label: '',
          pigment: TierPigment.indexOf(TierPigment.ash),
        );
        if (added != null) {
          _changed();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _editTier(added);
          });
        }
      case _TierDeleted():
        if (TierListSwitches.editTiers) {
          _removeTier(tier);
          return;
        }
        final had = tier.characterIds.length;
        if (_list.removeTier(tier.id)) {
          _changed();
          if (had > 0 && mounted) {
            tierToast(context, had == 1 ? '1 character went back to unranked.' : '$had characters went back to unranked.');
          }
        }
    }
  }

  /// Round nine: removes a tier, its characters going back to unranked as
  /// Delete tier did, with Undo, which puts back the tiers and every place
  /// exactly as they were.
  void _removeTier(Tier t) {
    final name = _list.displayName(t);
    final had = t.characterIds.length;
    final snapshot = TierList.fromJson(jsonDecode(jsonEncode(_list.toJson())));
    if (!_list.removeTier(t.id)) return;
    _changed();
    tierToast(
      context,
      switch (had) {
        0 => 'Removed $name.',
        1 => 'Removed $name. 1 character went back to unranked.',
        _ => 'Removed $name. $had characters went back to unranked.',
      },
      actionLabel: 'Undo',
      onAction: snapshot == null
          ? null
          : () {
              if (!mounted) return;
              _list.restoreFrom(snapshot);
              _changed();
              _announce('$name is back');
            },
    );
  }

  void _stepTier(Tier t, int step) {
    if (!_list.moveTier(t.id, step)) return;
    _changed();
    _announce('${_list.displayName(t)}: ${_list.indexOfTier(t.id) + 1} of ${_list.tiers.length}');
  }

  void _setEditing(bool on) {
    if (_editing == on) return;
    setState(() => _editing = on);
    _announce(on ? 'Editing tiers' : 'Done editing tiers');
  }

  Future<void> _renameList() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => TierTextSelection(child: _RenameListDialog(title: _list.title, prompt: _list.prompt)),
    );
    if (!mounted || result == null) return;
    final (title, prompt) = result;
    _list.title = title.trim().isEmpty ? _list.title : title.trim();
    _list.prompt = prompt.trim();
    _changed();
  }

  Future<void> _menu(String value) async {
    switch (value) {
      case 'edit-tiers':
        _setEditing(true);
      case 'rename':
        await _renameList();
      case 'add-tier':
        final added = _list.addTier(label: '', pigment: TierPigment.indexOf(TierPigment.ash));
        if (added != null) {
          _changed();
          await _editTier(added);
        } else {
          tierToast(context, 'A list holds up to ${TierList.maxTiers} tiers.');
        }
      case 'unrank':
        if (_list.rankedCount == 0) return;
        _list.unrankAll();
        _changed();
        tierToast(context, 'Everyone is back in unranked.');
      case 'delete':
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.hankoSumi2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoSheetRadius)),
            title: Text('Delete this tier list?', style: AppTheme.hankoSerif(fontSize: 20)),
            content: Text(
              '“${_list.title}” will be gone from this device. This can’t be undone.',
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
        _saveTimer?.cancel();
        _dirty = false;
        final ok = await TierListStore.instance.delete(_list.id);
        if (!mounted) return;
        if (ok) {
          Navigator.of(context).pop();
        } else {
          tierToast(context, 'Couldn’t delete it. Try again.');
        }
    }
  }

  void _export() {
    if (_list.rankedCount == 0) {
      tierToast(context, 'Place someone in a tier first.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TierListExportScreen(list: _list),
    ));
  }

  // ── build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 600;
    final tokenW = wide ? 64.0 : 52.0;
    final plateW = tierPlateWidth(
      context,
      [for (final t in _list.tiers) t.label.trim().isEmpty ? 'Name' : t.label],
      max: wide ? 150 : 120,
    );
    final tint = _coverTint();

    final page = Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: SafeArea(
        child: Column(
          children: [
            // As wide as the board, so on a desktop the title and Share sit
            // over the tiers rather than at the window's far edges.
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: _editing ? _editTopBar() : _topBar(),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (tint != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 220,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [tint, tint.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: ListView(
                        key: _boardKey,
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          _header(),
                          const SizedBox(height: 14),
                          for (final t in _list.tiers) ...[
                            KeyedSubtree(
                              key: ValueKey('tier-${t.id}'),
                              child: _editing ? _editRow(t, plateW) : _tierRow(t, plateW, tokenW),
                            ),
                            const SizedBox(height: 2),
                          ],
                          const SizedBox(height: 10),
                          if (TierListSwitches.editTiers)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_list.tiers.length < TierList.maxTiers)
                                  TierGhostButton(
                                    label: 'Add a tier',
                                    icon: Icons.add_rounded,
                                    dense: true,
                                    onTap: () => _menu('add-tier'),
                                  ),
                                if (!_editing)
                                  TierGhostButton(
                                    label: 'Edit tiers',
                                    icon: Icons.tune_rounded,
                                    dense: true,
                                    onTap: () => _setEditing(true),
                                  ),
                              ],
                            )
                          else if (_list.tiers.length < TierList.maxTiers)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TierGhostButton(
                                label: 'Add a tier',
                                icon: Icons.add_rounded,
                                dense: true,
                                onTap: () => _menu('add-tier'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_editing) _tray(tokenW),
          ],
        ),
      ),
    );
    if (!TierListSwitches.editTiers) return page;
    // Round nine: Back leaves Edit tiers before it leaves the list.
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _editing) _setEditing(false);
      },
      child: page,
    );
  }

  /// Round nine: Edit tiers' top bar. Back and Done both leave the mode.
  Widget _editTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.hankoWashi),
            onPressed: () => _setEditing(false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Semantics(
                header: true,
                child: Text('Edit tiers', style: AppTheme.hankoSerif(fontSize: 20)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TierMainButton(label: 'Done', icon: Icons.check_rounded, onTap: () => _setEditing(false)),
        ],
      ),
    );
  }

  /// Round nine: a tier in Edit tiers, as a short strip: its plate (tap to
  /// rename or recolour it), how many it holds, then up, down and remove.
  Widget _editRow(Tier t, double plateW) {
    final i = _list.indexOfTier(t.id);
    final n = t.characterIds.length;
    final name = _list.displayName(t);
    final canRemove = _list.tiers.length > TierList.minTiers;
    Widget action(IconData icon, String label, VoidCallback? onTap) => IconButton(
          tooltip: label,
          icon: Icon(icon, color: onTap == null ? AppTheme.hankoEdge : AppTheme.hankoWashi),
          onPressed: onTap,
        );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TierPressable(
            label: '$name. ${n == 1 ? '1 character' : '$n characters'}',
            hint: 'Rename or recolour this tier',
            onTap: () => _editTier(t),
            ringInset: 2,
            child: TierPlate(
              label: t.label,
              pigment: TierPigment.at(t.pigment),
              width: plateW,
              minHeight: 56,
              placeholder: 'Name',
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: _rowGround(t, false),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  // The count, as a figure: the plate's spoken label says it
                  // in words.
                  const ExcludeSemantics(child: Icon(Icons.person_rounded, size: 16, color: AppTheme.hankoAsh)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        '$n',
                        maxLines: 1,
                        style: AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w500, color: AppTheme.hankoStone, tabular: true),
                      ),
                    ),
                  ),
                  action(Icons.arrow_upward_rounded, 'Move $name up', i > 0 ? () => _stepTier(t, -1) : null),
                  action(Icons.arrow_downward_rounded, 'Move $name down',
                      i < _list.tiers.length - 1 ? () => _stepTier(t, 1) : null),
                  action(Icons.delete_outline_rounded, 'Remove $name', canRemove ? () => _removeTier(t) : null),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The most-used anime's cover colour, as a faint wash behind the header,
  /// held back when it's close to the seal's coral (Hanko's tint rule).
  Color? _coverTint() {
    final top = _list.mediaByUse();
    if (top.isEmpty) return null;
    final c = _list.sampleOf(top.first.key)?.mediaColor;
    if (c == null) return null;
    final t = AppTheme.hankoCoverTint(Color(c));
    return t?.withValues(alpha: 0.16);
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.hankoWashi),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: TierPressable(
              label: '${_list.title}. Rename list',
              onTap: _renameList,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Text(
                  _list.title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: AppTheme.hankoSerif(fontSize: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Past 1.4x text the labelled button would leave the title a few
          // letters, so it becomes an icon with the same name.
          if (MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4)
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.ios_share_rounded, color: AppTheme.hankoWashi),
              onPressed: _export,
            )
          else
            TierGhostButton(label: 'Share', icon: Icons.ios_share_rounded, dense: true, onTap: _export),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.hankoWashi),
            color: AppTheme.hankoSumi3,
            onSelected: _menu,
            itemBuilder: (_) => [
              _menuItem('rename', Icons.edit_rounded, 'Rename list'),
              _menuItem('add-tier', Icons.playlist_add_rounded, 'Add a tier'),
              if (TierListSwitches.editTiers) _menuItem('edit-tiers', Icons.tune_rounded, 'Edit tiers'),
              _menuItem('unrank', Icons.move_down_rounded, 'Send everyone to unranked'),
              _menuItem('delete', Icons.delete_outline_rounded, 'Delete list'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) => PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppTheme.hankoStone),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: AppTheme.hankoSans())),
          ],
        ),
      );

  Widget _header() {
    final anime = _list.mediaByUse().length;
    final bits = <String>[
      _list.count == 1 ? '1 character' : '${_list.count} characters',
      if (anime > 0) anime == 1 ? '1 anime' : '$anime anime',
      if (_saveFailed) 'not saved',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_list.prompt.isNotEmpty)
            Text(
              _list.prompt,
              style: AppTheme.hankoSans(fontSize: 15, color: AppTheme.hankoStoneHi, height: 1.35),
            ),
          const SizedBox(height: 6),
          TierEyebrow(bits.join('  ·  '),
              color: _saveFailed ? AppTheme.hankoWashi : AppTheme.hankoStone),
        ],
      ),
    );
  }

  Widget _tierRow(Tier t, double plateW, double tokenW) {
    final index = _list.indexOfTier(t.id);
    final n = t.characterIds.length;
    final name = t.label.trim().isEmpty ? 'Tier ${index + 1}, unnamed' : t.label;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) {
        _setHover(t.id);
        return true;
      },
      onLeave: (_) {
        if (_hoverTier == t.id && _insertAt == null) _setHover(null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, t.id),
      builder: (context, candidates, _) {
        final hot = _hoverTier == t.id;
        // Round nine: the plate fills its tier (an unnamed one is named
        // first: its plate says "Name"); long-press, or the screen reader's
        // "Edit tier", opens the tier's sheet.
        const fill = TierListSwitches.tapToFill;
        final named = t.label.trim().isNotEmpty;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TierPressable(
                label: '$name. ${n == 1 ? '1 character' : '$n characters'}',
                hint: !fill
                    ? 'Rename, recolour or move this tier'
                    : (named ? 'Adds characters to this tier' : 'Names this tier'),
                onTap: fill && named ? () => _fillTier(t) : () => _editTier(t),
                onLongPress: fill ? () => _editTier(t) : null,
                customActions: fill ? {_editTierAction: () => _editTier(t)} : null,
                ringInset: 2,
                child: TierPlate(
                  label: t.label,
                  pigment: TierPigment.at(t.pigment),
                  width: plateW,
                  // An empty row is a short strip until someone lands in it.
                  minHeight: fill && n == 0 ? 64 : tokenW * 1.5 + (TierListSwitches.boardLook ? 42 : 30),
                  placeholder: 'Name',
                ),
              ),
              Expanded(
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 120),
                  color: _rowGround(t, hot),
                  padding: const EdgeInsets.all(6),
                  child: n == 0
                      ? (fill ? _addSlot(t, tokenW, wide: true, hot: hot) : _emptyRowHint(hot))
                      : Wrap(
                          spacing: 6,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < n; i++)
                              _token(t.characterIds[i], t.id, i, n, tokenW),
                            if (fill) _addSlot(t, tokenW, wide: false, hot: hot),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A row's ground. Round nine: its tier's pigment at 7% (14% while a
  /// drag is over it), so each tier reads as one band of its colour, as the
  /// picture's plates do.
  Color _rowGround(Tier t, bool hot) {
    final base = hot ? AppTheme.hankoSumi3 : AppTheme.hankoSumi2;
    if (!TierListSwitches.boardLook) return base;
    return Color.alphaBlend(TierPigment.at(t.pigment).color.withValues(alpha: hot ? 0.14 : 0.07), base);
  }

  /// Round nine: the dashed slot that ends a row; tap it to pick for this
  /// tier. An empty row's slot is wide and says so ("Add to S"). The
  /// plate is the screen reader's and the keyboard's way in, so the slot
  /// is left out of both.
  Widget _addSlot(Tier t, double tokenW, {required bool wide, required bool hot}) {
    final Widget inside;
    if (wide) {
      inside = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 18, color: hot ? AppTheme.hankoWashi : AppTheme.hankoStone),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                hot ? 'Drop here' : 'Add to ${_list.displayName(t)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.hankoSans(
                  fontSize: 13,
                  weight: FontWeight.w500,
                  color: hot ? AppTheme.hankoWashi : AppTheme.hankoStone,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      inside = SizedBox(
        width: tokenW,
        height: tokenW * 1.5,
        child: Icon(Icons.add_rounded, size: 20, color: hot ? AppTheme.hankoWashi : AppTheme.hankoStone),
      );
    }
    return ExcludeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          canRequestFocus: false,
          onTap: () => _fillTier(t),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          // Washi while a drag is over the row: the slot is where it lands
          // (and edge on the drag's brighter ground would be 2.6:1).
          child: CustomPaint(
            painter: _DashedBox(color: hot ? AppTheme.hankoWashi : AppTheme.hankoEdge),
            child: wide ? Align(alignment: Alignment.centerLeft, child: inside) : inside,
          ),
        ),
      ),
    );
  }

  Widget _emptyRowHint(bool hot) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          hot ? 'Drop here' : (_list.isEmpty ? '' : 'Empty'),
          // Stone on a tinted row (round nine): ash would be 4.4:1 on gold.
          style: AppTheme.hankoSans(
            fontSize: 13,
            color: hot
                ? AppTheme.hankoWashi
                : (TierListSwitches.boardLook ? AppTheme.hankoStone : AppTheme.hankoAsh),
          ),
        ),
      ),
    );
  }

  Widget _token(int id, String slotId, int i, int n, double width) {
    final c = _list.characters[id];
    if (c == null) return const SizedBox.shrink();
    final inTray = slotId == _trayId;
    final where = _slotName(inTray ? null : slotId);
    // Round nine: two lines of name, as the picture prints them ("Satoru
    // Gojou", not "Satoru G…").
    final portrait = CharacterPortrait(
      character: c,
      width: width,
      nameSize: 10.5,
      nameLines: TierListSwitches.boardLook ? 2 : 1,
    );
    final ghost = Opacity(opacity: 0.25, child: portrait);
    final feedback = Material(
      color: Colors.transparent,
      child: Transform.translate(
        offset: Offset(-width / 2, -width * 0.75),
        child: Transform.scale(
          scale: 1.08,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 14, offset: Offset(0, 6))],
            ),
            child: MediaQuery.withNoTextScaling(child: CharacterPortrait(character: c, width: width, showName: false)),
          ),
        ),
      ),
    );

    final tierIndex = inTray ? _list.tiers.length : _list.indexOfTier(slotId);
    final bottom = tierIndex == _list.tiers.length - 1;
    final actions = <CustomSemanticsAction, VoidCallback>{
      if (tierIndex > 0) _moveUp: () => _moved(id, () => _list.shift(id, -1)),
      if (!inTray && !bottom) _moveDown: () => _moved(id, () => _list.shift(id, 1)),
      if (i > 0) _moveLeft: () => _moved(id, () => _list.nudge(id, -1)),
      if (i < n - 1) _moveRight: () => _moved(id, () => _list.nudge(id, 1)),
      if (!inTray) _toTray: () => _moved(id, () => _list.move(id)),
    };

    final target = DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != id,
      onMove: (d) {
        final box = _tokenKeys[id]?.currentContext?.findRenderObject();
        var after = false;
        if (box is RenderBox && box.hasSize) {
          after = box.globalToLocal(d.offset).dx > box.size.width / 2;
        }
        _setHover(slotId, at: id, after: after);
      },
      // Cleared entirely: if the pointer is still over this row, the row
      // takes the drag in the same update and marks itself again.
      onLeave: (_) {
        if (_insertAt == id) _setHover(null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, slotId, beside: id, after: _insertAt == id && _insertAfter),
      builder: (context, candidates, _) {
        final marked = candidates.isNotEmpty && _insertAt == id;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moved(id, () => _list.shift(id, -1)),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moved(id, () => _list.shift(id, 1)),
                const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _moved(id, () => _list.nudge(id, -1)),
                const SingleActivator(LogicalKeyboardKey.arrowRight): () => _moved(id, () => _list.nudge(id, 1)),
                const SingleActivator(LogicalKeyboardKey.delete): () => _moved(id, () => _list.move(id)),
                const SingleActivator(LogicalKeyboardKey.backspace): () => _moved(id, () => _list.move(id)),
              },
              child: TierPressable(
                focusNode: _nodeFor(id),
                label: '${c.name}${c.mediaTitle == null ? '' : ', ${c.mediaTitle}'}. '
                    '$where, ${i + 1} of $n.',
                hint: 'Opens moves. Arrow keys move it.',
                customActions: actions,
                onTap: () => _openCharacter(id),
                child: _dragging == id ? ghost : portrait,
              ),
            ),
            if (marked)
              Positioned(
                top: 0,
                bottom: 0,
                left: _insertAfter ? null : -4.5,
                right: _insertAfter ? -4.5 : null,
                width: 3,
                child: const ColoredBox(color: AppTheme.hankoWashi),
              ),
          ],
        );
      },
    );

    final drag = _touchFirst
        ? LongPressDraggable<int>(
            data: id,
            delay: const Duration(milliseconds: 280),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            onDragStarted: () => _dragStarted(id),
            onDragUpdate: _dragUpdate,
            onDragEnd: (_) => _dragEnded(),
            onDraggableCanceled: (_, _) => _dragEnded(),
            child: target,
          )
        : Draggable<int>(
            data: id,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: feedback,
            onDragStarted: () => _dragStarted(id),
            onDragUpdate: _dragUpdate,
            onDragEnd: (_) => _dragEnded(),
            onDraggableCanceled: (_, _) => _dragEnded(),
            child: target,
          );
    return KeyedSubtree(key: _keyFor(id), child: drag);
  }

  Widget _tray(double tokenW) {
    final n = _list.unranked.length;
    final showBody = n > 0 || _dragging != null || _list.isEmpty;
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) {
        _setHover(_trayId);
        return true;
      },
      onLeave: (_) {
        if (_hoverTier == _trayId && _insertAt == null) _setHover(null);
      },
      onAcceptWithDetails: (d) => _drop(d.data, _trayId),
      builder: (context, candidates, _) {
        final hot = _hoverTier == _trayId;
        return Container(
          decoration: BoxDecoration(
            color: hot ? AppTheme.hankoSumi3 : AppTheme.hankoSumi2,
            border: const Border(top: BorderSide(color: AppTheme.hankoHairline)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A wrap, not a row: at large text sizes the button moves
                    // under the label rather than squeezing it into a column
                    // of single letters (which made the tray half the screen).
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Semantics(
                            header: true,
                            child: TierEyebrow(n == 0 ? 'Unranked' : 'Unranked  ·  $n',
                                color: AppTheme.hankoStoneHi),
                          ),
                          // Round nine: the main way in is the tier you tap,
                          // so adding to the tray is the second way.
                          if (TierListSwitches.tapToFill)
                            TierGhostButton(
                              label: _list.isEmpty ? 'Add characters' : 'Add more',
                              icon: Icons.person_add_alt_1_rounded,
                              onTap: _list.isFull ? null : _addCharacters,
                            )
                          else
                            TierMainButton(
                              label: _list.isEmpty ? 'Add characters' : 'Add more',
                              icon: Icons.person_add_alt_1_rounded,
                              onTap: _list.isFull ? null : _addCharacters,
                            ),
                        ],
                      ),
                    ),
                    if (showBody) ...[
                      const SizedBox(height: 8),
                      if (n == 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, right: 8),
                          child: Text(
                            _dragging != null
                                ? 'Drop here to take them out of their tier.'
                                : TierListSwitches.tapToFill
                                    ? 'Tap a tier to choose who goes in it. Or add characters here and place them later.'
                                    : 'Search an anime, pick its characters, then drag them into tiers or tap one to place it.',
                            style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.35),
                          ),
                        )
                      else
                        SizedBox(
                          // A face and its name: one line, or two (round nine).
                          height: tokenW * 1.5 +
                              4 +
                              (TierListSwitches.boardLook ? 25 : 14) * MediaQuery.textScalerOf(context).scale(1) +
                              6,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: n,
                            separatorBuilder: (_, _) => const SizedBox(width: 6),
                            itemBuilder: (_, i) => Align(
                              alignment: Alignment.topCenter,
                              child: _token(_list.unranked[i], _trayId, i, n, tokenW),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A dashed rectangle, an empty place to fill (round nine), in one path.
class _DashedBox extends CustomPainter {
  const _DashedBox({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 4.0, gap = 3.0;
    final r = (Offset.zero & size).deflate(0.5);
    final path = Path();
    void side(Offset a, Offset b) {
      final len = (b - a).distance;
      if (len == 0) return;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        final e = d + dash < len ? d + dash : len;
        path
          ..moveTo(a.dx + dir.dx * d, a.dy + dir.dy * d)
          ..lineTo(a.dx + dir.dx * e, a.dy + dir.dy * e);
      }
    }

    side(r.topLeft, r.topRight);
    side(r.topRight, r.bottomRight);
    side(r.bottomRight, r.bottomLeft);
    side(r.bottomLeft, r.topLeft);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color;
}

// ── the character's sheet ────────────────────────────────────
sealed class _CharacterAction {
  const _CharacterAction();
}

class _MoveTo extends _CharacterAction {
  const _MoveTo(this.tierId);
  final String? tierId; // null: unranked
}

class _Nudge extends _CharacterAction {
  const _Nudge(this.step);
  final int step;
}

class _Remove extends _CharacterAction {
  const _Remove();
}

class _CharacterSheet extends StatelessWidget {
  const _CharacterSheet({required this.list, required this.character});
  final TierList list;
  final TierCharacter character;

  @override
  Widget build(BuildContext context) {
    final current = list.tierOf(character.id);
    final slot = current?.characterIds ?? list.unranked;
    final i = slot.indexOf(character.id);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TierSheetHeader('Place this character'),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: CharacterPortrait(character: character, width: 56, showName: false)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(character.name, style: AppTheme.hankoSerif(fontSize: 19)),
                        if (character.mediaTitle != null) ...[
                          const SizedBox(height: 4),
                          Text(character.mediaTitle!,
                              style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone)),
                        ],
                        const SizedBox(height: 8),
                        TierEyebrow(current == null
                            ? 'Unranked'
                            : '${current.label.trim().isEmpty ? (TierListSwitches.editTiers ? list.displayName(current) : 'Unnamed tier') : current.label}  ·  ${i + 1} of ${slot.length}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: TierEyebrow('Move to'),
            ),
            // The tiers as chips in their own colours, top tier first, so the
            // choice reads like the list itself and the sheet stays short.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var t = 0; t < list.tiers.length; t++)
                    _destination(
                      context,
                      label: list.tiers[t].label.trim().isEmpty ? 'Tier ${t + 1}' : list.tiers[t].label,
                      pigment: TierPigment.at(list.tiers[t].pigment),
                      here: current?.id == list.tiers[t].id,
                      onTap: () => Navigator.pop(context, _MoveTo(list.tiers[t].id)),
                    ),
                  _destination(
                    context,
                    label: 'Unranked',
                    pigment: null,
                    here: current == null,
                    onTap: () => Navigator.pop(context, const _MoveTo(null)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TierGhostButton(
                    label: 'Move left',
                    icon: Icons.chevron_left_rounded,
                    dense: true,
                    onTap: i > 0 ? () => Navigator.pop(context, const _Nudge(-1)) : null,
                  ),
                  TierGhostButton(
                    label: 'Move right',
                    icon: Icons.chevron_right_rounded,
                    dense: true,
                    onTap: i < slot.length - 1 ? () => Navigator.pop(context, const _Nudge(1)) : null,
                  ),
                  TierGhostButton(
                    label: 'Remove from list',
                    icon: Icons.close_rounded,
                    dense: true,
                    onTap: () => Navigator.pop(context, const _Remove()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A tier as a chip in its own colour. Where the character is now carries
  /// a check and an outline, so it never rests on colour alone.
  Widget _destination(BuildContext context,
      {required String label, required TierPigment? pigment, required bool here, required VoidCallback onTap}) {
    final ink = pigment?.ink ?? AppTheme.hankoWashi;
    return TierPressable(
      label: here ? '$label, where they are now' : 'Move to $label',
      selected: here,
      ringInset: -3,
      onTap: here ? () => Navigator.pop(context) : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: pigment?.color ?? AppTheme.hankoSumi3,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          border: here
              ? Border.all(color: AppTheme.hankoSumi, width: 2)
              : (pigment == null ? Border.all(color: AppTheme.hankoEdge) : null),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (here) ...[
              Icon(Icons.check_rounded, size: 16, color: ink),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w600, color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── the tier's sheet ─────────────────────────────────────────
sealed class _TierEdit {
  const _TierEdit();
}

class _TierSaved extends _TierEdit {
  const _TierSaved(this.label, this.pigment);
  final String label;
  final int pigment;
}

class _TierMoved extends _TierEdit {
  const _TierMoved(this.step);
  final int step;
}

class _TierAddBelow extends _TierEdit {
  const _TierAddBelow();
}

class _TierDeleted extends _TierEdit {
  const _TierDeleted();
}

class _TierSheet extends StatefulWidget {
  const _TierSheet({required this.list, required this.tier, required this.onLive});
  final TierList list;
  final Tier tier;

  /// Round nine: the sheet saves as you type, so the plate behind it
  /// changes with it and swiping the sheet away keeps the name. Called
  /// after each change.
  final VoidCallback onLive;

  @override
  State<_TierSheet> createState() => _TierSheetState();
}

class _TierSheetState extends State<_TierSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.tier.label);
  late int _pigment = widget.tier.pigment;

  @override
  void initState() {
    super.initState();
    if (TierListSwitches.editTiers) _name.addListener(_liveName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _liveName() {
    final before = widget.tier.label;
    widget.list.renameTier(widget.tier.id, _name.text);
    if (widget.tier.label != before) widget.onLive();
  }

  void _setPigment(int p) {
    setState(() => _pigment = p);
    if (!TierListSwitches.editTiers) return;
    widget.list.setPigment(widget.tier.id, p);
    widget.onLive();
  }

  void _done() => Navigator.pop(context, _TierSaved(_name.text, _pigment));

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final i = list.indexOfTier(widget.tier.id);
    final suggestions = tierNameSuggestionsFor(list.templateId);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    // Done sits beside the title, outside the scroll, and the tier's own
    // moves come before the name ideas: at the bottom of fourteen rows of
    // ideas, Done was about 1,670 px down.
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TierSheetHeader(
            'Edit tier',
            subtitle: 'Tier ${i + 1} of ${list.tiers.length}',
            trailing: TierMainButton(label: 'Done', icon: Icons.check_rounded, onTap: _done),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ExcludeSemantics(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _name,
                            builder: (_, v, _) => MediaQuery.withNoTextScaling(
                              child: TierPlate(
                                label: v.text,
                                pigment: TierPigment.at(_pigment),
                                width: 76,
                                minHeight: 76,
                                fontSize: 15,
                                placeholder: 'Name',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _name,
                            autofocus: true,
                            maxLength: TierList.maxLabelLength,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _done(),
                            style: AppTheme.hankoSans(fontSize: 16),
                            cursorColor: AppTheme.hankoWashi,
                            decoration: InputDecoration(
                              labelText: 'Tier name',
                              labelStyle: AppTheme.hankoSans(color: AppTheme.hankoStone),
                              counterStyle: AppTheme.hankoSans(fontSize: 11, color: AppTheme.hankoAsh),
                              filled: true,
                              fillColor: AppTheme.hankoSumi3,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                                borderSide: const BorderSide(color: AppTheme.hankoEdge),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                                borderSide: const BorderSide(color: AppTheme.hankoHairline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                                borderSide: const BorderSide(color: AppTheme.hankoWashi, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: TierEyebrow('Colour'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (var p = 0; p < TierPigment.all.length; p++)
                          TierPressable(
                            label: TierPigment.all[p].name,
                            selected: p == _pigment,
                            onTap: () => _setPigment(p),
                            child: SizedBox(
                              width: AppTheme.hankoTouch,
                              height: AppTheme.hankoTouch,
                              child: Center(
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: TierPigment.all[p].color,
                                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                                    border: p == _pigment
                                        ? Border.all(color: AppTheme.hankoWashi, width: 2)
                                        : Border.all(color: AppTheme.hankoSumi2, width: 2),
                                  ),
                                  child: p == _pigment
                                      ? Icon(Icons.check_rounded, size: 18, color: TierPigment.all[p].ink)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TierGhostButton(
                          label: 'Move up',
                          icon: Icons.arrow_upward_rounded,
                          dense: true,
                          onTap: i > 0 ? () => Navigator.pop(context, const _TierMoved(-1)) : null,
                        ),
                        TierGhostButton(
                          label: 'Move down',
                          icon: Icons.arrow_downward_rounded,
                          dense: true,
                          onTap: i < list.tiers.length - 1 ? () => Navigator.pop(context, const _TierMoved(1)) : null,
                        ),
                        TierGhostButton(
                          label: 'Add a tier below',
                          icon: Icons.add_rounded,
                          dense: true,
                          onTap: list.tiers.length < TierList.maxTiers
                              ? () => Navigator.pop(context, const _TierAddBelow())
                              : null,
                        ),
                        TierGhostButton(
                          label: 'Delete tier',
                          icon: Icons.delete_outline_rounded,
                          dense: true,
                          onTap: list.tiers.length > TierList.minTiers
                              ? () => Navigator.pop(context, const _TierDeleted())
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 2),
                    child: TierEyebrow('Name ideas'),
                  ),
                  for (final s in suggestions) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(s.key, style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoAsh)),
                    ),
                    SizedBox(
                      height: AppTheme.hankoTouch,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: s.value.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, k) => _NameChip(
                          label: s.value[k],
                          onTap: () {
                            _name.text = s.value[k];
                            _name.selection = TextSelection.collapsed(offset: s.value[k].length);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TierPressable(
        label: 'Use the name $label',
        onTap: onTap,
        child: Container(
          height: AppTheme.hankoChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.hankoSumi3,
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
            border: Border.all(color: AppTheme.hankoHairline),
          ),
          child: Text(label, style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

class _RenameListDialog extends StatefulWidget {
  const _RenameListDialog({required this.title, required this.prompt});
  final String title;
  final String prompt;

  @override
  State<_RenameListDialog> createState() => _RenameListDialogState();
}

class _RenameListDialogState extends State<_RenameListDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _prompt = TextEditingController(text: widget.prompt);

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: AppTheme.hankoSans(color: AppTheme.hankoStone),
        counterStyle: AppTheme.hankoSans(fontSize: 11, color: AppTheme.hankoAsh),
        filled: true,
        fillColor: AppTheme.hankoSumi3,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          borderSide: const BorderSide(color: AppTheme.hankoHairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          borderSide: const BorderSide(color: AppTheme.hankoWashi, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.hankoSumi2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoSheetRadius)),
      title: Text('Rename list', style: AppTheme.hankoSerif(fontSize: 20)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: TierList.maxTitleLength,
              style: AppTheme.hankoSans(fontSize: 16),
              cursorColor: AppTheme.hankoWashi,
              decoration: _field('Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _prompt,
              maxLength: 120,
              maxLines: 2,
              minLines: 1,
              style: AppTheme.hankoSans(fontSize: 14),
              cursorColor: AppTheme.hankoWashi,
              decoration: _field('The question it answers (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: AppTheme.hankoSans(weight: FontWeight.w600, color: AppTheme.hankoStone)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, (_title.text, _prompt.text)),
          child: Text('Save', style: AppTheme.hankoSans(weight: FontWeight.w600)),
        ),
      ],
    );
  }
}
