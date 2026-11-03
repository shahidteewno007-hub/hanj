// Tier lists: the picture people post.
//
// The poster is drawn at one fixed width (360, exported at 3x: 1080 px wide)
// and grows as tall as the list, so a long list stays readable. Like the
// card share image (card_share.dart), the reader's text size stays out of
// it, and the preview on screen is exactly what gets saved.
//
// Saving: on a phone, Save puts it in the gallery (album "Hanj") and Share
// opens the share sheet; on the web, Download saves a PNG and Share uses the
// browser's share sheet, downloading instead where there is none. Every face
// is loaded before the buttons wake, so a capture never catches a blank.
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import 'tier_list_model.dart';
import 'tier_list_widgets.dart';

class TierListExportScreen extends StatefulWidget {
  const TierListExportScreen({super.key, required this.list});
  final TierList list;

  @override
  State<TierListExportScreen> createState() => _TierListExportScreenState();
}

class _TierListExportScreenState extends State<TierListExportScreen> {
  final _boundary = GlobalKey();
  bool _names = true;
  bool _ready = false;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _prepare();
    }
  }

  /// Loads every picture the poster shows, for up to 15 seconds; a face that
  /// won't load is drawn as its initials.
  Future<void> _prepare() async {
    final urls = <String>{
      for (final t in widget.list.tiers)
        for (final id in t.characterIds)
          if (widget.list.characters[id]?.imageUrl case final String u) u,
      for (final c in TierListPoster.coversOf(widget.list)) c,
    };
    await Future.wait([
      precacheImage(const AssetImage(TierListPoster.wing), context, onError: (_, _) {}),
      for (final u in urls)
        precacheImage(CachedNetworkImageProvider(u), context, onError: (_, _) {}),
    ]).timeout(const Duration(seconds: 15), onTimeout: () => const <void>[]);
    if (mounted) setState(() => _ready = true);
  }

  String get _fileName {
    final slug = widget.list.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'hanj-${slug.isEmpty ? 'tier-list' : slug}.png';
  }

  Future<Uint8List?> _capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final box = _boundary.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    final image = await box.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _run(Future<String?> Function(Uint8List png) job) async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final png = await _capture();
      if (png == null) {
        _toast('Couldn’t make the image. Try again.');
        return;
      }
      final message = await job(png);
      if (message != null) _toast(message);
    } catch (e) {
      debugPrint('Tier list export failed: $e');
      _toast('Couldn’t save it. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run((png) async {
        if (kIsWeb) {
          await XFile.fromData(png, mimeType: 'image/png', name: _fileName).saveTo(_fileName);
          return 'Downloaded $_fileName';
        }
        try {
          await Gal.putImageBytes(png, album: 'Hanj', name: _fileName.replaceAll('.png', ''));
          return 'Saved to your gallery';
        } on GalException catch (e) {
          debugPrint('Gallery save failed: ${e.type}');
          return e.type == GalExceptionType.accessDenied
              ? 'Hanj needs permission to save to your gallery'
              : 'Couldn’t save it. Try again.';
        }
      });

  // On the web, a browser with no share sheet gets a download instead
  // (share_plus's fallback), so there is nothing further to say either way.
  Future<void> _share() => _run((png) async {
        await Share.shareXFiles(
          [XFile.fromData(png, mimeType: 'image/png', name: _fileName)],
          text: 'My “${widget.list.title}” tier list, made on Hanj',
          fileNameOverrides: [_fileName],
        );
        return null;
      });

  void _toast(String message) {
    if (mounted) tierToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
                    child: Semantics(
                      header: true,
                      child: Text('Share your tier list', style: AppTheme.hankoSerif(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: wide ? 480 : double.infinity),
                    child: Semantics(
                      image: true,
                      label: 'Preview of the image: ${TierListPoster.describe(widget.list)}',
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
                          ),
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            child: RepaintBoundary(
                              key: _boundary,
                              child: MediaQuery.withNoTextScaling(
                                child: TierListPoster(list: widget.list, showNames: _names),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.hankoSumi2,
                border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MergeSemantics(
                        child: SwitchListTile(
                          value: _names,
                          onChanged: (v) => setState(() => _names = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: AppTheme.hankoSumi,
                          activeTrackColor: AppTheme.hankoWashi,
                          inactiveThumbColor: AppTheme.hankoStone,
                          inactiveTrackColor: AppTheme.hankoSumi3,
                          title: Text('Names under faces', style: AppTheme.hankoSans(fontSize: 15)),
                        ),
                      ),
                      if (!_ready)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Loading the faces…',
                              style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone)),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TierGhostButton(
                              label: kIsWeb ? 'Download' : 'Save',
                              icon: Icons.download_rounded,
                              onTap: _ready && !_busy ? _save : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TierMainButton(
                              label: 'Share',
                              icon: Icons.ios_share_rounded,
                              busy: _busy,
                              onTap: _ready ? _share : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The exported image. Drawn at [width] wide and as tall as the list needs.
class TierListPoster extends StatelessWidget {
  const TierListPoster({super.key, required this.list, this.showNames = true, this.date});

  final TierList list;
  final bool showNames;

  /// The date printed in the corner; the list's last edit when null.
  final DateTime? date;

  static const double width = 360;
  static const double _pad = 18;
  static const wing = 'assets/images/hanj_wing_transparent.png';

  /// The anime covers along the top: most-used first, at most six.
  static List<String> coversOf(TierList list) => [
        for (final m in list.mediaByUse())
          if (list.sampleOf(m.key)?.mediaCover case final String c) c,
      ].take(6).toList();

  /// What a screen reader says the picture is.
  static String describe(TierList list) {
    final parts = <String>[list.title];
    for (final t in list.tiers) {
      final names = [for (final id in t.characterIds) list.characters[id]?.name ?? ''];
      final label = t.label.trim().isEmpty ? 'Unnamed tier' : t.label;
      parts.add(names.isEmpty ? '$label: nobody' : '$label: ${names.join(', ')}');
    }
    return parts.join('. ');
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final ranked = list.rankedCount;
    final perRow = ranked > 48 ? 5 : 4;
    final plateW = tierPlateWidth(
      context,
      [for (final t in list.tiers) t.label],
      base: 16,
      min: 66,
      max: 104,
    );
    const gap = 5.0;
    final inner = width - _pad * 2 - plateW - 10;
    final faceW = ((inner - (perRow - 1) * gap) / perRow).floorToDouble();
    final anime = list.mediaByUse();
    final covers = coversOf(list);
    final top = anime.isEmpty ? null : list.sampleOf(anime.first.key)?.mediaColor;
    final wash = top == null ? null : AppTheme.hankoCoverTint(Color(top));
    final d = date ?? list.updatedAt;
    final bits = <String>[
      'Tier list',
      ranked == 1 ? '1 ranked' : '$ranked ranked',
      if (anime.isNotEmpty) anime.length == 1 ? '1 anime' : '${anime.length} anime',
    ];

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
              height: 260,
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
                  bits.join('  ·  ').toUpperCase(),
                  style: AppTheme.hankoSans(
                    fontSize: 9.5,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoStoneHi,
                    letterSpacing: 2,
                    tabular: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  list.title,
                  maxLines: 3,
                  overflow: TextOverflow.fade,
                  style: AppTheme.hankoSerif(fontSize: 28, height: 1.15),
                ),
                if (list.prompt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    list.prompt,
                    maxLines: 3,
                    style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStoneHi, height: 1.35),
                  ),
                ],
                if (covers.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final c in covers)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 22,
                            height: 33,
                            child: CachedNetworkImage(
                              imageUrl: c,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, _) => const ColoredBox(color: AppTheme.hankoSumi3),
                              errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.hankoSumi3),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _fromLine(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.hankoSans(fontSize: 10.5, color: AppTheme.hankoStone, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                for (final t in list.tiers) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TierPlate(
                          label: t.label,
                          pigment: TierPigment.at(t.pigment),
                          width: plateW,
                          minHeight: faceW * 1.5 + (showNames ? 28 : 10),
                          fontSize: 16,
                        ),
                        Expanded(
                          child: Container(
                            color: AppTheme.hankoSumi2,
                            padding: const EdgeInsets.all(5),
                            child: Wrap(
                              spacing: gap,
                              runSpacing: 6,
                              children: [
                                for (final id in t.characterIds)
                                  if (list.characters[id] case final TierCharacter c)
                                    CharacterPortrait(
                                      character: c,
                                      width: faceW,
                                      showName: showNames,
                                      nameLines: 2,
                                      nameSize: 8.5,
                                      exportMode: true,
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Image.asset(wing, width: 18, height: 18, fit: BoxFit.contain),
                    const SizedBox(width: 7),
                    Text('Hanj', style: AppTheme.hankoSerif(fontSize: 19, height: 1, letterSpacing: 0.2)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'TIER LISTS',
                        style: AppTheme.hankoSans(
                          fontSize: 8.5,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoStone,
                          letterSpacing: 2,
                          tabular: true,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${d.day} ${_months[d.month - 1]} ${d.year}',
                        style: AppTheme.hankoSans(fontSize: 10, color: AppTheme.hankoStone, tabular: true),
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

  String _fromLine() {
    final anime = list.mediaByUse();
    final names = [
      for (final m in anime)
        if (list.sampleOf(m.key)?.mediaTitle case final String t) t,
    ];
    if (names.isEmpty) return '';
    if (names.length == 1) return 'From ${names.first}';
    if (names.length == 2) return 'From ${names[0]} and ${names[1]}';
    final rest = names.length - 2;
    return 'From ${names[0]}, ${names[1]} and $rest more';
  }
}
