import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/arcs_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hanko_print.dart';
import 'arcs_hanko.dart';

// ─────────────────────────────────────────────────────────────
// Arcs' forms in flat Hanko (arcs redesign, 2026-11-14): starting an arc
// and writing a post. Forms get nothing decorative (the Vibes rule): sumi 2
// sheets with 6 dp top corners, Hanko fields, printed chips for choices,
// and one washi main action. A refused write keeps everything typed and
// says why under the action.
// ─────────────────────────────────────────────────────────────

Widget _sheet(BuildContext context, {required Widget child}) {
  final media = MediaQuery.of(context);
  return Padding(
    padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
      child: Material(
        color: AppTheme.hankoSumi2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.hankoSheetRadius)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(top: false, child: child),
      ),
    ),
  );
}

InputDecoration _field(String hint) {
  final edge = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
    borderSide: const BorderSide(color: AppTheme.hankoEdge),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: AppTheme.hankoSans(color: AppTheme.hankoAsh, height: 1.35),
    filled: true,
    fillColor: AppTheme.hankoSumi3,
    isDense: true,
    counterStyle: AppTheme.hankoSans(
        fontSize: AppTheme.hankoDataSmallSize, color: AppTheme.hankoStone),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: edge,
    enabledBorder: edge,
    focusedBorder:
        edge.copyWith(borderSide: const BorderSide(color: AppTheme.hankoWashi)),
  );
}

Widget _label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(s,
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoLabelSize,
              weight: FontWeight.w500,
              color: AppTheme.hankoStone,
              letterSpacing: 0.5)),
    );

Widget _refusal(String? s) => s == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.error_outline_sharp,
                    size: 18, color: AppTheme.hankoWashi),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s,
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize, height: 1.4)),
              ),
            ],
          ),
        ),
      );

/// A number with − and +, one adjustable control for a screen reader.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, int to, bool can) => InkWell(
          onTap: can ? () => onChanged(to) : null,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          child: SizedBox(
            width: AppTheme.hankoTouch,
            height: AppTheme.hankoTouch,
            child: Icon(icon,
                size: 20,
                color: can ? AppTheme.hankoWashi : AppTheme.hankoEdge),
          ),
        );
    return Semantics(
      container: true,
      label: label,
      value: '$value',
      increasedValue: value < max ? '${value + 1}' : null,
      decreasedValue: value > min ? '${value - 1}' : null,
      onIncrease: value < max ? () => onChanged(value + 1) : null,
      onDecrease: value > min ? () => onChanged(value - 1) : null,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.hankoSumi3,
            border: Border.all(color: AppTheme.hankoEdge),
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              step(Icons.remove_sharp, value - 1, value > min),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 40),
                child: Text('$value',
                    textAlign: TextAlign.center,
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoListTitleSize,
                        weight: FontWeight.w600,
                        tabular: true)),
              ),
              step(Icons.add_sharp, value + 1, value < max),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Write a post
// ─────────────────────────────────────────────────────────────

/// Opens the post sheet for [arc], the episode set to [ep]. Returns true
/// once posted.
Future<bool?> showArcPostSheet(BuildContext context,
    {required Arc arc, required String uid, required int ep}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PostSheet(arc: arc, uid: uid, ep: ep),
  );
}

class _PostSheet extends StatefulWidget {
  const _PostSheet({required this.arc, required this.uid, required this.ep});

  final Arc arc;
  final String uid;
  final int ep;

  @override
  State<_PostSheet> createState() => _PostSheetState();
}

class _PostSheetState extends State<_PostSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _bodyFocus = FocusNode();
  late int _ep = widget.ep.clamp(widget.arc.from, widget.arc.to);
  bool _posting = false;
  String? _refused;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
    // A field that appears after a tap doesn't take focus by itself
    // (web-emulator-e2e), so ask for it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bodyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_body.text.trim().isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _refused = null;
    });
    try {
      await ArcsService.instance.addPost(
        arcId: widget.arc.id,
        uid: widget.uid,
        title: _title.text,
        body: _body.text,
        ep: _ep,
      );
      if (mounted) Navigator.pop(context, true);
      return;
    } on ArcsFailure catch (e) {
      if (mounted) setState(() => _refused = e.message);
    }
    if (mounted) setState(() => _posting = false);
  }

  @override
  Widget build(BuildContext context) {
    final arc = widget.arc;
    return _sheet(
      context,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 20, AppTheme.hankoGutter, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Write about episode $_ep',
                style: AppTheme.hankoSerif(fontSize: 20, height: 1.3)),
            const SizedBox(height: 4),
            Text(
                'Readers who haven\'t reached episode $_ep see it sealed '
                'until they do.',
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    color: AppTheme.hankoStone,
                    height: 1.4)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Episode',
                    style: AppTheme.hankoSans(weight: FontWeight.w500)),
                _Stepper(
                  label: 'Episode',
                  value: _ep,
                  min: arc.from,
                  max: arc.to,
                  onChanged: (v) => setState(() => _ep = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _label('TITLE (OPTIONAL)'),
            TextField(
              controller: _title,
              maxLength: ArcLimits.title,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppTheme.hankoWashi,
              style: AppTheme.hankoSans(height: 1.35),
              decoration: _field('A line for the top'),
            ),
            const SizedBox(height: 8),
            _label('POST'),
            TextField(
              controller: _body,
              focusNode: _bodyFocus,
              minLines: 4,
              maxLines: 8,
              maxLength: ArcLimits.body,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppTheme.hankoWashi,
              style: AppTheme.hankoSans(height: 1.45),
              decoration: _field('What did you make of it?'),
            ),
            const SizedBox(height: 12),
            ArcAction(
              label: 'Post',
              icon: Icons.send_sharp,
              expand: true,
              busy: _posting,
              busyLabel: 'Posting…',
              onTap: _body.text.trim().isEmpty ? null : _post,
            ),
            _refusal(_refused),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Start an arc
// ─────────────────────────────────────────────────────────────

/// Opens the start sheet. With [show], it starts there; otherwise it first
/// offers the shows on your list. Returns the new arc's id.
Future<String?> showArcStartSheet(BuildContext context, {ArcShow? show}) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Future.value(null);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ArcStartSheet(uid: uid, show: show),
  );
}

class ArcStartSheet extends StatefulWidget {
  const ArcStartSheet({super.key, required this.uid, this.show, this.today});

  final String uid;
  final ArcShow? show;

  /// The day it counts from; tests pin it.
  final DateTime? today;

  @override
  State<ArcStartSheet> createState() => _ArcStartSheetState();
}

class _ArcStartSheetState extends State<ArcStartSheet> {
  static const _paces = [1, 2, 3, 4, 6];
  static final DateFormat _day = DateFormat('EEE d MMM');

  Future<List<ArcListEntry>>? _list;
  ArcShow? _show;
  int _progress = 0;

  int _from = 1;
  int _to = 12;
  int _pace = 3;
  int _start = 0; // 0 today, 1 this Saturday, 2 in a week
  final _name = TextEditingController();
  final _about = TextEditingController();
  bool _nameTouched = false;
  bool _creating = false;
  String? _refused;

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  DateTime _startDay(int choice) {
    final t = _today;
    switch (choice) {
      case 1:
        final ahead = (DateTime.saturday - t.weekday) % 7;
        return DateTime(t.year, t.month, t.day + (ahead == 0 ? 7 : ahead));
      case 2:
        return DateTime(t.year, t.month, t.day + 7);
      default:
        return t;
    }
  }

  int get _max => _show?.episodes ?? 500;

  @override
  void initState() {
    super.initState();
    final show = widget.show;
    if (show != null) {
      _choose(show, 0);
    } else {
      _list = ArcsService.instance.listShows(widget.uid);
    }
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  void _choose(ArcShow show, int progress) {
    _show = show;
    _progress = progress;
    final total = show.episodes;
    _from = (progress > 0 && (total == null || progress < total)) ? progress + 1 : 1;
    _to = total ?? (_from + 11);
    _pace = (_to - _from + 1) <= 4 ? 1 : 3;
    _setName();
  }

  void _setName() {
    final show = _show;
    if (show == null || _nameTouched) return;
    final whole = _from == 1 && show.episodes != null && _to == show.episodes;
    var s = whole
        ? show.title
        : '${show.title}, episode${_from == _to ? '' : 's'} '
            '${_from == _to ? '$_from' : '$_from–$_to'}';
    if (s.length > ArcLimits.name) s = show.title;
    if (s.length > ArcLimits.name) s = s.substring(0, ArcLimits.name);
    _name.text = s;
  }

  Arc get _preview => Arc(
        id: '',
        name: _name.text,
        description: '',
        show: _show,
        from: _from,
        to: _to,
        pace: _pace,
        startsOn: _startDay(_start),
        members: const [],
        memberCount: 1,
        postCount: 0,
        createdBy: widget.uid,
        creatorName: '',
      );

  Future<void> _create() async {
    final show = _show;
    if (show == null || _name.text.trim().isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _refused = null;
    });
    try {
      final id = await ArcsService.instance.create(
        uid: widget.uid,
        show: show,
        name: _name.text,
        description: _about.text,
        from: _from,
        to: _to,
        pace: _pace,
        startsOn: _startDay(_start),
      );
      if (mounted) Navigator.pop(context, id);
      return;
    } on ArcsFailure catch (e) {
      if (mounted) setState(() => _refused = e.message);
    }
    if (mounted) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      context,
      child: _show == null ? _pick() : _settings(),
    );
  }

  // Step 1: a show from your list.
  Widget _pick() {
    return FutureBuilder<List<ArcListEntry>>(
      future: _list,
      builder: (context, snap) {
        final head = Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 20, AppTheme.hankoGutter, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Start an arc',
                  style: AppTheme.hankoSerif(fontSize: 20, height: 1.3)),
              const SizedBox(height: 4),
              Text('Pick a show from your list to watch together.',
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone,
                      height: 1.4)),
            ],
          ),
        );
        Widget body;
        if (snap.hasError) {
          body = Padding(
            padding: const EdgeInsets.all(AppTheme.hankoGutter),
            child: Text(snap.error.toString(),
                style: AppTheme.hankoSans(color: AppTheme.hankoStone)),
          );
        } else if (!snap.hasData) {
          body = const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.hankoStone),
              ),
            ),
          );
        } else if (snap.data!.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.all(AppTheme.hankoGutter),
            child: Text(
                'Your list is empty. Add a show from its page, then start '
                'an arc for it.',
                style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.5)),
          );
        } else {
          final entries = snap.data!;
          body = Flexible(
            child: LayoutBuilder(builder: (context, box) {
              const gap = 12.0;
              final cols = box.maxWidth >= 560 ? 5 : 3;
              final w = (box.maxWidth - AppTheme.hankoGutter * 2 - gap * (cols - 1)) / cols;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, 0, AppTheme.hankoGutter, 20),
                child: Wrap(
                  spacing: gap,
                  runSpacing: 16,
                  children: [
                    for (final e in entries)
                      SizedBox(
                        width: w,
                        child: _ShowPick(
                          entry: e,
                          width: w,
                          onTap: () => setState(() => _choose(e.show, e.progress)),
                        ),
                      ),
                  ],
                ),
              );
            }),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [head, body],
        );
      },
    );
  }

  // Step 2: the range, pace, first day and name.
  Widget _settings() {
    final show = _show!;
    final preview = _preview;
    final last = preview.endsOn.subtract(const Duration(days: 1));
    final stops = preview.stopCount;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 20, AppTheme.hankoGutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HankoPrint(url: show.cover, width: 48, height: 68),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start an arc',
                        style: AppTheme.hankoSerif(fontSize: 20, height: 1.3)),
                    const SizedBox(height: 2),
                    Text(show.title,
                        style: AppTheme.hankoSans(
                            color: AppTheme.hankoStone, height: 1.35)),
                    if (_progress > 0)
                      Text('You\'re on episode $_progress',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              color: AppTheme.hankoStone,
                              height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _label('EPISODES'),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Stepper(
                label: 'From episode',
                value: _from,
                min: 1,
                max: _to,
                onChanged: (v) => setState(() {
                  _from = v;
                  _setName();
                }),
              ),
              Text('to', style: AppTheme.hankoSans(color: AppTheme.hankoStone)),
              _Stepper(
                label: 'To episode',
                value: _to,
                min: _from,
                max: _max,
                onChanged: (v) => setState(() {
                  _to = v;
                  _setName();
                }),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _label('EPISODES A WEEK'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _paces)
                HankoChip(
                  label: '$p',
                  semanticLabel: '$p episode${p == 1 ? '' : 's'} a week',
                  on: _pace == p,
                  onTap: () => setState(() => _pace = p),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _label('STARTS'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                HankoChip(
                  label: [
                    'Today',
                    'Saturday',
                    'In a week'
                  ][i],
                  semanticLabel: 'Starts ${_day.format(_startDay(i))}',
                  on: _start == i,
                  onTap: () => setState(() => _start = i),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              '$stops stop${stops == 1 ? '' : 's'}, from '
              '${_day.format(_startDay(_start))} to ${_day.format(last)}',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500,
                  height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          ArcStopStrip(stops: stops, current: -1),
          const SizedBox(height: 20),
          _label('NAME'),
          TextField(
            controller: _name,
            maxLength: ArcLimits.name,
            cursorColor: AppTheme.hankoWashi,
            style: AppTheme.hankoSans(height: 1.35),
            decoration: _field('What the arc is called'),
            onChanged: (_) => _nameTouched = true,
          ),
          const SizedBox(height: 8),
          _label('ABOUT (OPTIONAL)'),
          TextField(
            controller: _about,
            minLines: 2,
            maxLines: 4,
            maxLength: ArcLimits.about,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: AppTheme.hankoWashi,
            style: AppTheme.hankoSans(height: 1.45),
            decoration: _field('A first rewatch, dub only, anyone welcome…'),
          ),
          const SizedBox(height: 12),
          ArcAction(
            label: 'Start the arc',
            expand: true,
            busy: _creating,
            busyLabel: 'Starting…',
            onTap: _name.text.trim().isEmpty ? null : _create,
          ),
          _refusal(_refused),
          if (widget.show == null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _show = null;
                  _nameTouched = false;
                }),
                child: Text('Pick another show',
                    style: AppTheme.hankoSans(
                        weight: FontWeight.w500, color: AppTheme.hankoStone)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A show to pick: its print and title. One button for a screen reader.
class _ShowPick extends StatelessWidget {
  const _ShowPick({required this.entry, required this.width, required this.onTap});

  final ArcListEntry entry;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: entry.show.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HankoPrint(
                  url: entry.show.cover, width: width, height: width * 1.42),
              const SizedBox(height: 6),
              Text(entry.show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}
