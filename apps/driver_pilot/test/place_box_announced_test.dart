// Brief section 6: every icon button has a spoken label, and a search or an address lookup that is out is
// announced, not shown only as a spinner. Pickup and Drop boxes take a full address; From and To take a town.
import 'dart:async';

import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/two_place_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _addressBoxes = ['Pickup', 'Drop'];
const _townBoxes = ['From', 'To'];

/// The screen's two place boxes, without the map: [TwoPlaceMapPins.movePin] stands in for a map tap.
Future<TwoPlaceMapPins> _mountBoxes(WidgetTester tester, List<String> titles,
    {PlaceFinder? findPlace, PinNamer? namePin}) async {
  final pins = TwoPlaceMapPins(canDraw: true);
  addTearDown(pins.dispose);
  final words = [for (final _ in titles) TextEditingController()];
  for (final controller in words) {
    addTearDown(controller.dispose);
  }
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Column(children: [
    for (final (index, title) in titles.indexed)
      LocationEndpointEditor(
        title: title,
        hint: 'Place',
        labelController: words[index],
        pins: pins,
        place: index == 0 ? MapPlace.start : MapPlace.end,
        position: pinNotPlacedYet,
        onPositionChanged: (_) {},
        findPlace: findPlace ?? (_) async => GeocodeOutcome.fail('ZERO_RESULTS'),
        namePin: namePin ?? (_) async => GeocodeOutcome.fail('ZERO_RESULTS'),
        keepsFullAddress: titles == _addressBoxes,
        showApiKeyHint: false,
      ),
  ]))));
  return pins;
}

void main() {
  testWidgets('each search button says which place it searches for', (tester) async {
    await _mountBoxes(tester, _addressBoxes);
    for (final tooltip in ['Search for pickup', 'Search for drop']) {
      expect(find.byTooltip(tooltip), findsOneWidget,
          reason: 'brief 6: every icon button has a spoken label, and the two are told apart');
    }
    await _mountBoxes(tester, _townBoxes);
    for (final tooltip in ['Search for From', 'Search for To']) {
      expect(find.byTooltip(tooltip), findsOneWidget,
          reason: 'brief 6: From and To stay as their boxes name them');
    }
    expect(find.byTooltip('Search for place'), findsNothing);
  });

  for (final (titles, sentence) in [
    (_addressBoxes, 'Searching for the pickup.'),
    (_townBoxes, 'Searching for From.'),
  ]) {
    testWidgets('a search that is out is announced: "$sentence"', (tester) async {
      final semantics = tester.ensureSemantics();
      final answer = Completer<GeocodeOutcome>();
      await _mountBoxes(tester, titles, findPlace: (_) => answer.future);
      await tester.enterText(find.byType(TextField).first, 'Hoskote');
      await tester.tap(find.byTooltip(titles == _addressBoxes ? 'Search for pickup' : 'Search for From'));
      await tester.pump();
      expect(tester.getSemantics(find.text(sentence)),
          containsSemantics(label: sentence, isLiveRegion: true),
          reason: 'brief 6: the spinner says nothing to a screen reader, so the search is said in words');

      answer.complete(GeocodeOutcome.fail('ZERO_RESULTS'));
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsNothing, reason: 'the search has answered');
      semantics.dispose();
    });
  }

  testWidgets('looking up the address at a moved pin is announced', (tester) async {
    final semantics = tester.ensureSemantics();
    final named = Completer<GeocodeOutcome>();
    final pins = await _mountBoxes(tester, _addressBoxes, namePin: (_) => named.future);
    pins.movePin(MapPlace.start, const LatLng(12.85, 77.65));
    await tester.pump();
    const sentence = 'Looking up the address at the pin.';
    expect(tester.getSemantics(find.text(sentence)),
        containsSemantics(label: sentence, isLiveRegion: true),
        reason: 'brief 5 and 6: the looking-up state is drawn and announced');
    expect(find.text('Updating address from pin…'), findsNothing);

    named.complete(GeocodeOutcome.ok(
        const LatLng(12.85, 77.65), 'Electronic City, Bengaluru', 'Electronic City'));
    await tester.pumpAndSettle();
    expect(find.text(sentence), findsNothing, reason: 'the address is found');
    semantics.dispose();
  });

  for (final (titles, sentence) in [
    (_addressBoxes, 'Type the address, then search.'),
    (_townBoxes, 'Type a town or area, then search.'),
  ]) {
    testWidgets('an empty search asks for what the box takes: "$sentence"', (tester) async {
      await _mountBoxes(tester, titles, findPlace: (_) async => GeocodeOutcome.fail('EMPTY'));
      await tester.tap(find.byTooltip(titles == _addressBoxes ? 'Search for pickup' : 'Search for From'));
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsOneWidget,
          reason: 'brief 6: a pickup or drop is an address, a trip place is a town');
    });
  }
}
