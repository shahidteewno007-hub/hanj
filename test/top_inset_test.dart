// The page's top inset is the device's (top-inset, 2026-11-16). OfflineBanner
// used to keep its hidden pill's height above every tab, so a tab started
// ~36 dp down whatever the status bar was. With OfflineBanner.deviceInset the
// hidden pill takes no room: the page starts at the top of the window and
// gets the status bar's height as its top padding, for a SafeArea or Home's
// own top line to use, at 1.0x and 1.3x text alike.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/services/connectivity_service.dart';

void _drain(WidgetTester tester) {
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {}
}

/// The LG V60: 411 dp wide at 2.625, a 76 px (29 dp) status bar.
void _phone(WidgetTester tester, double textScale) {
  tester.view.physicalSize = const Size(1080, 2460);
  tester.view.devicePixelRatio = 2.625;
  tester.view.padding = const FakeViewPadding(top: 76);
  tester.view.viewPadding = const FakeViewPadding(top: 76);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  const page = Key('page');

  for (final scale in [1.0, 1.3]) {
    testWidgets('hidden pill takes no room, the page gets the status bar '
        '(${scale}x)', (tester) async {
      _phone(tester, scale);
      late double paddingTop;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OfflineBanner(
            child: Builder(builder: (context) {
              paddingTop = MediaQuery.paddingOf(context).top;
              return const SizedBox.expand(key: page);
            }),
          ),
        ),
      ));
      await tester.pump();
      _drain(tester);

      expect(tester.getTopLeft(find.byKey(page)).dy, 0,
          reason: 'the hidden pill must not push the page down');
      expect(paddingTop, closeTo(76 / 2.625, 0.001),
          reason: "the page's top padding is the status bar's");
    });
  }
}
