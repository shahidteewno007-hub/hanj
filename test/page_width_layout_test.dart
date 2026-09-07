// Batch 1 guard: PageWidth must be inert on the phone.
//
// The 1400 px cap cannot bind at 360 or 792 logical px, so the width is not
// the risk. The risk is that PageWidth wraps the tab root in an Align with no
// widthFactor or heightFactor, which hands its child LOOSE constraints on both
// axes where it previously received tight ones. Anything inside a tab root
// that fills vertically — Expanded, Spacer, a bottom-anchored Column — is
// where that would show, not the horizontal centring.
//
// PulseScreen is the subject: it is the tab root whose initState builds only a
// TabController, so it pumps without Firebase, and its build is exactly the
// shape at risk —
//
//     Scaffold > SafeArea > Column [ header, tabBar, Expanded(TabBarView) ]
//
// Each case compares a full geometric signature — every laid-out RenderBox
// under the Scaffold, by widget type, global position and size — wrapped
// against unwrapped, at the real CPH2573 metrics (1440x3168 @ DPR 4.0 =
// 360x792 logical) in both orientations.
//
// Layout exceptions are compared too, not swallowed. In landscape the Pulse
// empty state already overflows its Column by 14 px at 360 px of height; that
// is pre-existing and happens with and without the wrapper, so the assertion
// is that the wrapper does not change it. See the landscape test.
//
// The last test is a control. At 1920 the cap MUST bind and the signatures
// MUST differ — without it, the equality tests would pass whether or not the
// comparison can detect a difference at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanj/core/responsive.dart';
import 'package:hanj/features/pulse/pulse_screen.dart';

class _Layout {
  _Layout(this.boxes, this.errors);
  final List<String> boxes;
  final List<String> errors;
}

/// Every laid-out box under the first Scaffold, in tree order.
List<String> _signature(WidgetTester tester) {
  final sig = <String>[];
  void visit(Element el) {
    final ro = el.renderObject;
    if (ro is RenderBox && ro.attached && ro.hasSize) {
      final o = ro.localToGlobal(Offset.zero);
      sig.add('${el.widget.runtimeType} '
          '@${o.dx.toStringAsFixed(2)},${o.dy.toStringAsFixed(2)} '
          '${ro.size.width.toStringAsFixed(2)}x${ro.size.height.toStringAsFixed(2)}');
    }
    el.visitChildren(visit);
  }

  visit(find.byType(Scaffold).evaluate().first);
  return sig;
}

/// First line of every exception raised since the last drain.
List<String> _drain(WidgetTester tester) {
  final out = <String>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    out.add(e.toString().split('\n').first.trim());
  }
  return out;
}

/// Pumps one frame only — deterministic, since the feed's FutureBuilder has
/// not resolved and both trees render the same content. Tears the tree down
/// afterwards so a disposal error cannot leak into the next pump.
Future<_Layout> _run(WidgetTester tester, {required bool wrapped}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: wrapped ? const PageWidth(child: PulseScreen()) : const PulseScreen(),
    ),
  );
  await tester.pump();

  final layout = _Layout(_signature(tester), _drain(tester));

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  _drain(tester);

  return layout;
}

Size _sizeOf(List<String> boxes, String type) {
  final line = boxes.firstWhere((b) => b.startsWith('$type '));
  final wh = line.split(' ').last.split('x');
  return Size(double.parse(wh[0]), double.parse(wh[1]));
}

void main() {
  void useMetrics(WidgetTester tester, Size physical, double dpr) {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('portrait 360x792 — PageWidth changes no box', (tester) async {
    useMetrics(tester, const Size(1440, 3168), 4.0);

    final plain = await _run(tester, wrapped: false);
    final wrapped = await _run(tester, wrapped: true);

    expect(plain.boxes, isNotEmpty);
    expect(_sizeOf(plain.boxes, 'Scaffold'), const Size(360, 792),
        reason: 'device metrics should give the CPH2573 its real logical size');
    expect(_sizeOf(wrapped.boxes, 'Scaffold'), const Size(360, 792),
        reason: 'the Align must not shrink-wrap the Scaffold on either axis');
    expect(wrapped.boxes, equals(plain.boxes));
    expect(wrapped.errors, equals(plain.errors));
    expect(plain.errors, isEmpty, reason: 'portrait should lay out cleanly');
  });

  testWidgets('landscape 792x360 — PageWidth changes no box', (tester) async {
    useMetrics(tester, const Size(3168, 1440), 4.0);

    final plain = await _run(tester, wrapped: false);
    final wrapped = await _run(tester, wrapped: true);

    expect(plain.boxes, isNotEmpty);
    expect(_sizeOf(plain.boxes, 'Scaffold'), const Size(792, 360),
        reason: 'landscape is 792 logical px wide — above 600, below 1024');
    expect(_sizeOf(wrapped.boxes, 'Scaffold'), const Size(792, 360));
    expect(wrapped.boxes, equals(plain.boxes));

    // Pre-existing: the empty-state Column at pulse_screen.dart:220 does not
    // fit in 360 px of height. It must overflow identically either way — the
    // wrapper must neither cause it nor change it.
    expect(wrapped.errors, equals(plain.errors),
        reason: 'PageWidth must not change which layout errors occur');

    // Tripwire, and the proof the assertion above is not comparing two empty
    // lists: the overflow is really there, without the wrapper. If Pulse's
    // empty state is ever made to fit at 360 px of height, this line fails and
    // should simply be deleted.
    expect(plain.errors.join(), contains('overflowed'),
        reason: 'the landscape overflow is pre-existing, not caused by PageWidth');
  });

  testWidgets('the vertical axis specifically survives the loose constraints',
      (tester) async {
    useMetrics(tester, const Size(1440, 3168), 4.0);

    // TabBarView sits under the Column's Expanded. If Align's loose vertical
    // constraint let the Column shrink-wrap, this is the box that collapses.
    final plain = await _run(tester, wrapped: false);
    final wrapped = await _run(tester, wrapped: true);

    final plainView = _sizeOf(plain.boxes, 'TabBarView');
    expect(plainView.height, greaterThan(0));
    expect(_sizeOf(wrapped.boxes, 'TabBarView'), equals(plainView),
        reason: 'Expanded must still fill the same height inside PageWidth');
  });

  testWidgets('control — at 1920 the cap binds and the signature does differ',
      (tester) async {
    useMetrics(tester, const Size(1920, 1080), 1.0);

    final plain = await _run(tester, wrapped: false);
    final wrapped = await _run(tester, wrapped: true);

    expect(_sizeOf(plain.boxes, 'Scaffold').width, 1920);
    expect(_sizeOf(wrapped.boxes, 'Scaffold').width, Responsive.pageMaxWidth,
        reason: 'the cap should bind once the viewport exceeds it');
    expect(wrapped.boxes, isNot(equals(plain.boxes)),
        reason: 'if this passes, the equality assertions above are not vacuous');
  });
}
