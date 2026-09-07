// columnsFor's published table, and the floor that keeps it off the phone.
//
// The arithmetic is desktop content-width arithmetic derived from the 1400 cap.
// Unfloored it returns 2 at 768 and at 792 — and 792 is a CPH2573 in landscape,
// so the shipped phone would get a two-column layout from a formula whose whole
// justification was that 1024 is the safe structural breakpoint and 600 is not.
// The floor lives inside columnsFor so no call site has to remember to clamp.

import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/responsive.dart';

void main() {
  test('published table (WEB.md §9.3)', () {
    expect(Responsive.columnsFor(390), 1);
    expect(Responsive.columnsFor(768), 1);
    expect(Responsive.columnsFor(1024), 2);
    expect(Responsive.columnsFor(1440), 3);
    expect(Responsive.columnsFor(1920), 3);
  });

  test('every phone width the CPH2573 can present is single column', () {
    expect(Responsive.columnsFor(360), 1, reason: 'portrait');
    expect(Responsive.columnsFor(792), 1, reason: 'landscape — the whole point');
  });

  test('the floor sits exactly at the desktop breakpoint', () {
    expect(Responsive.desktopMin, 1024);
    expect(Responsive.columnsFor(1023), 1);
    expect(Responsive.columnsFor(1024), 2);
  });

  test('never exceeds three, and the cap bounds the count above 1400', () {
    expect(Responsive.columnsFor(2560), 3);
    expect(Responsive.columnsFor(5000), 3);
    expect(Responsive.columnsFor(Responsive.pageMaxWidth), 3);
  });

  test('a column is never narrower than the phone width the design is proven at',
      () {
    // 3 x 437 + 2 x 24 gutter + 2 x 20 padding = 1400.
    for (final w in [1024.0, 1280.0, 1440.0, 1920.0]) {
      final cols = Responsive.columnsFor(w);
      final content = w > Responsive.pageMaxWidth ? Responsive.pageMaxWidth : w;
      final colWidth = (content - 40 - (cols - 1) * 24) / cols;
      expect(colWidth, greaterThanOrEqualTo(350),
          reason: 'at ${w}px, $cols columns gives ${colWidth}px each');
    }
  });
}
