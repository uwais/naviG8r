// The map's states from spec/components.md: default, legend, loading, location off and failed. A
// plain box stands in for the Google map, which cannot draw under flutter test.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/nv_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const mapStandIn = SizedBox(key: Key('google-map'), height: 200);

Future<void> mountMap(WidgetTester tester, NvMap map,
    {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!),
    home:
        Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: map)),
  ));
}

void main() {
  testWidgets('default draws the map small and names the pins in words',
      (tester) async {
    await mountMap(tester, const NvMap(map: mapStandIn));

    expect(find.byKey(const Key('google-map')), findsOneWidget,
        reason: 'the existing map is drawn inside');
    final height = tester.getSize(find.byKey(const Key('google-map'))).height;
    expect(height, inInclusiveRange(112, 148),
        reason: 'spec/components.md: the map is 112 to 148 dp tall');
    expect(find.text('Pickup and drop'), findsOneWidget,
        reason:
            'accessibility.md: map pins are named in the chip, not by colour alone');
  });

  testWidgets(
      'with pin titles the chip is a legend: each dot beside its title, said in words',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountMap(tester,
        const NvMap(map: mapStandIn, pinTitles: (start: 'Pickup', end: 'Drop')));

    expect(find.text('Pickup and drop'), findsNothing,
        reason: 'the legend replaces the words-only chip');
    expect(tester.getTopLeft(find.text('Pickup')).dx,
        lessThan(tester.getTopLeft(find.text('Drop')).dx),
        reason: 'cp-map: pickup first, then drop');
    expect(find.bySemanticsLabel('Pickup is the navy dot. Drop is the gold dot.'),
        findsOneWidget,
        reason: 'brief 6: colour is never the only signal');
    semantics.dispose();
  });

  for (final (start, end) in [('Pickup', 'Drop'), ('From', 'To'), ('Origin', 'Destination')]) {
    testWidgets('the $start and $end legend fits 360 dp at 200% text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await mountMap(tester, NvMap(map: mapStandIn, pinTitles: (start: start, end: end)));

      expect(tester.takeException(), isNull,
          reason: 'accessibility.md: works at 200% text');
      final map = tester.getRect(find.byType(NvMap));
      for (final title in [start, end]) {
        final words = tester.getRect(find.text(title));
        expect(map.left <= words.left && words.right <= map.right, isTrue,
            reason: '$title stays inside the map');
        expect(map.top <= words.top && words.bottom <= map.bottom, isTrue,
            reason: '$title stays inside the map');
      }
    });
  }

  testWidgets(
      'loading says so in words and drops the spinner for reduce-motion',
      (tester) async {
    await mountMap(
        tester, const NvMap(map: mapStandIn, state: NvMapState.loading));
    expect(find.text('Loading the map'), findsOneWidget,
        reason: 'components PNG: loading words');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'a spinner shows while the map loads');
    expect(find.byKey(const Key('google-map')), findsNothing,
        reason: 'the map is not drawn until it loads');

    await mountMap(
        tester, const NvMap(map: mapStandIn, state: NvMapState.loading),
        reduceMotion: true);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'accessibility.md: spinners respect reduce-motion, words only');
    expect(find.text('Loading the map'), findsOneWidget,
        reason: 'the words stay with reduce-motion on');
  });

  testWidgets(
      'location off points to typing the place, with the button only when offered',
      (tester) async {
    var asked = false;
    await mountMap(
        tester,
        NvMap(
            map: mapStandIn,
            state: NvMapState.locationOff,
            onTurnOnLocation: () => asked = true));

    expect(find.text('Location is off'), findsOneWidget,
        reason: 'components PNG: location off title');
    expect(
        find.text(
            'Type the pickup place above, or turn on location to use where you are.'),
        findsOneWidget,
        reason: 'the map is never the only way to set a place');
    expect(find.widgetWithText(NvButton, 'Turn on location'), findsOneWidget,
        reason: 'Turn on location is the shared secondary button');
    await tester.tap(find.text('Turn on location'));
    expect(asked, isTrue, reason: 'the button calls the screen');

    await mountMap(
        tester, const NvMap(map: mapStandIn, state: NvMapState.locationOff));
    expect(find.text('Turn on location'), findsNothing,
        reason: 'no button for an action the screen does not offer');
  });

  testWidgets('failed says the map could not load and what still works',
      (tester) async {
    await mountMap(
        tester,
        const NvMap(
            map: mapStandIn,
            state: NvMapState.failed,
            failedHelp:
                'Your pickup and drop are still set. You can book without the map.'));

    expect(find.text('The map could not load'), findsOneWidget,
        reason: 'components PNG: failed title');
    expect(
        find.text(
            'Your pickup and drop are still set. You can book without the map.'),
        findsOneWidget,
        reason: 'the screen still works without the map');
    expect(find.byKey(const Key('google-map')), findsNothing,
        reason: 'a failed map is not drawn');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountMap(
        tester, const NvMap(map: mapStandIn, state: NvMapState.locationOff));

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text');
  });
}
