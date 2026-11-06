import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hanko_cover_colour.dart';

/// A field of a show's own colour behind its art (Print Room, DESIGN.md §9).
///
/// Where the colour comes from:
/// - [colour] is the show's colour: AniList's `coverImage.color`, where the
///   screen has it;
/// - without it, [coverUrl] lends its own, read from the cover by
///   [HankoCoverColour], fading in once it's ready.
///
/// The field is [AppTheme.hankoField] of that colour. It's solid down to
/// [solidTo] of its height, then fades to nothing at its bottom, so the
/// page's sumi takes over by the next block. [glow] adds a pool of lighter
/// colour ([AppTheme.hankoFieldGlowCap]) centred there, [glowRadius] of the
/// field's shorter side across: put it behind a print, where no text sits.
///
/// With no colour, or a grey cover, the field is clear and the page's sumi
/// shows, as today. It's two gradients with no blur and no layer, so it's
/// cheap to paint (PERF.md S2-2). A colour arriving or changing crossfades in
/// 240 ms, or at once with Remove animations on.
class HankoField extends StatefulWidget {
  const HankoField({
    super.key,
    this.colour,
    this.coverUrl,
    this.solidTo = 0.7,
    this.glow,
    this.glowRadius = 0.6,
    required this.child,
  });

  /// The show's own colour. Wins over [coverUrl].
  final Color? colour;

  /// A cover to read the colour from when [colour] is null.
  final String? coverUrl;

  /// Where the fade begins, as a fraction of the field's height.
  final double solidTo;

  /// The centre of a pool of lighter colour behind a print. Null draws none.
  final Alignment? glow;

  /// The glow's radius, as a fraction of the field's shorter side.
  final double glowRadius;

  /// What the field sits behind. The field takes its size.
  final Widget child;

  @override
  State<HankoField> createState() => _HankoFieldState();
}

class _HankoFieldState extends State<HankoField> {
  // The colour read from coverUrl, when there's no colour.
  Color? _fromCover;

  @override
  void initState() {
    super.initState();
    _readCover();
  }

  @override
  void didUpdateWidget(HankoField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.colour != widget.colour) {
      _readCover();
    }
  }

  void _readCover() {
    final url = widget.coverUrl;
    if (widget.colour != null || url == null || url.isEmpty) {
      _fromCover = null;
      return;
    }
    if (HankoCoverColour.knows(url)) {
      _fromCover = HankoCoverColour.peek(url);
      return;
    }
    _fromCover = null;
    // HankoCoverColour never throws, so nothing here can reach Crashlytics.
    HankoCoverColour.ofUrl(url).then((colour) {
      if (!mounted || widget.coverUrl != url || widget.colour != null) return;
      setState(() => _fromCover = colour);
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.colour ?? _fromCover;
    final clear = AppTheme.hankoSumi.withValues(alpha: 0);
    final field = AppTheme.hankoField(base) ?? clear;
    final centre = widget.glow;
    final glow = centre == null
        ? null
        : AppTheme.hankoField(base,
            cap: AppTheme.hankoFieldGlowCap, mix: AppTheme.hankoFieldGlowMix);
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: still ? Duration.zero : const Duration(milliseconds: 240),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [field, field, field.withValues(alpha: 0)],
                stops: [0, widget.solidTo, 1],
              ),
            ),
            foregroundDecoration: centre == null || glow == null
                ? null
                : BoxDecoration(
                    gradient: RadialGradient(
                      center: centre,
                      radius: widget.glowRadius,
                      colors: [glow, glow.withValues(alpha: 0)],
                    ),
                  ),
          ),
        ),
        widget.child,
      ],
    );
  }
}
