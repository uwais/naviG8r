// The app leaving the screen and coming back, one step at a time as a phone reports it: the
// lifecycle listener asserts on a skipped step.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _stepThrough(
    WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

/// Inactive, hidden, then paused. The app is brought back when the test ends, so a failed test
/// does not leave the next one in the background.
Future<void> sendAppToBackground(WidgetTester tester) async {
  addTearDown(() {
    if (tester.binding.lifecycleState != AppLifecycleState.paused) return;
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  });
  await _stepThrough(tester, const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]);
}

/// Hidden, inactive, then resumed.
Future<void> bringAppBack(WidgetTester tester) => _stepThrough(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]);
