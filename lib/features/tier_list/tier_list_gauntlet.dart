// Tier lists, round nine: the Gauntlet. One challenger against five
// opponents, a phase at a time, each harder: how far do they go?
//
// People post these as questions ("How far does Naruto get?") and answer
// them in the replies, so a gauntlet can leave its answer open, or say
// where the challenger falls, or that they clear all five. Underneath it is
// a tier list (the template `gauntlet`: the first tier holds the
// challenger, each phase one opponent, and `TierList.verdict` the answer),
// so it saves, loads and shares like the others. With
// `TierListSwitches.gauntlet` off it opens as a plain six-tier list.
//
// The answer is the person's own verdict, so it is pressed as the seal:
// coral "Falls" on the phase where the challenger falls, or "Clears" at the
// finish. Beaten phases carry a washi check and the word, phases past the
// fall are dimmed with a dash: never colour alone.
//
// This file: the board (TierGauntletScreen), the picture
// (TierGauntletPoster), and the start screen's card and saved-list strip.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/hanko_seal.dart';
import 'tier_list_anilist.dart';
import 'tier_list_editor_screen.dart';
import 'tier_list_export_screen.dart';
import 'tier_list_model.dart';
import 'tier_list_picker_screen.dart';
import 'tier_list_store.dart';
import 'tier_list_templates.dart';
import 'tier_list_widgets.dart';

/// What one phase shows for the gauntlet's answer.
enum GauntletMark {
  /// No answer yet.
  open,

  /// The challenger got past this phase.
  beats,

  /// The challenger falls here.
  falls,

  /// The challenger never got this far.
  notReached,
}

/// A gauntlet's shape, read from its tiers.
extension TierGauntlet on TierList {
  bool get isGauntlet => templateId == kGauntletTemplate.id;

  /// The challenger's tier: the first.
  Tier? get challengerTier => tiers.isEmpty ? null : tiers.first;

  /// The phases, easiest first: every tier after the challenger's.
  List<Tier> get phases => tiers.length < 2 ? const [] : tiers.sublist(1);

  /// The one character in [t], or null.
  TierCharacter? holderOf(Tier t) => t.characterIds.isEmpty ? null : characters[t.characterIds.first];

  TierCharacter? get challenger {
    final t = challengerTier;
    return t == null ? null : holderOf(t);
  }

  /// A challenger and an opponent in every phase: ready to share.
  bool get gauntletReady =>
      challenger != null && phases.isNotEmpty && phases.every((p) => p.characterIds.isNotEmpty);

  /// The phase (from 1) where the challenger falls, or null.
  int? get fallsAt {
    final v = verdict;
    if (v == null || v == TierList.verdictClear) return null;
    final i = phases.indexWhere((p) => p.id == v);
    return i < 0 ? null : i + 1;
  }

  bool get clearsAll => verdict == TierList.verdictClear;

  /// What phase [n] (from 1) shows.
  GauntletMark markOf(int n) {
    if (clearsAll) return GauntletMark.beats;
    final f = fallsAt;
    if (f == null) return GauntletMark.open;
    if (n < f) return GauntletMark.beats;
    return n == f ? GauntletMark.falls : GauntletMark.notReached;
  }

  /// "five", for "Clears all five".
  String get phaseCountWord {
    const words = ['none', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
    final n = phases.length;
    return n < words.length ? words[n] : '$n';
  }

  /// The answer in words: "Falls at Phase 3", "Clears all five", or null
  /// while it's open.
  String? get verdictLine {
    final f = fallsAt;
    if (f != null) return 'Falls at Phase $f';
    if (clearsAll) return 'Clears all $phaseCountWord';
    return null;
  }
}

/// The title a gauntlet gives itself from its challenger: "How far does
/// Naruto Uzumaki go?". The template's own title until there is one.
String gauntletTitleFor(TierCharacter? challenger) =>
    challenger == null ? (kGauntletTemplate.title ?? kGauntletTemplate.name) : 'How far does ${challenger.name} go?';

/// A row's ground on the board and the picture: its pigment at 7% over
/// sumi 2, as the tier rows are (round nine).
Color _phaseGround(Tier t) =>
    Color.alphaBlend(TierPigment.at(t.pigment).color.withValues(alpha: 0.07), AppTheme.hankoSumi2);

// ── the board ────────────────────────────────────────────────

class TierGauntletScreen extends StatefulWidget {
  const TierGauntletScreen({super.key, required this.list});
  final TierList list;

  @override
  State<TierGauntletScreen> createState() => _TierGauntletScreenState();
}

class _TierGauntletScreenState extends State<TierGauntletScreen> {
  static const _removeAction = CustomSemanticsAction(label: 'Remove');

  TierList get _list => widget.list;

  Timer? _saveTimer;
  bool _dirty = false;
  bool _saveFailed = false;

  /// How many times each box has been stamped, for the seal's press.
  final Map<String, int> _presses = {};

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_dirty) unawaited(TierListStore.instance.save(_list));
    super.dispose();
  }

  // ── saving, as the tier board does ─────────────────────────
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

  String get _who => _list.challenger?.name ?? 'The challenger';

  String _slotName(Tier t) {
    final i = _list.phases.indexWhere((p) => p.id == t.id);
    return i < 0 ? 'Challenger' : 'Phase ${i + 1}';
  }

  /// The anime already in the gauntlet, for the picker's quick picks.
  List<TierAnime> _listAnime() => [
        for (final m in _list.mediaByUse())
          if (_list.sampleOf(m.key) case final TierCharacter c when c.mediaTitle != null)
            TierAnime(id: m.key, title: c.mediaTitle!, cover: c.mediaCover, color: c.mediaColor),
      ].take(4).toList();

  // ── picking ────────────────────────────────────────────────
  Future<void> _pick(Tier slot) async {
    final template = tierTemplateById(_list.templateId) ?? kGauntletTemplate;
    final current = _list.holderOf(slot);
    final elsewhere =
        await TierListStore.instance.charactersElsewhere(_list.id, skip: _list.characters.keys.toSet());
    if (!mounted) return;
    final picked = await Navigator.of(context).push<List<TierCharacter>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TierCharacterPickerScreen(
          alreadyOnList: _list.characters.keys.toSet(),
          room: 1,
          ideas: TierSearchIdeas(characters: template.characters, anime: template.anime),
          target: TierPickTarget(label: _slotName(slot), pigment: TierPigment.at(slot.pigment)),
          single: true,
          current: current,
          listAnime: _listAnime(),
          fromOtherLists: elsewhere,
        ),
      ),
    );
    if (!mounted || picked == null || _list.tierById(slot.id) == null) return;
    if (picked.isEmpty) {
      _clear(slot);
      return;
    }
    final c = picked.first;
    final isChallenger = slot.id == _list.challengerTier?.id;
    final oldTitle = gauntletTitleFor(_list.challenger);
    if (!_list.setSlot(slot.id, c)) return;
    if (isChallenger) _retitle(oldTitle);
    _changed();
    _announce('${_slotName(slot)}: ${c.name}');
  }

  void _clear(Tier slot) {
    final isChallenger = slot.id == _list.challengerTier?.id;
    final oldTitle = gauntletTitleFor(_list.challenger);
    if (_list.clearTier(slot.id) == 0) return;
    if (isChallenger) _retitle(oldTitle);
    _changed();
    _announce('${_slotName(slot)} is empty');
  }

  /// A title the gauntlet wrote follows its challenger; one the person
  /// typed stays.
  void _retitle(String oldTitle) {
    if (_list.title != oldTitle) return;
    final t = gauntletTitleFor(_list.challenger);
    if (t.length <= TierList.maxTitleLength) _list.title = t;
  }

  // ── the answer ─────────────────────────────────────────────
  void _mark(Tier phase) {
    final on = _list.verdict != phase.id;
    if (!_list.setVerdict(on ? phase.id : null)) return;
    if (on) _presses[phase.id] = (_presses[phase.id] ?? 0) + 1;
    _changed();
    _announce(on ? '$_who falls at ${_slotName(phase)}' : 'Left open');
  }

  void _markClear() {
    final on = !_list.clearsAll;
    if (!_list.setVerdict(on ? TierList.verdictClear : null)) return;
    if (on) _presses[TierList.verdictClear] = (_presses[TierList.verdictClear] ?? 0) + 1;
    _changed();
    _announce(on ? '$_who clears all ${_list.phaseCountWord}' : 'Left open');
  }

  // ── the menu, renaming, sharing ────────────────────────────
  Future<void> _rename() async {
    final result = await showTierListRenameDialog(context, _list);
    if (!mounted || result == null) return;
    final (title, prompt) = result;
    _list.title = title.trim().isEmpty ? _list.title : title.trim();
    _list.prompt = prompt.trim();
    _changed();
  }

  Future<void> _menu(String value) async {
    switch (value) {
      case 'rename':
        await _rename();
      case 'open':
        if (_list.setVerdict(null)) {
          _changed();
          _announce('Left open');
        }
      case 'delete':
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.hankoSumi2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoSheetRadius)),
            title: Text('Delete this gauntlet?', style: AppTheme.hankoSerif(fontSize: 20)),
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
    if (!_list.gauntletReady) {
      tierToast(context, 'Pick a challenger and all ${_list.phaseCountWord} opponents first.');
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
    final cover = _list.challenger?.mediaColor;
    final tint = cover == null ? null : AppTheme.hankoCoverTint(Color(cover))?.withValues(alpha: 0.16);
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: SafeArea(
        child: Column(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: _topBar(),
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
                      height: 260,
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
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        children: [
                          _header(),
                          const SizedBox(height: 18),
                          _challengerBlock(),
                          const SizedBox(height: 16),
                          const _VsRule(),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _list.phases.length; i++) ...[
                            KeyedSubtree(key: ValueKey('phase-${_list.phases[i].id}'), child: _phaseRow(_list.phases[i], i + 1)),
                            const SizedBox(height: 2),
                          ],
                          _finishRow(),
                          const SizedBox(height: 14),
                          Text(
                            _list.gauntletReady
                                ? 'Tap a phase’s box to mark where they fall, or leave it open for whoever sees the picture.'
                                : 'Pick the challenger, then an opponent for every phase, the hardest last.',
                            style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.4),
                          ),
                        ],
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Text(
                'Gauntlet',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: AppTheme.hankoSerif(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(width: 6),
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
              _menuItem('rename', Icons.edit_rounded, 'Rename'),
              if (_list.verdict != null) _menuItem('open', Icons.help_outline_rounded, 'Leave the answer open'),
              _menuItem('delete', Icons.delete_outline_rounded, 'Delete gauntlet'),
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
    final bits = <String>[
      'Gauntlet',
      _list.phases.length == 1 ? '1 phase' : '${_list.phases.length} phases',
      if (_saveFailed) 'not saved',
    ];
    // Until there is a challenger, the question stands in for the title
    // the gauntlet will give itself.
    final asking = _list.challenger == null && _list.title == gauntletTitleFor(null);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TierEyebrow(bits.join('  ·  '), color: _saveFailed ? AppTheme.hankoWashi : AppTheme.hankoStone),
          const SizedBox(height: 8),
          TierPressable(
            label: '${_list.title}. Rename',
            onTap: _rename,
            child: Text(
              asking ? 'How far does your pick go?' : _list.title,
              style: AppTheme.hankoSerif(
                fontSize: 24,
                height: 1.2,
                color: asking ? AppTheme.hankoStoneHi : AppTheme.hankoWashi,
              ),
            ),
          ),
          if (_list.prompt.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_list.prompt, style: AppTheme.hankoSans(fontSize: 15, color: AppTheme.hankoStoneHi, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _challengerBlock() {
    final slot = _list.challengerTier;
    if (slot == null) return const SizedBox.shrink();
    final c = _list.holderOf(slot);
    final line = _list.verdictLine;
    return TierPressable(
      label: c == null
          ? 'Challenger: pick one'
          : 'Challenger: ${c.name}${c.mediaTitle == null ? '' : ', ${c.mediaTitle}'}. ${line ?? 'Answer open'}.',
      hint: c == null ? 'Opens the picker' : 'Changes the challenger',
      customActions: c == null ? null : {_removeAction: () => _clear(slot)},
      onTap: () => _pick(slot),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          c == null
              ? const _EmptySlot(width: 96, big: true)
              : CharacterPortrait(character: c, width: 96, showName: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                TierEyebrow('The challenger', color: TierPigment.gold.color),
                const SizedBox(height: 6),
                Text(
                  c?.name ?? 'Pick the challenger',
                  style: AppTheme.hankoSerif(fontSize: 21, height: 1.2, color: c == null ? AppTheme.hankoStoneHi : AppTheme.hankoWashi),
                ),
                if (c?.mediaTitle != null) ...[
                  const SizedBox(height: 4),
                  Text(c!.mediaTitle!, style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.3)),
                ],
                if (c == null) ...[
                  const SizedBox(height: 4),
                  Text('Who goes through the gauntlet?',
                      style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.3)),
                ],
                if (c != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    line ?? 'How far do they go? Mark it below, or leave it open.',
                    style: line == null
                        ? AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.35)
                        : AppTheme.hankoSans(fontSize: 15, weight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseRow(Tier phase, int n) {
    final c = _list.holderOf(phase);
    final mark = _list.markOf(n);
    final canMark = c != null && _list.challenger != null;
    final falls = mark == GauntletMark.falls;
    final state = switch (mark) {
      GauntletMark.open => 'open',
      GauntletMark.beats => 'beaten',
      GauntletMark.falls => '$_who falls here',
      GauntletMark.notReached => 'not reached',
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(child: _PhasePlate(n: n, pigment: TierPigment.at(phase.pigment), width: 48)),
          Expanded(
            child: ColoredBox(
              color: _phaseGround(phase),
              child: Row(
                children: [
                  Expanded(
                    child: TierPressable(
                      label: c == null
                          ? 'Phase $n: pick an opponent'
                          : 'Phase $n: ${c.name}${c.mediaTitle == null ? '' : ', ${c.mediaTitle}'}. $state',
                      hint: c == null ? 'Opens the picker' : 'Changes this opponent',
                      customActions: c == null ? null : {_removeAction: () => _clear(phase)},
                      onTap: () => _pick(phase),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            if (c == null)
                              const _EmptySlot(width: 52)
                            else
                              Opacity(
                                opacity: mark == GauntletMark.notReached ? 0.4 : 1,
                                child: CharacterPortrait(character: c, width: 52, showName: false),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c?.name ?? 'Pick an opponent',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.hankoSans(
                                      fontSize: 14,
                                      weight: c == null ? FontWeight.w500 : FontWeight.w600,
                                      color: c == null ? AppTheme.hankoStone : AppTheme.hankoWashi,
                                      height: 1.25,
                                    ),
                                  ),
                                  if (c?.mediaTitle != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      c!.mediaTitle!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.hankoSans(fontSize: 12, color: AppTheme.hankoStone, height: 1.25),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TierPressable(
                    label: canMark ? 'Phase $n: $state' : 'Phase $n: no opponent yet',
                    hint: !canMark
                        ? null
                        : (falls ? 'Leaves the answer open' : 'Marks that $_who falls here'),
                    selected: canMark ? falls : null,
                    onTap: canMark ? () => _mark(phase) : null,
                    child: SizedBox(
                      width: 64,
                      child: Center(
                        child: _MarkBox(
                          mark: mark,
                          enabled: canMark,
                          presses: _presses[phase.id] ?? 0,
                          sealLabel: 'Falls',
                          editing: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _finishRow() {
    final ready = _list.gauntletReady;
    final cleared = _list.clearsAll;
    final all = 'Clears all ${_list.phaseCountWord}';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ExcludeSemantics(child: _FinishPlate(width: 48)),
          Expanded(
            child: ColoredBox(
              color: AppTheme.hankoSumi2,
              child: TierPressable(
                label: !ready ? '$all: every phase needs an opponent first' : '$all: ${cleared ? 'marked' : 'open'}',
                hint: !ready ? null : (cleared ? 'Leaves the answer open' : 'Marks that $_who clears them all'),
                selected: ready ? cleared : null,
                onTap: ready ? _markClear : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          all,
                          style: AppTheme.hankoSans(
                            fontSize: 14,
                            weight: FontWeight.w600,
                            color: ready ? AppTheme.hankoWashi : AppTheme.hankoStone,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: _MarkBox(
                            mark: cleared ? GauntletMark.falls : GauntletMark.open,
                            enabled: ready,
                            presses: _presses[TierList.verdictClear] ?? 0,
                            sealLabel: 'Clears',
                            editing: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── the pieces ───────────────────────────────────────────────

/// "PHASE 3": the phase's numeral on its pigment, the tier plate's idea.
class _PhasePlate extends StatelessWidget {
  const _PhasePlate({required this.n, required this.pigment, required this.width});
  final int n;
  final TierPigment pigment;
  final double width;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: pigment.color,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: MediaQuery.withNoTextScaling(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'PHASE',
                  style: AppTheme.hankoSans(fontSize: 8, weight: FontWeight.w600, color: pigment.ink, letterSpacing: 1.2),
                ),
                const SizedBox(height: 2),
                Text('$n', style: AppTheme.hankoSerif(fontSize: 26, color: pigment.ink, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The finish line's plate: a flag in washi on ink.
class _FinishPlate extends StatelessWidget {
  const _FinishPlate({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: TierPigment.sumiInk.color,
      alignment: Alignment.center,
      child: Icon(Icons.flag_rounded, size: 20, color: TierPigment.sumiInk.ink),
    );
  }
}

/// An empty place for a character: a dashed print-sized frame with a plus.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.width, this.big = false});
  final double width;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: CustomPaint(
        painter: const _Dashes(color: AppTheme.hankoEdge),
        child: Center(
          child: Icon(Icons.add_rounded, size: big ? 28 : 20, color: AppTheme.hankoStone),
        ),
      ),
    );
  }
}

/// A phase's (or the finish line's) answer: the dashed slot while open (a
/// plus on the board, nothing on the picture), the coral seal where the
/// challenger falls (or clears them all), a washi check on a beaten phase,
/// and a dash on one never reached.
class _MarkBox extends StatelessWidget {
  const _MarkBox({
    required this.mark,
    required this.enabled,
    required this.presses,
    required this.sealLabel,
    required this.editing,
  });

  final GauntletMark mark;
  final bool enabled;
  final int presses;
  final String sealLabel;

  /// On the board (a plus in the open slot) rather than the picture.
  final bool editing;

  @override
  Widget build(BuildContext context) {
    switch (mark) {
      case GauntletMark.open:
        return Opacity(
          opacity: enabled ? 1 : 0.35,
          child: HankoSeal.unrated(size: 36, width: 52, showAdd: editing && enabled),
        );
      case GauntletMark.falls:
        final seal = HankoSeal(label: sealLabel, size: 36, width: 56);
        return editing ? HankoSealPress(presses: presses, child: seal) : seal;
      case GauntletMark.beats:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 22, color: AppTheme.hankoWashi),
            const SizedBox(height: 2),
            MediaQuery.withNoTextScaling(child: const TierEyebrow('Beats', color: AppTheme.hankoStoneHi)),
          ],
        );
      case GauntletMark.notReached:
        // Stone, not ash: ash is only just 4.5:1 on the phases' grounds.
        return Text('—', style: AppTheme.hankoSans(fontSize: 18, color: AppTheme.hankoStone));
    }
  }
}

/// "VS" between the challenger and the phases.
class _VsRule extends StatelessWidget {
  const _VsRule();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          const Expanded(child: ColoredBox(color: AppTheme.hankoHairline, child: SizedBox(height: 1))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('VS', style: AppTheme.hankoSerif(fontSize: 15, color: AppTheme.hankoStone, letterSpacing: 1)),
          ),
          const Expanded(child: ColoredBox(color: AppTheme.hankoHairline, child: SizedBox(height: 1))),
        ],
      ),
    );
  }
}

/// A dashed rectangle in one path.
class _Dashes extends CustomPainter {
  const _Dashes({required this.color});
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
  bool shouldRepaint(_Dashes old) => old.color != color;
}

// ── the picture ──────────────────────────────────────────────

/// The exported gauntlet: 360 wide (1080 px at 3x) and as tall as it needs,
/// drawn like the tier list's picture (TierListPoster): the challenger's
/// anime colour as the wash, the question as the title, the challenger
/// large, then the phases and the answer. An open gauntlet prints its
/// boxes empty: a question for whoever sees it.
class TierGauntletPoster extends StatelessWidget {
  const TierGauntletPoster({super.key, required this.list, this.date});

  final TierList list;

  /// The date in the corner; the list's last edit when null.
  final DateTime? date;

  static const double width = 360;
  static const double _pad = 18;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// What a screen reader says the picture is.
  static String describe(TierList list) {
    final parts = <String>[list.title];
    final c = list.challenger;
    parts.add('Challenger: ${c?.name ?? 'nobody yet'}');
    for (var i = 0; i < list.phases.length; i++) {
      final o = list.holderOf(list.phases[i]);
      final mark = switch (list.markOf(i + 1)) {
        GauntletMark.open => '',
        GauntletMark.beats => ', beaten',
        GauntletMark.falls => ', where ${c?.name ?? 'the challenger'} falls',
        GauntletMark.notReached => ', not reached',
      };
      parts.add('Phase ${i + 1}: ${o?.name ?? 'nobody'}$mark');
    }
    parts.add(list.verdictLine ?? 'The answer is left open');
    return parts.join('. ');
  }

  @override
  Widget build(BuildContext context) {
    final c = list.challenger;
    final cover = c?.mediaColor;
    final wash = cover == null ? null : AppTheme.hankoCoverTint(Color(cover));
    final d = date ?? list.updatedAt;
    final line = list.verdictLine;
    return Container(
      width: width,
      color: AppTheme.hankoSumi,
      child: Stack(
        children: [
          if (wash != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 300,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [wash, wash.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          const Positioned.fill(child: CustomPaint(painter: TierDotGrid())),
          Padding(
            padding: const EdgeInsets.fromLTRB(_pad, 22, _pad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gauntlet  ·  ${list.phases.length} phases'.toUpperCase(),
                  style: AppTheme.hankoSans(
                    fontSize: 9.5,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoStoneHi,
                    letterSpacing: 2,
                    tabular: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(list.title, maxLines: 3, overflow: TextOverflow.fade, style: AppTheme.hankoSerif(fontSize: 27, height: 1.15)),
                if (list.prompt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    list.prompt,
                    maxLines: 3,
                    style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStoneHi, height: 1.35),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c == null)
                      const _EmptySlot(width: 112, big: true)
                    else
                      CharacterPortrait(character: c, width: 112, showName: false, exportMode: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          Text(
                            'THE CHALLENGER',
                            style: AppTheme.hankoSans(
                              fontSize: 9.5,
                              weight: FontWeight.w500,
                              color: TierPigment.gold.color,
                              letterSpacing: 2,
                              tabular: true,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(c?.name ?? '?', maxLines: 3, style: AppTheme.hankoSerif(fontSize: 22, height: 1.15)),
                          if (c?.mediaTitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              c!.mediaTitle!,
                              maxLines: 2,
                              style: AppTheme.hankoSans(fontSize: 11.5, color: AppTheme.hankoStone, height: 1.3),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            line ?? 'Where do they fall?',
                            style: line == null
                                ? AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStoneHi, height: 1.3)
                                : AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w600, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _VsRule(),
                const SizedBox(height: 12),
                for (var i = 0; i < list.phases.length; i++) ...[
                  _posterPhase(list.phases[i], i + 1),
                  const SizedBox(height: 2),
                ],
                _posterFinish(),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Image.asset(TierListPoster.wing, width: 18, height: 18, fit: BoxFit.contain),
                    const SizedBox(width: 7),
                    Text('Hanj', style: AppTheme.hankoSerif(fontSize: 19, height: 1, letterSpacing: 0.2)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'GAUNTLET',
                        style: AppTheme.hankoSans(
                          fontSize: 8.5,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoStone,
                          letterSpacing: 2,
                          tabular: true,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${d.day} ${_months[d.month - 1]} ${d.year}',
                            textAlign: TextAlign.right,
                            style: AppTheme.hankoSans(fontSize: 10, color: AppTheme.hankoStone, tabular: true),
                          ),
                        ),
                      ),
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

  Widget _posterPhase(Tier phase, int n) {
    final o = list.holderOf(phase);
    final mark = list.markOf(n);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhasePlate(n: n, pigment: TierPigment.at(phase.pigment), width: 46),
          Expanded(
            child: Container(
              color: _phaseGround(phase),
              padding: const EdgeInsets.all(5),
              child: Row(
                children: [
                  if (o == null)
                    const _EmptySlot(width: 58)
                  else
                    Opacity(
                      opacity: mark == GauntletMark.notReached ? 0.4 : 1,
                      child: CharacterPortrait(character: o, width: 58, showName: false, exportMode: true),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o?.name ?? '?',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w600, height: 1.2),
                        ),
                        if (o?.mediaTitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            o!.mediaTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.hankoSans(fontSize: 10.5, color: AppTheme.hankoStone, height: 1.2),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Center(
                      child: _MarkBox(mark: mark, enabled: true, presses: 0, sealLabel: 'Falls', editing: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFinish() {
    final cleared = list.clearsAll;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FinishPlate(width: 46),
          Expanded(
            child: Container(
              color: AppTheme.hankoSumi2,
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Clears all ${list.phaseCountWord}',
                      style: AppTheme.hankoSans(fontSize: 13, weight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Center(
                      child: _MarkBox(
                        mark: cleared ? GauntletMark.falls : GauntletMark.open,
                        enabled: true,
                        presses: 0,
                        sealLabel: 'Clears',
                        editing: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── the start screen ─────────────────────────────────────────

/// The start screen's way into a gauntlet: a rising staircase of five phase
/// plates beside the gold challenger, drawn, so it costs no picture.
class TierGauntletCard extends StatelessWidget {
  const TierGauntletCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = kGauntletTemplate.pigmentsOrRamp;
    return TierPressable(
      label: 'Gauntlet. How far does your pick go? One challenger against five opponents, a phase at a time.',
      hint: 'Starts a new gauntlet',
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.hankoSumi2,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          border: Border.all(color: AppTheme.hankoHairline),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(
                child: SizedBox(
                  height: 58,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 40,
                        height: 58,
                        color: TierPigment.at(p.first).color,
                        alignment: Alignment.center,
                        child: Icon(Icons.person_rounded, size: 22, color: TierPigment.at(p.first).ink),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('VS', style: AppTheme.hankoSerif(fontSize: 13, color: AppTheme.hankoStone)),
                      ),
                      const SizedBox(width: 8),
                      for (var i = 1; i < p.length; i++) ...[
                        Expanded(
                          child: Container(
                            height: 18.0 + (i - 1) * 10,
                            color: TierPigment.at(p[i]).color,
                            alignment: Alignment.center,
                            child: Text('$i', style: AppTheme.hankoSerif(fontSize: 12, color: TierPigment.at(p[i]).ink, height: 1)),
                          ),
                        ),
                        if (i < p.length - 1) const SizedBox(width: 3),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const TierEyebrow('Gauntlet'),
            const SizedBox(height: 6),
            Text('How far does your pick go?', style: AppTheme.hankoSerif(fontSize: 19, height: 1.2)),
            const SizedBox(height: 6),
            Text(
              'One challenger, five fights in a row. Mark where they fall, or post it as a question.',
              style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Flexible(
                  child: Text('Start a gauntlet',
                      style: AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: AppTheme.hankoWashi),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved gauntlet on the start screen: the challenger, "vs", and the
/// phases' faces, dimmed past the fall.
class TierGauntletStrip extends StatelessWidget {
  const TierGauntletStrip({super.key, required this.list});
  final TierList list;

  @override
  Widget build(BuildContext context) {
    final c = list.challenger;
    return ExcludeSemantics(
      child: SizedBox(
        height: 42,
        child: ClipRect(
          child: Row(
            children: [
              if (c != null) CharacterPortrait(character: c, width: 28, showName: false) else const _EmptySlot(width: 28),
              const SizedBox(width: 8),
              MediaQuery.withNoTextScaling(
                child: Text('vs', style: AppTheme.hankoSerif(fontSize: 13, color: AppTheme.hankoStone)),
              ),
              const SizedBox(width: 8),
              for (var i = 0; i < list.phases.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: switch (list.holderOf(list.phases[i])) {
                    final TierCharacter o => Opacity(
                        opacity: list.markOf(i + 1) == GauntletMark.notReached ? 0.4 : 1,
                        child: CharacterPortrait(character: o, width: 24, showName: false),
                      ),
                    null => const _EmptySlot(width: 24),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
