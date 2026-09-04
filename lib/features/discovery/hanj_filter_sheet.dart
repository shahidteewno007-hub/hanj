import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

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
  static const _formats = ['TV', 'Movie', 'ONA', 'OVA', 'Special'];
  final _currentYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _genre = widget.genre;
    _format = widget.format;
    _year = widget.year;
  }

  @override
  Widget build(BuildContext context) {
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
                      label: f,
                      selected: _format == f,
                      onTap: () => setState(() => _format = _format == f ? null : f),
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
                        style: AppTheme.sans(fontSize: 14, color: Colors.white, weight: FontWeight.w600)),
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
            color: selected ? Colors.white : AppTheme.textSecondary,
            weight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
