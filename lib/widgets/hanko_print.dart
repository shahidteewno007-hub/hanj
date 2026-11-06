import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// How far a [HankoPrint] lifts off the page.
enum HankoPrintLift {
  /// Flat on the page, with no shadow: on bare sumi a shadow can't show.
  none,

  /// A shelf print, a favourite, a poster in a strip.
  small,

  /// A screen's hero print.
  large,
}

/// A show's cover as a print lying on the page (Print Room, DESIGN.md §9).
///
/// It draws:
/// - the whole cover at [width] by [height], with Hanko's 2 px corners, on
///   [placeholder] (sumi 3) while it loads or when there's no art;
/// - one soft shadow, set by [lift];
/// - optionally a mat of the show's own colour around it, [mat],
///   [AppTheme.hankoMatPad] wide;
/// - optionally [seal], pressed across the corner [sealCorner] so that it
///   hangs [sealOverhang] past the print's edges, half on the art and half on
///   the page, as on Detail.
///
/// [sharp] is for a screen's hero print. Home's covers are AniList's 230 px
/// `large`: crisp to about 58 dp and acceptable to about 115 dp on a 4x screen
/// (DESIGN.md §6d). So a hero asks AniList's image server for its 460 px cover by
/// the server's naming (`/cover/medium/` becomes `/cover/large/`), and shows
/// the stored cover until that arrives, or for good if it fails. The naming
/// is the AniList image server's, not a documented API, hence the fallback.
///
/// The print is decorative and adds nothing to the semantics tree. The screen
/// names the show in its own node, as Hanko's rows do.
class HankoPrint extends StatelessWidget {
  const HankoPrint({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.lift = HankoPrintLift.small,
    this.mat,
    this.seal,
    this.sealCorner = Alignment.bottomRight,
    this.sealOverhang = const Offset(8, 8),
    this.sharp = false,
    this.placeholder = AppTheme.hankoSumi3,
  });

  /// The stored cover URL. Null or empty shows [placeholder] alone.
  final String? url;
  final double width;
  final double height;
  final HankoPrintLift lift;

  /// The mat's colour, usually `AppTheme.hankoField` of the show's colour.
  /// Null draws no mat.
  final Color? mat;

  /// Usually a [HankoSeal]. It isn't clipped, so it can hang past the edge.
  final Widget? seal;

  /// Which corner the seal is pressed across. Only the signs of x and y
  /// count: left or right, top or bottom.
  final Alignment sealCorner;

  /// How far the seal hangs past the print's edges, across and down.
  final Offset sealOverhang;

  /// Ask for the 460 px cover (heroes only).
  final bool sharp;

  /// Shown while the cover loads, and when there is none.
  final Color placeholder;

  /// The 460 px cover for [url], by the AniList image server's naming. When [url]
  /// isn't one of AniList's 230 px covers (a MyAnimeList import, for one),
  /// it comes back unchanged.
  static String? sharpUrl(String? url) {
    if (url == null) return null;
    const stored = '/media/anime/cover/medium/';
    const sharper = '/media/anime/cover/large/';
    return url.contains(stored) ? url.replaceFirst(stored, sharper) : url;
  }

  @override
  Widget build(BuildContext context) {
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    final shadow = switch (lift) {
      HankoPrintLift.none => const <BoxShadow>[],
      HankoPrintLift.small => AppTheme.hankoPrintShadow,
      HankoPrintLift.large => AppTheme.hankoPrintShadowLarge,
    };
    Widget body = SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: placeholder,
          borderRadius: corners,
          boxShadow: shadow,
        ),
        child: ClipRRect(borderRadius: corners, child: _art()),
      ),
    );
    final seal = this.seal;
    if (seal != null) {
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            left: sealCorner.x < 0 ? -sealOverhang.dx : null,
            right: sealCorner.x < 0 ? null : -sealOverhang.dx,
            top: sealCorner.y < 0 ? -sealOverhang.dy : null,
            bottom: sealCorner.y < 0 ? null : -sealOverhang.dy,
            child: seal,
          ),
        ],
      );
    }
    final mat = this.mat;
    if (mat != null) {
      body = DecoratedBox(
        decoration: BoxDecoration(color: mat, borderRadius: corners),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.hankoMatPad),
          child: body,
        ),
      );
    }
    return ExcludeSemantics(child: body);
  }

  Widget _art() {
    final stored = url;
    if (stored == null || stored.isEmpty) return const SizedBox.expand();
    Widget storedCover() => CachedNetworkImage(
          imageUrl: stored,
          fit: BoxFit.cover,
          width: width,
          height: height,
          errorWidget: (_, _, _) => const SizedBox.expand(),
        );
    final hero = sharp ? sharpUrl(stored) : stored;
    if (hero == null || hero == stored) return storedCover();
    return CachedNetworkImage(
      imageUrl: hero,
      fit: BoxFit.cover,
      width: width,
      height: height,
      placeholder: (_, _) => storedCover(),
      errorWidget: (_, _, _) => storedCover(),
    );
  }
}
