// The action bar from spec/components.md: the screen's primary action stays visible at
// 360 x 800 above long content, including at 200% text.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mountScreen(WidgetTester tester,
    {required VoidCallback onBook}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(
      body: ListView(children: [
        for (var row = 0; row < 40; row++) Text('Content row $row'),
      ]),
      bottomNavigationBar: NvActionBar(
        child: FilledButton(onPressed: onBook, child: const Text('Get price')),
      ),
    ),
  ));
}

void main() {
  testWidgets('keeps the primary action on screen below long content',
      (tester) async {
    var pressed = false;
    await mountScreen(tester, onBook: () => pressed = true);

    expect(find.text('Get price').hitTestable(), findsOneWidget,
        reason:
            'decisions.md: the primary action is visible without scrolling at 360 x 800');
    expect(
        tester.getBottomLeft(find.text('Get price')).dy, lessThanOrEqualTo(800),
        reason: 'the action sits inside the screen');
    await tester.tap(find.text('Get price'));
    expect(pressed, isTrue, reason: 'the action in the bar works');
  });

  testWidgets('stays visible at 200% text while the content scrolls above it',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountScreen(tester, onBook: () {});

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Get price').hitTestable(), findsOneWidget,
        reason:
            'accessibility.md: the sticky action bar stays; content scrolls above it');
  });
}
