import 'package:flutter/material.dart';

/// A print's flight to the page it opens (Print Room, DESIGN.md §9.3 A rule
/// 5, stage P6): the print you tap flies into the page's print as one Hero,
/// and the show's colour floods in behind it.
///
/// [tag] names the print's Hero (HankoPrint's `heroTag`): where the print lies
/// and which show it is, such as `('shelf', '195516')`, since one show can
/// lie in two places on a screen at once. The page's print takes the same
/// tag, and only a page opened by a flight has one.
///
/// [colour] is the show's colour as the print's place showed it (its mat or
/// its field, the cover's own, read by HankoCoverColour), so the page opens
/// in that colour in its first frame instead of waiting for AniList's.
@immutable
class HankoFlight {
  const HankoFlight({required this.tag, this.colour});

  final Object tag;
  final Color? colour;

  /// The flight, both ways: rule 5's 320 ms.
  static const Duration duration = Duration(milliseconds: 320);
}

/// The route a print flies by (Print Room, P6). The page fades in over the
/// screen it was opened from while the print flies, so the show's colour
/// floods in behind the print; nothing slides, and the screen below stays
/// where it is, since only Material routes move the route under them. Back
/// plays it in reverse. With Remove animations on ([still]) it's instant:
/// no print flies and nothing fades.
class HankoFlightRoute<T> extends PageRoute<T> {
  HankoFlightRoute({required this.builder, required this.still});

  final WidgetBuilder builder;

  /// Remove animations was on when the print was tapped.
  final bool still;

  // The page is all there at 60% of the flight, so the screen below shows
  // through it only briefly; the print lands at the end.
  static final Animatable<double> _fade =
      CurveTween(curve: const Interval(0, 0.6, curve: Curves.easeOut));

  @override
  Duration get transitionDuration =>
      still ? Duration.zero : HankoFlight.duration;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      // A screen of its own to a screen reader, as a Material route says.
      Semantics(
          scopesRoute: true, explicitChildNodes: true, child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation.drive(_fade), child: child);
}
