import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what a screen reader is told.
List<String> watchAnnouncements(WidgetTester tester) {
  final announced = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    if ((message as Map)['type'] == 'announce') {
      announced.add((message['data'] as Map)['message'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return announced;
}

/// System text at 200% for the rest of the test.
void useDoubleTextSize(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Scrolls the screen's main list from its top until [finder] is built and on screen: a list
/// builds only the rows near what shows.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 200, scrollable: list);
  // Its last step jumps without a frame, so lay out once more before anything is tapped.
  await tester.pump();
}

/// Scrolls the screen's main list, or [list], from top to bottom, so every part of it is laid
/// out, and fails on the first overflow (a RenderFlex overflow is reported as an exception).
Future<void> expectNoOverflowToTheEnd(WidgetTester tester, String screen,
    {Finder? list}) async {
  expect(tester.takeException(), isNull,
      reason: 'brief 7: 200% text, $screen at the top');
  final scrollable = list ?? find.byType(Scrollable).first;
  if (scrollable.evaluate().isEmpty) return;
  final position = tester.state<ScrollableState>(scrollable).position;
  if (position.axis != Axis.vertical) return;
  while (position.pixels < position.maxScrollExtent) {
    position.jumpTo((position.pixels + 300).clamp(0, position.maxScrollExtent));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'brief 7: 200% text, $screen scrolled to ${position.pixels}');
  }
}
