// The achievements' emblems (r9, stage 2): what each badge says, drawn as
// data. HankoBadge (hanko_badge.dart) paints them; nothing else reads them.
//
// Every emblem is one bold idea in filled shapes, never strokes, so a
// knockout is just a shape painted in the badge's face colour (`erase`).
// Each is drawn twice, as an optical cut: `large` on a 32-unit grid for
// badges of 32 dp and up, `small` on a 16-unit grid for 24 dp and down. At
// 24 dp the large cut's thin parts close up; at 32 the small cut looks
// coarse. On the CPH2573 (DPR 4) both grids put every edge on whole device
// pixels at 20, 24, 32 and 48 dp.
//
// The numbers are badge-builder.js's EM table, revision 1 (the design round's
// reference geometry, r9/achievements/badges/), written out by a script so
// they match it exactly; loops in the builder are unrolled here. Keys are the
// catalogue's ids (system/catalogue.md §3), in its order. Two drawings stay
// in the builder only: the rejected first tries, and the closed-edition plate
// for retired Hanj Cards, kept on file and unbuilt (decision e).

/// The six families, each with its own outline. The emblem tells the
/// achievement; the outline tells the family, so the page reads without
/// colour.
enum HankoBadgeFamily {
  /// The square seal: counts are what a seal has always certified.
  milestones,

  /// The wide seal, 4:3: a stretch of your rating ruler.
  taste,

  /// The lozenge: a seal turned on its point, facing every way.
  range,

  /// The ticket, its corners notched in: you kept your seat.
  stayingWithIt,

  /// The registered seal: a square with a V cut in the middle of each side,
  /// where a printer cuts the marks that set each sheet in its place. Your
  /// picks are the shows you set in their place.
  yourPicks,

  /// The plate, corners bevelled: an edition is numbered pulls from a plate.
  founder,
}

/// One achievement's emblem: its family and its two cuts.
class HankoEmblem {
  const HankoEmblem(this.family, {required this.large, required this.small});

  final HankoBadgeFamily family;

  /// On a 32-unit grid, for badges of 32 dp and up.
  final List<HankoEmblemShape> large;

  /// On a 16-unit grid, for badges of 24 dp and down.
  final List<HankoEmblemShape> small;
}

/// A filled shape in grid units. [erase] paints it in the badge's face
/// colour instead of its ink: the gap that parts a tally's strike from its
/// strokes. Shapes paint in order, so an erased shape cuts only what was
/// drawn before it.
sealed class HankoEmblemShape {
  const HankoEmblemShape({required this.erase});

  final bool erase;
}

/// A rectangle, turned [turn] degrees about its own centre.
class HankoRect extends HankoEmblemShape {
  const HankoRect(this.x, this.y, this.w, this.h, {this.turn = 0, super.erase = false});

  final double x, y, w, h, turn;
}

/// A rectangular ring [t] thick, turned [turn] degrees about its centre.
class HankoRectRing extends HankoEmblemShape {
  const HankoRectRing(this.x, this.y, this.w, this.h, this.t,
      {this.turn = 0, super.erase = false});

  final double x, y, w, h, t, turn;
}

/// A polygon as x, y pairs, clockwise, grown outward by [grow] (a halo
/// erased around a shape before the shape itself is drawn).
class HankoPolygon extends HankoEmblemShape {
  const HankoPolygon(this.points, {this.grow = 0, super.erase = false});

  final List<double> points;
  final double grow;
}

/// A straight bar [w] wide from (x1, y1) to (x2, y2), with square ends.
class HankoBar extends HankoEmblemShape {
  const HankoBar(this.x1, this.y1, this.x2, this.y2, this.w, {super.erase = false});

  final double x1, y1, x2, y2, w;
}

/// A lozenge centred on (cx, cy), [h] from centre to each point.
class HankoLozenge extends HankoEmblemShape {
  const HankoLozenge(this.cx, this.cy, this.h) : super(erase: false);

  final double cx, cy, h;
}

/// A lozenge's outline, [t] thick measured square to its sides.
class HankoLozengeRing extends HankoEmblemShape {
  const HankoLozengeRing(this.cx, this.cy, this.h, this.t) : super(erase: false);

  final double cx, cy, h, t;
}

/// A disc: people are round in Hanj.
class HankoCircle extends HankoEmblemShape {
  const HankoCircle(this.cx, this.cy, this.r) : super(erase: false);

  final double cx, cy, r;
}

/// Text centred on [x], its baseline at [y], [size] units tall: Founder's
/// edition number in Shippori ([HankoLabel.number], the badge's own
/// number), or a fixed figure in Jost 500.
class HankoLabel extends HankoEmblemShape {
  const HankoLabel(String this.text, this.x, this.y, this.size) : super(erase: false);

  const HankoLabel.number(this.x, this.y, this.size)
      : text = null,
        super(erase: false);

  /// Null for the badge's own number.
  final String? text;
  final double x, y, size;
}

/// The 22 emblems, by catalogue id.
const Map<String, HankoEmblem> hankoBadgeEmblems = {
  // ── Milestones ──
  // Finished: a tally: four strokes and the strike, one stroke per show finished.
  'finished': HankoEmblem(
    HankoBadgeFamily.milestones,
    large: [
      HankoRect(8.6, 8.0, 2.2, 16.0),
      HankoRect(12.8, 8.0, 2.2, 16.0),
      HankoRect(17.0, 8.0, 2.2, 16.0),
      HankoRect(21.2, 8.0, 2.2, 16.0),
      HankoBar(6.4, 21.0, 25.6, 11.0, 4.5, erase: true),
      HankoBar(6.4, 21.0, 25.6, 11.0, 2.3),
    ],
    small: [
      HankoRect(4.55, 4.2, 1.5, 7.6),
      HankoRect(7.25, 4.2, 1.5, 7.6),
      HankoRect(9.95, 4.2, 1.5, 7.6),
      HankoBar(3.9, 10.3, 12.1, 5.7, 2.7, erase: true),
      HankoBar(3.9, 10.3, 12.1, 5.7, 1.4),
    ],
  ),
  // Episodes: a strip of film, one frame an episode: the reel Hanj counts in.
  'episodes': HankoEmblem(
    HankoBadgeFamily.milestones,
    large: [
      HankoRect(10.0, 6.5, 12.0, 19.0),
      HankoRect(11.0, 7.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 7.7, 1.5, 1.5, erase: true),
      HankoRect(11.0, 10.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 10.7, 1.5, 1.5, erase: true),
      HankoRect(11.0, 13.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 13.7, 1.5, 1.5, erase: true),
      HankoRect(11.0, 16.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 16.7, 1.5, 1.5, erase: true),
      HankoRect(11.0, 19.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 19.7, 1.5, 1.5, erase: true),
      HankoRect(11.0, 22.7, 1.5, 1.5, erase: true),
      HankoRect(19.5, 22.7, 1.5, 1.5, erase: true),
      HankoRect(13.6, 8.0, 4.8, 4.6, erase: true),
      HankoRect(13.6, 13.6, 4.8, 4.6, erase: true),
      HankoRect(13.6, 19.2, 4.8, 4.6, erase: true),
    ],
    small: [
      HankoRect(5.0, 3.6, 6.0, 8.8),
      HankoRect(5.55, 4.4, 0.95, 0.95, erase: true),
      HankoRect(9.5, 4.4, 0.95, 0.95, erase: true),
      HankoRect(5.55, 7.4, 0.95, 0.95, erase: true),
      HankoRect(9.5, 7.4, 0.95, 0.95, erase: true),
      HankoRect(5.55, 10.4, 0.95, 0.95, erase: true),
      HankoRect(9.5, 10.4, 0.95, 0.95, erase: true),
      HankoRect(7.05, 4.4, 1.9, 3.1, erase: true),
      HankoRect(7.05, 8.15, 1.9, 3.1, erase: true),
    ],
  ),
  // ── Range ──
  // Genres: a lattice of lozenges, every other one open: many kinds.
  'genres': HankoEmblem(
    HankoBadgeFamily.range,
    large: [
      HankoLozenge(16.0, 9.2, 2.4),
      HankoLozengeRing(12.6, 12.6, 2.4, 0.9),
      HankoLozenge(9.2, 16.0, 2.4),
      HankoLozengeRing(19.4, 12.6, 2.4, 0.9),
      HankoLozenge(16.0, 16.0, 2.4),
      HankoLozengeRing(12.6, 19.4, 2.4, 0.9),
      HankoLozenge(22.8, 16.0, 2.4),
      HankoLozengeRing(19.4, 19.4, 2.4, 0.9),
      HankoLozenge(16.0, 22.8, 2.4),
    ],
    small: [
      HankoLozenge(8.0, 4.8, 1.15),
      HankoLozenge(6.4, 6.4, 1.15),
      HankoLozenge(4.8, 8.0, 1.15),
      HankoLozenge(9.6, 6.4, 1.15),
      HankoLozenge(8.0, 8.0, 1.15),
      HankoLozenge(6.4, 9.6, 1.15),
      HankoLozenge(11.2, 8.0, 1.15),
      HankoLozenge(9.6, 9.6, 1.15),
      HankoLozenge(8.0, 11.2, 1.15),
    ],
  ),
  // Decades: points along one line of time.
  'decades': HankoEmblem(
    HankoBadgeFamily.range,
    large: [
      HankoRect(7.6, 15.3, 16.8, 1.4),
      HankoLozenge(9.6, 16.0, 2.6),
      HankoLozenge(16.0, 16.0, 3.5),
      HankoLozenge(22.4, 16.0, 2.6),
    ],
    small: [
      HankoRect(4.5, 7.6, 7.0, 0.8),
      HankoLozenge(5.4, 8.0, 1.3),
      HankoLozenge(8.0, 8.0, 1.75),
      HankoLozenge(10.6, 8.0, 1.3),
    ],
  ),
  // Every form: four forms, four shapes: wide, tall, square and turned.
  'forms': HankoEmblem(
    HankoBadgeFamily.range,
    large: [
      HankoRect(13.0, 9.5, 6.0, 3.4),
      HankoRect(19.1, 13.0, 3.4, 6.0),
      HankoRect(13.8, 18.6, 4.4, 4.4),
      HankoLozenge(11.2, 16.0, 3.0),
    ],
    small: [
      HankoRect(6.7, 4.95, 2.6, 1.5),
      HankoRect(9.55, 6.7, 1.5, 2.6),
      HankoRect(7.0, 9.3, 2.0, 2.0),
      HankoLozenge(5.7, 8.0, 1.4),
    ],
  ),
  // A full year: four lozenges, one for each season.
  'full_year': HankoEmblem(
    HankoBadgeFamily.range,
    large: [
      HankoLozenge(16.0, 11.4, 3.6),
      HankoLozenge(11.4, 16.0, 3.6),
      HankoLozenge(20.6, 16.0, 3.6),
      HankoLozenge(16.0, 20.6, 3.6),
    ],
    small: [
      HankoLozenge(8.0, 5.75, 1.85),
      HankoLozenge(5.75, 8.0, 1.85),
      HankoLozenge(10.25, 8.0, 1.85),
      HankoLozenge(8.0, 10.25, 1.85),
    ],
  ),
  // ── Staying with it ──
  // The long haul: rows of ticks, as days are marked on a wall.
  'long_haul': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoRect(8.75, 8.6, 1.4, 4.4),
      HankoRect(11.35, 8.6, 1.4, 4.4),
      HankoRect(13.95, 8.6, 1.4, 4.4),
      HankoRect(16.55, 8.6, 1.4, 4.4),
      HankoRect(19.15, 8.6, 1.4, 4.4),
      HankoRect(21.75, 8.6, 1.4, 4.4),
      HankoRect(8.75, 14.2, 1.4, 4.4),
      HankoRect(11.35, 14.2, 1.4, 4.4),
      HankoRect(13.95, 14.2, 1.4, 4.4),
      HankoRect(16.55, 14.2, 1.4, 4.4),
      HankoRect(19.15, 14.2, 1.4, 4.4),
      HankoRect(21.75, 14.2, 1.4, 4.4),
      HankoRect(8.75, 19.8, 1.4, 4.4),
      HankoRect(11.35, 19.8, 1.4, 4.4),
      HankoRect(13.95, 19.8, 1.4, 4.4),
      HankoRect(16.55, 19.8, 1.4, 4.4),
      HankoRect(19.15, 19.8, 1.4, 4.4),
      HankoRect(21.75, 19.8, 1.4, 4.4),
    ],
    small: [
      HankoRect(4.65, 4.3, 1.0, 2.1),
      HankoRect(6.55, 4.3, 1.0, 2.1),
      HankoRect(8.45, 4.3, 1.0, 2.1),
      HankoRect(10.35, 4.3, 1.0, 2.1),
      HankoRect(4.65, 7.0, 1.0, 2.1),
      HankoRect(6.55, 7.0, 1.0, 2.1),
      HankoRect(8.45, 7.0, 1.0, 2.1),
      HankoRect(10.35, 7.0, 1.0, 2.1),
      HankoRect(4.65, 9.7, 1.0, 2.1),
      HankoRect(6.55, 9.7, 1.0, 2.1),
      HankoRect(8.45, 9.7, 1.0, 2.1),
      HankoRect(10.35, 9.7, 1.0, 2.1),
    ],
  ),
  // As it aired: the same day marked, week after week.
  'as_it_aired': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoRect(16.8, 8.8, 2.4, 14.4),
      HankoRect(8.8, 8.8, 2.4, 2.4),
      HankoRect(12.8, 8.8, 2.4, 2.4),
      HankoRect(20.8, 8.8, 2.4, 2.4),
      HankoRect(8.8, 12.8, 2.4, 2.4),
      HankoRect(12.8, 12.8, 2.4, 2.4),
      HankoRect(20.8, 12.8, 2.4, 2.4),
      HankoRect(8.8, 16.8, 2.4, 2.4),
      HankoRect(12.8, 16.8, 2.4, 2.4),
      HankoRect(20.8, 16.8, 2.4, 2.4),
      HankoRect(8.8, 20.8, 2.4, 2.4),
      HankoRect(12.8, 20.8, 2.4, 2.4),
      HankoRect(20.8, 20.8, 2.4, 2.4),
    ],
    small: [
      HankoRect(7.2, 4.5, 1.6, 7.0),
      HankoRect(4.5, 4.5, 1.6, 1.6),
      HankoRect(9.9, 4.5, 1.6, 1.6),
      HankoRect(4.5, 7.2, 1.6, 1.6),
      HankoRect(9.9, 7.2, 1.6, 1.6),
      HankoRect(4.5, 9.9, 1.6, 1.6),
      HankoRect(9.9, 9.9, 1.6, 1.6),
    ],
  ),
  // Second chance: one tick dropped, lying in the gap, and the run going on past it.
  'second_chance': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoRect(6.8, 9.5, 2.2, 13.0),
      HankoRect(10.0, 9.5, 2.2, 13.0),
      HankoRect(12.8, 20.3, 6.4, 2.2),
      HankoRect(19.8, 9.5, 2.2, 13.0),
      HankoRect(23.0, 9.5, 2.2, 13.0),
    ],
    small: [
      HankoRect(3.7, 4.6, 1.3, 6.8),
      HankoRect(5.6, 4.6, 1.3, 6.8),
      HankoRect(7.05, 10.2, 1.8, 1.2),
      HankoRect(9.0, 4.6, 1.3, 6.8),
      HankoRect(10.9, 4.6, 1.3, 6.8),
    ],
  ),
  // Off the watchlist: a print that kept its bookmark: Hanj's Plan to watch, followed through.
  'off_watchlist': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoRect(10.0, 8.6, 12.0, 15.4),
      HankoPolygon([17.6, 6.0, 20.8, 6.0, 20.8, 15.8, 19.2, 14.1, 17.6, 15.8], grow: 0.9, erase: true),
      HankoPolygon([17.6, 6.0, 20.8, 6.0, 20.8, 15.8, 19.2, 14.1, 17.6, 15.8]),
    ],
    small: [
      HankoRect(5.0, 4.6, 6.0, 7.6),
      HankoPolygon([8.7, 3.3, 10.4, 3.3, 10.4, 8.3, 9.55, 7.4, 8.7, 8.3], grow: 0.6, erase: true),
      HankoPolygon([8.7, 3.3, 10.4, 3.3, 10.4, 8.3, 9.55, 7.4, 8.7, 8.3]),
    ],
  ),
  // Deep in a genre: one lozenge, ringed and ringed again: one kind, deep.
  'deep_genre': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoLozengeRing(16.0, 16.0, 8.4, 1.4),
      HankoLozengeRing(16.0, 16.0, 5.2, 1.4),
      HankoLozenge(16.0, 16.0, 2.2),
    ],
    small: [
      HankoLozengeRing(8.0, 8.0, 4.4, 1.0),
      HankoLozenge(8.0, 8.0, 1.7),
    ],
  ),
  // ── Your picks ──
  // Named a masterpiece: one print standing alone on its own shelf: Hanj's Masterpiece shelf.
  'masterpiece': HankoEmblem(
    HankoBadgeFamily.yourPicks,
    large: [
      HankoRect(11.2, 6.4, 9.6, 14.6),
      HankoRect(5.6, 21.8, 20.8, 1.6),
      HankoRect(7.0, 23.4, 1.4, 2.2),
      HankoRect(23.6, 23.4, 1.4, 2.2),
    ],
    small: [
      HankoRect(5.4, 3.5, 5.2, 7.2),
      HankoRect(3.2, 11.2, 9.6, 0.9),
      HankoRect(3.8, 12.1, 0.8, 1.0),
      HankoRect(11.4, 12.1, 0.8, 1.0),
    ],
  ),
  // Found a hidden gem: a lozenge resting at the end of a shelf of prints.
  'hidden_gem': HankoEmblem(
    HankoBadgeFamily.yourPicks,
    large: [
      HankoRect(7.6, 9.6, 4.0, 11.0),
      HankoRect(12.6, 9.6, 4.0, 11.0),
      HankoLozenge(21.2, 17.6, 3.3),
      HankoRect(7.0, 21.4, 18.0, 1.6),
    ],
    small: [
      HankoRect(3.9, 5.0, 2.2, 5.6),
      HankoRect(6.7, 5.0, 2.2, 5.6),
      HankoLozenge(10.7, 9.0, 1.75),
      HankoRect(3.6, 11.4, 8.8, 1.0),
    ],
  ),
  // Marked a favourite: a picture hung on your wall, on a low wire from one nail.
  'favourite': HankoEmblem(
    HankoBadgeFamily.yourPicks,
    large: [
      HankoRect(15.25, 7.6, 1.5, 1.5),
      HankoBar(11.0, 12.9, 16.0, 10.2, 0.9),
      HankoBar(21.0, 12.9, 16.0, 10.2, 0.9),
      HankoRect(10.5, 12.6, 11.0, 12.6),
      HankoPolygon([12.2, 23.6, 15.2, 18.4, 17.0, 20.9, 18.6, 19.2, 20.0, 23.6], erase: true),
    ],
    small: [
      HankoRect(7.45, 3.6, 1.1, 1.1),
      HankoBar(5.8, 6.6, 8.0, 5.2, 0.7),
      HankoBar(10.2, 6.6, 8.0, 5.2, 0.7),
      HankoRect(5.2, 6.4, 5.6, 5.6),
      HankoPolygon([6.1, 11.4, 8.0, 8.7, 9.9, 11.4], erase: true),
    ],
  ),
  // Chose your Top 9: nine prints, three by three.
  'top9': HankoEmblem(
    HankoBadgeFamily.yourPicks,
    large: [
      HankoRect(9.4, 8.0, 3.6, 4.6),
      HankoRect(14.2, 8.0, 3.6, 4.6),
      HankoRect(19.0, 8.0, 3.6, 4.6),
      HankoRect(9.4, 13.6, 3.6, 4.6),
      HankoRect(14.2, 13.6, 3.6, 4.6),
      HankoRect(19.0, 13.6, 3.6, 4.6),
      HankoRect(9.4, 19.2, 3.6, 4.6),
      HankoRect(14.2, 19.2, 3.6, 4.6),
      HankoRect(19.0, 19.2, 3.6, 4.6),
    ],
    small: [
      HankoRect(4.9, 4.3, 1.7, 2.1),
      HankoRect(7.15, 4.3, 1.7, 2.1),
      HankoRect(9.4, 4.3, 1.7, 2.1),
      HankoRect(4.9, 6.9, 1.7, 2.1),
      HankoRect(7.15, 6.9, 1.7, 2.1),
      HankoRect(9.4, 6.9, 1.7, 2.1),
      HankoRect(4.9, 9.5, 1.7, 2.1),
      HankoRect(7.15, 9.5, 1.7, 2.1),
      HankoRect(9.4, 9.5, 1.7, 2.1),
    ],
  ),
  // Ranked a cast: round portraits (people are round in Hanj) sorted into
  // rows by tier rules. Seven or more, never six or fewer: no die has more
  // than six pips.
  'tier_list': HankoEmblem(
    HankoBadgeFamily.yourPicks,
    large: [
      HankoCircle(12.5, 10.0, 1.35),
      HankoCircle(16.0, 10.0, 1.35),
      HankoCircle(19.5, 10.0, 1.35),
      HankoRect(8.2, 12.7, 15.6, 0.8),
      HankoCircle(10.75, 16.0, 1.35),
      HankoCircle(14.25, 16.0, 1.35),
      HankoCircle(17.75, 16.0, 1.35),
      HankoCircle(21.25, 16.0, 1.35),
      HankoRect(8.2, 18.5, 15.6, 0.8),
      HankoCircle(12.5, 22.0, 1.35),
      HankoCircle(16.0, 22.0, 1.35),
      HankoCircle(19.5, 22.0, 1.35),
    ],
    small: [
      HankoCircle(5.2, 5.6, 0.95),
      HankoCircle(8.0, 5.6, 0.95),
      HankoCircle(10.8, 5.6, 0.95),
      HankoRect(3.8, 7.45, 8.4, 0.6),
      HankoCircle(4.6, 10.0, 0.9),
      HankoCircle(6.87, 10.0, 0.9),
      HankoCircle(9.13, 10.0, 0.9),
      HankoCircle(11.4, 10.0, 0.9),
    ],
  ),
  // ── Taste ──
  // Sealed: the seal register: impressions sized by how often, over the ruler.
  'sealed': HankoEmblem(
    HankoBadgeFamily.taste,
    large: [
      HankoRectRing(5.8, 16.2, 3.0, 3.0, 0.9),
      HankoRectRing(10.0, 14.7, 4.5, 4.5, 1.0),
      HankoRect(15.7, 13.2, 6.0, 6.0),
      HankoRectRing(22.9, 15.7, 3.5, 3.5, 0.9),
      HankoRect(5.8, 20.6, 20.6, 1.0),
    ],
    small: [
      HankoRect(3.6, 6.7, 3.2, 3.2),
      HankoRect(7.6, 8.3, 1.6, 1.6),
      HankoRect(10.0, 7.5, 2.4, 2.4),
      HankoRect(3.6, 10.6, 8.8, 0.8),
    ],
  ),
  // Finished and sealed: the reel run to its end, the seal pressed by hand
  // at its close, tilted as a hand presses it. The seal's own inner keyline
  // is cut back in the large cut only.
  'finished_sealed': HankoEmblem(
    HankoBadgeFamily.taste,
    large: [
      HankoRect(6.4, 11.2, 1.8, 9.6),
      HankoRect(9.6, 11.2, 1.8, 9.6),
      HankoRect(12.8, 11.2, 1.8, 9.6),
      HankoRect(15.8, 11.2, 9.6, 9.6, turn: -11.0, erase: true),
      HankoRect(16.8, 12.2, 7.6, 7.6, turn: -11.0),
      HankoRectRing(17.7, 13.1, 5.8, 5.8, 0.55, turn: -11.0, erase: true),
    ],
    small: [
      HankoRect(3.7, 5.6, 1.25, 4.8),
      HankoRect(5.9, 5.6, 1.25, 4.8),
      HankoRect(7.2, 5.0, 6.0, 6.0, turn: -11.0, erase: true),
      HankoRect(8.2, 6.0, 4.0, 4.0, turn: -11.0),
    ],
  ),
  // The whole ruler: the ruler from end to end, both ends marked.
  'whole_ruler': HankoEmblem(
    HankoBadgeFamily.taste,
    large: [
      HankoRect(6.5, 17.4, 19.0, 1.2),
      HankoRect(6.5, 10.6, 1.6, 8.0),
      HankoRect(23.9, 10.6, 1.6, 8.0),
      HankoRect(5.4, 9.0, 3.8, 3.8),
      HankoRect(22.8, 9.0, 3.8, 3.8),
      HankoRect(8.833, 14.6, 0.8, 2.8),
      HankoRect(10.766, 14.6, 0.8, 2.8),
      HankoRect(12.699, 14.6, 0.8, 2.8),
      HankoRect(14.632, 14.6, 0.8, 2.8),
      HankoRect(16.565, 14.6, 0.8, 2.8),
      HankoRect(18.498, 14.6, 0.8, 2.8),
      HankoRect(20.431, 14.6, 0.8, 2.8),
      HankoRect(22.364, 14.6, 0.8, 2.8),
    ],
    small: [
      HankoRect(3.8, 9.6, 8.4, 0.85),
      HankoRect(3.8, 5.6, 1.1, 4.85),
      HankoRect(11.1, 5.6, 1.1, 4.85),
      HankoRect(5.95, 8.2, 0.7, 1.4),
      HankoRect(7.65, 8.2, 0.7, 1.4),
      HankoRect(9.35, 8.2, 0.7, 1.4),
    ],
  ),
  // ── Founder ──
  // Founder: the edition number, one of the first fifty. The page only, never
  // the corner (decision f): a number on an avatar's corner reads as a count.
  'founder': HankoEmblem(
    HankoBadgeFamily.founder,
    large: [
      HankoLabel.number(16.0, 18.6, 13.0),
      HankoRect(11.5, 20.6, 9.0, 0.8),
      HankoLabel('50', 16.0, 27.1, 5.2),
    ],
    small: [
      HankoLabel.number(8.0, 11.1, 8.2),
    ],
  ),
  // ── Unlisted: written in only when they happen ──
  // Against the crowd: your seal, solid, apart from the crowd's outlined ones.
  'against_crowd': HankoEmblem(
    HankoBadgeFamily.taste,
    large: [
      HankoRectRing(6.4, 12.0, 3.2, 3.2, 0.9),
      HankoRectRing(10.4, 12.0, 3.2, 3.2, 0.9),
      HankoRectRing(6.4, 16.0, 3.2, 3.2, 0.9),
      HankoRectRing(10.4, 16.0, 3.2, 3.2, 0.9),
      HankoRect(17.2, 11.2, 8.8, 8.8, erase: true),
      HankoRect(18.2, 12.2, 6.8, 6.8),
      HankoRectRing(19.1, 13.1, 5.0, 5.0, 0.55, erase: true),
    ],
    small: [
      HankoRect(3.7, 6.3, 1.5, 1.5),
      HankoRect(5.9, 6.3, 1.5, 1.5),
      HankoRect(3.7, 8.5, 1.5, 1.5),
      HankoRect(5.9, 8.5, 1.5, 1.5),
      HankoRect(9.0, 5.9, 3.6, 3.6),
    ],
  ),
  // On the day: the two halves of a split tally stick, notched in the same
  // place: the day then, and now.
  'on_the_day': HankoEmblem(
    HankoBadgeFamily.stayingWithIt,
    large: [
      HankoPolygon([7.5, 10.2, 24.5, 10.2, 24.5, 14.6, 21.0, 14.6, 18.5, 12.2, 16.0, 14.6, 7.5, 14.6]),
      HankoPolygon([7.5, 17.4, 16.0, 17.4, 18.5, 19.8, 21.0, 17.4, 24.5, 17.4, 24.5, 21.8, 7.5, 21.8]),
      HankoRect(9.2, 10.2, 0.9, 1.5, erase: true),
      HankoRect(9.2, 20.3, 0.9, 1.5, erase: true),
      HankoRect(11.4, 10.2, 0.9, 1.5, erase: true),
      HankoRect(11.4, 20.3, 0.9, 1.5, erase: true),
      HankoRect(13.6, 10.2, 0.9, 1.5, erase: true),
      HankoRect(13.6, 20.3, 0.9, 1.5, erase: true),
      HankoRect(22.4, 10.2, 0.9, 1.5, erase: true),
      HankoRect(22.4, 20.3, 0.9, 1.5, erase: true),
    ],
    small: [
      HankoPolygon([4.0, 5.3, 12.0, 5.3, 12.0, 7.4, 10.6, 7.4, 9.3, 6.2, 8.0, 7.4, 4.0, 7.4]),
      HankoPolygon([4.0, 8.6, 8.0, 8.6, 9.3, 9.8, 10.6, 8.6, 12.0, 8.6, 12.0, 10.7, 4.0, 10.7]),
      HankoRect(5.2, 5.3, 0.7, 0.8, erase: true),
      HankoRect(6.6, 5.3, 0.7, 0.8, erase: true),
      HankoRect(5.2, 9.9, 0.7, 0.8, erase: true),
      HankoRect(6.6, 9.9, 0.7, 0.8, erase: true),
    ],
  ),
};
