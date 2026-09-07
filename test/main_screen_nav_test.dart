// Batch 2 guard: the rail appears only from 1024 up, and the shell's rebuild
// contract is unchanged.
//
// Two things are being protected here.
//
// 1. The phone must keep taking the branch it always took. The CPH2573 is
//    360x792 logical, and 792x360 rotated — both below 1024, so both must show
//    the bottom bar and no rail. That is why the breakpoint is 1024 and not
//    600 (WEB.md §9.2).
//
// 2. MainScreen deliberately does NOT use IndexedStack: every tab switch
//    destroys and rebuilds the tab root, and the static caches in Home and
//    Discovery exist to cover exactly that. A rail refactor is precisely the
//    kind of change that would quietly introduce one, so it is asserted.
//
// The rail's own shape is checked too: flush to the left edge, full height,
// and NOT inside the content cap — PageWidth applies to the content beside it,
// never to the rail and content as a pair.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanj/core/responsive.dart';
import 'package:hanj/features/main_screen.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: MainScreen()));
  await tester.pump();
  // Home's loader fails without Firebase; it is caught, and one frame is all
  // this test needs. Drain so it cannot be reported as an unexpected error.
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {}
}

void main() {
  void useMetrics(WidgetTester tester, Size physical, double dpr) {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('phone portrait 360x792 — bottom bar, no rail', (tester) async {
    useMetrics(tester, const Size(1440, 3168), 4.0);
    await _pump(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('phone landscape 792x360 — still bottom bar, no rail',
      (tester) async {
    useMetrics(tester, const Size(3168, 1440), 4.0);
    await _pump(tester);

    expect(find.byType(NavigationRail), findsNothing,
        reason: '792 is above 600 but below 1024 — the phone must not get a rail');
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('desktop 1440x900 — rail replaces the bottom bar', (tester) async {
    useMetrics(tester, const Size(1440, 900), 1.0);
    await _pump(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('just below and just above the 1024 boundary', (tester) async {
    useMetrics(tester, const Size(1023, 800), 1.0);
    await _pump(tester);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);

    useMetrics(tester, const Size(1024, 800), 1.0);
    await _pump(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the rail is flush to the edge and full height', (tester) async {
    useMetrics(tester, const Size(1440, 900), 1.0);
    await _pump(tester);

    final rail = tester.getRect(find.byType(NavigationRail));
    expect(rail.left, 0, reason: 'the rail must sit against the window edge');
    expect(rail.top, 0);
    expect(rail.height, 900,
        reason: 'the rail is a Row sibling, so it spans the full body height');
  });

  testWidgets('the cap applies beside the rail, not around the pair',
      (tester) async {
    // 1920 is above the 1400 cap, so if the Row had been wrapped the rail would
    // be inset from the window edge and the content would stop short of it.
    // That the cap itself binds at 1400 is covered by page_width_layout_test's
    // control case; here the question is only where it is applied.
    //
    // The tab root cannot render in a test (no Firebase), so this asserts the
    // shell geometry rather than anything inside the content.
    useMetrics(tester, const Size(1920, 900), 1.0);
    await _pump(tester);

    final rail = tester.getRect(find.byType(NavigationRail));
    final content = tester.getRect(find.byType(PageWidth));

    expect(rail.left, 0,
        reason: 'if the Row were wrapped by the cap, the rail would be inset');
    // +1 for the rail Container's divider border, which sits outside the
    // NavigationRail widget this finder measures.
    expect(content.left, rail.right + 1,
        reason: 'content begins where the rail ends, past its divider');
    expect(content.right, 1920,
        reason: 'the Row fills the window; the cap lives inside PageWidth');
    // Reaches the bottom of the window. It does not start at 0: OfflineBanner
    // is a Column whose connectivity strip always reserves its ~33 px, sliding
    // rather than unmounting. Pre-existing, and outside the rail either way.
    expect(content.bottom, 900,
        reason: 'content runs to the bottom of the window beside the rail');
    expect(content.top, lessThan(40));
  });

  testWidgets('no IndexedStack — the rebuild-per-switch contract holds',
      (tester) async {
    useMetrics(tester, const Size(1440, 900), 1.0);
    await _pump(tester);
    expect(find.byType(IndexedStack), findsNothing,
        reason: 'Home and Discovery keep static caches because tab roots are '
            'rebuilt on every switch; an IndexedStack would silently change that');
  });
}
