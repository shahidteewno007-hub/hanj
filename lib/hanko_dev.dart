import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'widgets/hanko_reel.dart';
import 'widgets/hanko_seal.dart';
import 'widgets/hanko_title_slip.dart';

/// Dev-only entry point: a specimen of Hanko's foundation, the tokens in
/// `AppTheme` and the three shared widgets, on Hanko's sumi background.
///
/// Run with:  flutter run -t lib/hanko_dev.dart
///
/// Nothing in the app imports this file, by design, like `cadre_dev.dart`.
/// It starts no Firebase and loads no network images: prints and posters are
/// flat cover colours, so it doesn't depend on AniList. Titles, native titles,
/// episode counts and cover colours are real AniList data, from
/// `design/mockups/looks/data/anilist.json` in the designer worktree. Watched
/// counts and ratings are illustrative, as in the spec's frames. Compare it
/// with `design/mockups/looks/hanko.html`.
///
/// It does load fonts: Jost and Shippori Mincho through `google_fonts`, and,
/// on web, the engine's own CJK fallback for native titles.
void main() {
  runApp(const HankoDevApp());
}

class HankoDevApp extends StatelessWidget {
  const HankoDevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanko specimen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppTheme.hankoSumi,
        colorScheme: const ColorScheme.dark(
          surface: AppTheme.hankoSumi,
          primary: AppTheme.hankoWashi,
          onSurface: AppTheme.hankoWashi,
        ),
      ),
      home: const _Specimen(),
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 64),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hanko specimen',
                        style: AppTheme.hankoSerif(fontSize: AppTheme.hankoDisplaySize)),
                    const SizedBox(height: 6),
                    Text(
                      'Dev only: lib/hanko_dev.dart. The tokens and the seal, reel '
                      'and title slip from hanko.html, drawn on sumi. No Firebase '
                      'and no network images; prints and posters are flat cover '
                      'colours. Watched counts and ratings are illustrative.',
                      style: _note,
                    ),
                    const _Section(title: 'Palette', child: _Palette()),
                    const _Section(
                      title: 'Cover tint',
                      note: 'coverImage.color at 20% over sumi, behind the print. '
                          'Neutral sumi when the cover’s hue is within 25° of the seal’s.',
                      child: _Tints(),
                    ),
                    const _Section(title: 'Type', child: _Type()),
                    const _Section(
                      title: 'Seal',
                      note: 'Filled is yours, outlined is someone else’s, dashed is '
                          'not rated yet. Your seal keeps a 2 px sumi keyline. '
                          'Coral by default, shu as the option.',
                      child: _Seals(),
                    ),
                    const _Section(
                      title: 'Reel',
                      note: 'One tick per episode: solid watched, outlined aired and '
                          'waiting, short not aired. Past 30 episodes, or when ticks '
                          'don’t fit, it becomes a line. An unknown total ends in an '
                          'open tail.',
                      child: _Reels(),
                    ),
                    const _Section(
                      title: 'Title slip',
                      note: 'Detail’s hero at true size: a 208 by 293 print (a flat '
                          'cover colour here), the native title on its slip, your '
                          'seal across the print’s edge.',
                      child: _Slips(),
                    ),
                    const _Section(
                      title: 'More native titles',
                      note: 'Real AniList native titles, each on a 150 by 293 print '
                          'with the slip 10 px from its corner.',
                      child: _SlipGallery(),
                    ),
                    const _Section(
                      title: 'At 1.5× text size',
                      note: 'Seal numerals grow until they fill the square, then '
                          'stop. The slip grows with the text, up to 1.5×.',
                      child: _LargeText(),
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
}

final _note = AppTheme.hankoSans(
    fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone, height: 1.45);
final _cap = AppTheme.hankoSans(
    fontSize: AppTheme.hankoDataSmallSize, color: AppTheme.hankoAsh, height: 1.3);

class _Section extends StatelessWidget {
  const _Section({required this.title, this.note, required this.child});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, thickness: 1, color: AppTheme.hankoHairline),
          const SizedBox(height: 22),
          Text(title, style: AppTheme.hankoSerif()),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: _note),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ── Palette ─────────────────────────────────────────────────────────────

class _Palette extends StatelessWidget {
  const _Palette();

  static const _swatches = <(String, Color, String)>[
    ('Sumi', AppTheme.hankoSumi, 'Background'),
    ('Sumi 2', AppTheme.hankoSumi2, 'Sheets, fields, nav'),
    ('Sumi 3', AppTheme.hankoSumi3, 'Tiles, chips'),
    ('Washi', AppTheme.hankoWashi, 'Text, the main action'),
    ('Stone', AppTheme.hankoStone, 'Secondary text'),
    ('Stone hi', AppTheme.hankoStoneHi, 'Text on a cover tint'),
    ('Ash', AppTheme.hankoAsh, 'Tertiary, placeholders'),
    ('Coral', AppTheme.hankoCoral, 'Your seal (default)'),
    ('Shu', AppTheme.hankoShu, 'Your seal (option)'),
    ('Ai', AppTheme.hankoAi, 'The crowd’s numbers'),
    ('Ai deep', AppTheme.hankoAiDeep, 'The crowd’s chart marks'),
    ('Edge', AppTheme.hankoEdge, 'Borders, outlines'),
    ('Hairline', AppTheme.hankoHairline, 'The one rule'),
    ('Press', AppTheme.hankoPressWash, 'Washi at 8%'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 14,
      children: [
        for (final (name, color, role) in _swatches)
          SizedBox(
            width: 160,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                    border: Border.all(color: AppTheme.hankoWashi.withValues(alpha: 0.12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w500)),
                      Text(_hex(color),
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              color: AppTheme.hankoStone,
                              tabular: true)),
                      Text(role, style: _cap, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _hex(Color c) {
    final rgb = (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    final alpha = (c.a * 100).round();
    return alpha == 100 ? '#$rgb' : '#$rgb $alpha%';
  }
}

class _Tints extends StatelessWidget {
  const _Tints();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 14,
      children: [
        _tint('Frieren', const Color(0xFFBBF1A1)),
        _tint('MUSHI-SHI', const Color(0xFFD6BB78)),
        _tint('Perfect Blue', const Color(0xFF1A356B)),
        _tint('DAN DA DAN', const Color(0xFFE47850)),
        _tint('Cowboy Bebop', const Color(0xFFF16B50)),
      ],
    );
  }

  Widget _tint(String show, Color cover) {
    final tint = AppTheme.hankoCoverTint(cover);
    return SizedBox(
      width: 128,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: tint == null ? AppTheme.hankoSumi : Color.alphaBlend(tint, AppTheme.hankoSumi),
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              border: Border.all(color: AppTheme.hankoHairline),
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(8),
            child: Container(width: 14, height: 14, color: cover),
          ),
          const SizedBox(height: 6),
          Text(show, style: AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, weight: FontWeight.w500)),
          Text(tint == null ? 'neutral: close to the seal' : 'tinted', style: _cap),
        ],
      ),
    );
  }
}

// ── Type ────────────────────────────────────────────────────────────────

class _Type extends StatelessWidget {
  const _Type();

  @override
  Widget build(BuildContext context) {
    const lede = AppTheme.hankoLedeSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('Display 24, Mincho',
            Text('Frieren: Beyond Journey’s End',
                style: AppTheme.hankoSerif(fontSize: AppTheme.hankoDisplaySize, height: 1.18))),
        _row(
          'Lede 22, Mincho, with an inline seal',
          Text.rich(
            TextSpan(
              text: 'Last night you finished DAN DA DAN, all twelve episodes, and sealed it',
              children: [
                const WidgetSpan(child: SizedBox(width: lede * 0.4 * 0.64)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  // The spec's inline seal: 2.3 by 2 em at 0.64 of the lede.
                  child: HankoSeal.score(8.5,
                      size: lede * 0.64 * 2, width: lede * 0.64 * 2.3, fontSize: lede * 0.64),
                ),
              ],
            ),
            style: AppTheme.hankoSerif(fontSize: lede, height: 1.32),
          ),
        ),
        _row('Featured 19 / section 16 / list title 15, Mincho',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MUSHI-SHI', style: AppTheme.hankoSerif(fontSize: AppTheme.hankoFeaturedSize)),
                Text('From your watchlist tonight', style: AppTheme.hankoSerif()),
                Text('The Apothecary Diaries Season 3',
                    style: AppTheme.hankoSerif(fontSize: AppTheme.hankoListTitleSize)),
              ],
            )),
        _row('Native 17 / 13: the phone’s own Japanese font, locale ja',
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text('葬送のフリーレン', style: AppTheme.hankoNative(color: AppTheme.hankoWashi)),
                Text('目覚めたら最強装備と宇宙船持ちだったので',
                    style: AppTheme.hankoNative(
                        fontSize: AppTheme.hankoNativeLongSize, color: AppTheme.hankoWashi)),
              ],
            )),
        _row('Body 14, Jost 400',
            Text(
              'The adventure is over but life goes on for an elf mage just beginning '
              'to learn what living is all about.',
              style: AppTheme.hankoSans(height: 1.55),
            )),
        _row('Meta 13 and label 12, Jost 400–500',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TV, Fall 2023. 28 episodes, 24 min each.',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone)),
                const SizedBox(height: 4),
                Text('Your rating',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        weight: FontWeight.w500,
                        color: AppTheme.hankoStone)),
              ],
            )),
        _row('Data 11–14, Jost 500: tabular in columns, proportional alone',
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final n in ['11 of 12', '7 of 28', '108 of 220'])
                      Text(n,
                          style: AppTheme.hankoSans(
                              fontSize: 14, weight: FontWeight.w500, tabular: true)),
                  ],
                ),
                const SizedBox(width: 28),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final n in ['11 of 12', '7 of 28', '108 of 220'])
                      Text(n, style: AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(width: 28),
                Text('AniList 91',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        weight: FontWeight.w500,
                        color: AppTheme.hankoAi)),
              ],
            )),
      ],
    );
  }

  Widget _row(String label, Widget sample) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _cap),
          const SizedBox(height: 6),
          sample,
        ],
      ),
    );
  }
}

// ── Seal ────────────────────────────────────────────────────────────────

class _Seals extends StatelessWidget {
  const _Seals();

  static const _sizes = <double>[24, 28, 40, 56];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line('Yours, coral (default)', [
          for (final s in _sizes) _fig(HankoSeal.score(8.5, size: s), '${s.round()}'),
          _fig(HankoSeal.score(10, size: 24), '10.0 at 24'),
        ]),
        _line('Yours, shu (option)', [
          for (final s in _sizes)
            _fig(HankoSeal.score(8.5, size: s, tone: HankoSealTone.shu), '${s.round()}'),
        ]),
        _line('Someone else’s', [
          for (final s in _sizes)
            _fig(HankoSeal.score(9, size: s, kind: HankoSealKind.theirs), '${s.round()}'),
        ]),
        _line('Not rated yet', [
          for (final s in _sizes) _fig(HankoSeal.unrated(size: s), '${s.round()}'),
          _fig(const HankoSeal.unrated(showAdd: false), 'no plus'),
        ]),
        _line('On a sheet, on a tile, across a poster’s edge', [
          _fig(_on(AppTheme.hankoSumi2, HankoSeal.score(8)), 'sumi 2'),
          _fig(_on(AppTheme.hankoSumi3, HankoSeal.score(8)), 'sumi 3'),
          _fig(_on(AppTheme.hankoSumi3, HankoSeal.score(8, tone: HankoSealTone.shu)), 'shu on sumi 3'),
          _fig(
            SizedBox(
              width: 54,
              height: 74,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _poster(const Color(0xFFE47850), 48, 68),
                  Positioned(right: 0, bottom: 0, child: HankoSeal.score(8.5, size: 24)),
                ],
              ),
            ),
            'DAN DA DAN',
          ),
        ]),
      ],
    );
  }

  Widget _on(Color surface, Widget seal) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        ),
        child: seal,
      );

  Widget _line(String label, List<Widget> figs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  weight: FontWeight.w500,
                  color: AppTheme.hankoStone)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: figs,
          ),
        ],
      ),
    );
  }

  Widget _fig(Widget child, String caption) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: 8),
          Text(caption, style: _cap),
        ],
      );
}

Widget _poster(Color color, double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      ),
    );

// ── Reel ────────────────────────────────────────────────────────────────

class _Reels extends StatelessWidget {
  const _Reels();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('The Apothecary Diaries Season 3', '3 of 12',
            const HankoReel(watched: 3, total: 12, aired: 4),
            'Episode 4 has aired and is waiting; 5 airs next.'),
        _row('Frieren: Beyond Journey’s End', '7 of 28',
            const HankoReel(watched: 7, total: 28), 'All 28 have aired.'),
        _row('Fullmetal Alchemist: Brotherhood', '45 of 64',
            const HankoReel(watched: 45, total: 64), '64 episodes: a line.'),
        _row('Fullmetal Alchemist: Brotherhood', '63 of 64',
            const HankoReel(watched: 63, total: 64), 'One waiting still shows.'),
        _row('Black Clover Season 2', '2 watched',
            const HankoReel(watched: 2, aired: 4),
            'Episode count not announced; 4 have aired.'),
        _row('Firefly Wedding', '0 of 12',
            const HankoReel(watched: 0, total: 12, aired: 3), 'Three aired, none watched.'),
        _row('A long-running show (illustrative)', '100 watched',
            const HankoReel(watched: 100, aired: 120),
            'Unknown total past 30: a line with an open tail.'),
        _row('Frieren, in 100 px', '7 of 28',
            const SizedBox(width: 100, child: HankoReel(watched: 7, total: 28)),
            'Too narrow for 28 ticks, so a line.'),
      ],
    );
  }

  Widget _row(String title, String count, Widget reel, String note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.hankoSerif(fontSize: AppTheme.hankoListTitleSize, height: 1.25)),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(count,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      weight: FontWeight.w500,
                      color: AppTheme.hankoStone,
                      height: 1,
                      tabular: true)),
              const SizedBox(width: 10),
              reel,
            ],
          ),
          const SizedBox(height: 5),
          Text(note, style: _cap),
        ],
      ),
    );
  }
}

// ── Title slip ──────────────────────────────────────────────────────────

class _Slips extends StatelessWidget {
  const _Slips();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 20,
      children: [
        _Hero(
          label: 'Frieren: Beyond Journey’s End. 8 characters at 17 px; '
              'ー turns.',
          cover: const Color(0xFFBBF1A1),
          nativeTitle: '葬送のフリーレン',
          seal: HankoSeal.score(8.5, size: 56),
          caption: 'Yours\n3 Oct',
        ),
        const _Hero(
          label: 'Reborn as a Space Mercenary. 41 characters: 13 px in '
              'columns; 、 takes its vertical form.',
          cover: Color(0xFFD6BB78),
          nativeTitle: '目覚めたら最強装備と宇宙船持ちだったので、一戸建て目指して傭兵として自由に生きたい',
          seal: HankoSeal.unrated(size: 56),
          caption: 'Not rated\nyet',
        ),
        _Hero(
          label: 'Perfect Blue. Its native title is Latin (PERFECT BLUE), '
              'so no slip.',
          cover: const Color(0xFF1A356B),
          nativeTitle: 'PERFECT BLUE',
          seal: HankoSeal.score(9.5, size: 56),
          caption: 'Yours\n28 Sep',
        ),
      ],
    );
  }
}

/// The spec's Detail hero geometry (frame 2): print at 0,0, slip at 10,10,
/// seal at 180,225 and its caption at 246,239, on a cover tint.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.label,
    required this.cover,
    required this.nativeTitle,
    required this.seal,
    required this.caption,
  });

  final String label;
  final Color cover;
  final String nativeTitle;
  final Widget seal;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final tint = AppTheme.hankoCoverTint(cover);
    return SizedBox(
      width: 320,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Container(
              width: 320,
              height: 333,
              decoration: BoxDecoration(
                color: AppTheme.hankoSumi,
                gradient: tint == null
                    ? null
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.62, 1],
                        colors: [
                          Color.alphaBlend(tint, AppTheme.hankoSumi),
                          Color.alphaBlend(tint, AppTheme.hankoSumi),
                          AppTheme.hankoSumi,
                        ],
                      ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 20,
                    child: Container(
                      width: 208,
                      height: 293,
                      decoration: BoxDecoration(
                        color: cover,
                        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.hankoWashi.withValues(alpha: 0.12),
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(left: 10, top: 30, child: HankoTitleSlip(nativeTitle: nativeTitle)),
                  Positioned(left: 180, top: 245, child: seal),
                  Positioned(
                    left: 246,
                    top: 259,
                    child: Text(caption,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoDataSmallSize,
                            color: AppTheme.hankoStoneHi,
                            height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: _cap),
        ],
      ),
    );
  }
}

class _SlipGallery extends StatelessWidget {
  const _SlipGallery();

  static const _titles = <(String, String)>[
    ('HAIKYU!!', 'ハイキュー!!'),
    ('OSHI NO KO', '【推しの子】'),
    ('Your Name.', '君の名は。'),
    ('The Apothecary Diaries Season 3', '薬屋のひとりごと 第3期'),
    ('March comes in like a lion', '３月のライオン'),
    ('Mob Psycho 100', 'モブサイコ100'),
    ('Cyberpunk: Edgerunners 2', 'サイバーパンク: エッジランナーズ2'),
    ('Ghost in the Shell', 'GHOST IN THE SHELL / 攻殻機動隊'),
    ('Kaguya-sama: Love is War', 'かぐや様は告らせたい～天才たちの恋愛頭脳戦～'),
    ('SPY x FAMILY', 'SPY×FAMILY'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 20,
      children: [
        for (final (english, native) in _titles)
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  height: 293,
                  child: Stack(
                    children: [
                      Positioned.fill(child: _poster(AppTheme.hankoSumi3, 150, 293)),
                      Positioned(
                        left: 10,
                        top: 10,
                        child: HankoTitleSlip(nativeTitle: native, maxWidth: 130),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  HankoTitleSlip.shows(native) ? english : '$english: Latin only, no slip',
                  style: _cap,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LargeText extends StatelessWidget {
  const _LargeText();

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)),
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          HankoSeal.score(10, size: 24),
          HankoSeal.score(8.5),
          HankoSeal.score(8.5, size: 56),
          SizedBox(
            width: 150,
            height: 293,
            child: Stack(
              children: [
                Positioned.fill(child: _poster(const Color(0xFFBBF1A1), 150, 293)),
                const Positioned(
                  left: 10,
                  top: 10,
                  child: HankoTitleSlip(nativeTitle: '葬送のフリーレン', maxWidth: 130),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
