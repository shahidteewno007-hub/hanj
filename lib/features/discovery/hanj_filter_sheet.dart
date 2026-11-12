import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/hanko_board.dart';

class HanjFilterSheet extends StatefulWidget {
  final String? genre;
  final String? format;
  final int? year;
  final void Function(String? genre, String? format, int? year) onApply;

  const HanjFilterSheet({
    super.key,
    this.genre, this.format, this.year, required this.onApply,
  });

  @override
  State<HanjFilterSheet> createState() => _HanjFilterSheetState();

  /// The sheet's label for a format value onApply returned ('MOVIE' →
  /// 'Movie'), for a caller's active-filter chip. Unknown values show as is.
  static String formatLabel(String value) => _HanjFilterSheetState._formats
      .firstWhere((f) => f.$1 == value, orElse: () => (value, value)).$2;
}

class _HanjFilterSheetState extends State<HanjFilterSheet> {
  late String? _genre;
  late String? _format;
  late int? _year;

  static const _genres = [
    'Action','Adventure','Comedy','Drama','Fantasy','Horror',
    'Mystery','Romance','Sci-Fi','Slice of Life','Sports',
    'Supernatural','Thriller','Mecha','Music','Psychological',
  ];
  // (value, label). The value is what onApply hands back, and both callers
  // pass it straight to AniList's MediaFormat variable, whose members are
  // upper case. Sending the labels made 'Movie' and 'Special' invalid.
  static const _formats = [
    ('TV', 'TV'),
    ('MOVIE', 'Movie'),
    ('ONA', 'ONA'),
    ('OVA', 'OVA'),
    ('SPECIAL', 'Special'),
  ];
  final _currentYear = DateTime.now().year;

  /// The sheet in Hanko (Print Room P8; the Vibes report's next small
  /// stage): sumi 2 with Hanko's sheet corners, the choices as printed tabs
  /// (the chosen one washi; CLAUDE.md: never coral, which is only ever your
  /// verdicts), and Apply as the washi main action. Each choice is one button
  /// for a screen reader and the keyboard. False gives back the coral pills
  /// and the coral Apply as they were.
  static const bool _printRoom = true;

  @override
  void initState() {
    super.initState();
    _genre = widget.genre;
    _format = widget.format;
    _year = widget.year;
  }

  @override
  Widget build(BuildContext context) {
    if (_printRoom) return _printed(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('Filter & Sort',
                      style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _genre = null; _format = null; _year = null;
                    }),
                    child: Text('Reset',
                        style: AppTheme.sans(color: AppTheme.textMuted, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _label('Genre'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _genres.map((g) => _FilterChip(
                      label: g,
                      selected: _genre == g,
                      onTap: () => setState(() => _genre = _genre == g ? null : g),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  _label('Format'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _formats.map((f) => _FilterChip(
                      label: f.$2,
                      selected: _format == f.$1,
                      onTap: () => setState(() => _format = _format == f.$1 ? null : f.$1),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  _label('Year'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(8, (i) {
                      final y = _currentYear - i;
                      return _FilterChip(
                        label: '$y',
                        selected: _year == y,
                        onTap: () => setState(() => _year = _year == y ? null : y),
                      );
                    }),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onApply(_genre, _format, _year);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Apply Filters',
                        // Sumi on coral, 5.64:1 (Hanko's rule; white was 3.35:1).
                        style: AppTheme.sans(fontSize: 14, color: AppTheme.textInverse, weight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _printed(BuildContext context) {
    // A choice is a printed tab; its 48 dp touch already holds 6 dp of air
    // above and below the drawn 36, so the rows need no run spacing.
    Widget choices(List<Widget> tabs) =>
        Wrap(spacing: 8, runSpacing: 0, children: tabs);
    Widget head(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(text,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: AppTheme.hankoStone)),
        );
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.hankoSumi2,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.hankoSheetRadius)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.hankoEdge,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Filter & Sort',
                        style: AppTheme.hankoSerif(
                            fontSize: AppTheme.hankoFeaturedSize)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _genre = null; _format = null; _year = null;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.hankoWashi,
                      minimumSize: const Size(AppTheme.hankoTouch, AppTheme.hankoTouch),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
                    ),
                    child: Text('Reset',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone)),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.hankoHairline, height: 1),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  head('Genre'),
                  choices([
                    for (final g in _genres)
                      HankoTab(
                        label: g,
                        selected: _genre == g,
                        onTap: () => setState(() => _genre = _genre == g ? null : g),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  head('Format'),
                  choices([
                    for (final f in _formats)
                      HankoTab(
                        label: f.$2,
                        selected: _format == f.$1,
                        onTap: () => setState(() => _format = _format == f.$1 ? null : f.$1),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  head('Year'),
                  choices([
                    for (var i = 0; i < 8; i++)
                      HankoTab(
                        label: '${_currentYear - i}',
                        selected: _year == _currentYear - i,
                        onTap: () => setState(() =>
                            _year = _year == _currentYear - i ? null : _currentYear - i),
                      ),
                  ]),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                // The washi main action, as Detail's (its own button node,
                // with the InkWell's tap and focus in it).
                child: Semantics(
                  container: true,
                  button: true,
                  child: Material(
                    color: AppTheme.hankoWashi,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onApply(_genre, _format, _year);
                      },
                      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minWidth: double.infinity, minHeight: AppTheme.hankoTouch),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('Apply filters',
                                style: AppTheme.hankoSans(
                                    fontSize: AppTheme.hankoBodySize,
                                    weight: FontWeight.w600,
                                    color: AppTheme.hankoSumi)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTheme.mono(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 13,
            // A chosen chip is sumi on coral, 5.64:1: Hanko's rule for
            // anything on coral, as on Apply Filters (white was 3.35:1).
            color: selected ? AppTheme.textInverse : AppTheme.textSecondary,
            weight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
