// The one map for a screen's two places (owner, 5 Nov 2026): the October design's Map component plus the
// approved addition, one pin moved at a time. Two place boxes and the map, as a screen holds them.
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/place_pin_icons.dart';
import 'package:driver_pilot/two_place_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/one_map.dart';

const _bommasandra = LatLng(12.8, 77.7);
const _guindy = LatLng(13.0, 80.2);

class _Places {
  LatLng? pickup;
  LatLng? drop;
  final named = <LatLng>[];
}

/// Pickup and Drop boxes with the one map under them. Each search finds [_bommasandra] for words with
/// "Bommasandra" and [_guindy] otherwise, unless [findsNothing]; a moved pin is named "Named spot".
Future<_Places> _mount(WidgetTester tester,
    {LatLng? pickup,
    LatLng? drop,
    bool readOnly = false,
    bool canDraw = true,
    bool findsNothing = false}) async {
  final places = _Places()
    ..pickup = pickup
    ..drop = drop;
  final pins = TwoPlaceMapPins(canDraw: canDraw);
  final pickupWords = TextEditingController(text: pickup == null ? '' : 'Plot 12');
  final dropWords = TextEditingController(text: drop == null ? '' : 'Gate 4');
  addTearDown(pins.dispose);
  addTearDown(pickupWords.dispose);
  addTearDown(dropWords.dispose);
  Future<GeocodeOutcome> find(String words) async => findsNothing
      ? GeocodeOutcome.fail('ZERO_RESULTS')
      : GeocodeOutcome.ok(
          words.contains('Bommasandra') ? _bommasandra : _guindy, '$words, India', words);
  Future<GeocodeOutcome> name(LatLng point) async {
    places.named.add(point);
    return GeocodeOutcome.ok(point, 'Named spot, India', 'Named spot');
  }

  tester.view.physicalSize = const Size(360, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: StatefulBuilder(
                  builder: (context, setState) => Column(children: [
                        for (final (place, title, words) in [
                          (MapPlace.start, 'Pickup', pickupWords),
                          (MapPlace.end, 'Drop', dropWords),
                        ])
                          LocationEndpointEditor(
                            title: title,
                            hint: 'Address for the driver',
                            labelController: words,
                            pins: pins,
                            place: place,
                            position: (place == MapPlace.start ? places.pickup : places.drop) ??
                                pinNotPlacedYet,
                            onPositionChanged: (moved) => setState(() => place == MapPlace.start
                                ? places.pickup = moved
                                : places.drop = moved),
                            readOnly: readOnly,
                            findPlace: find,
                            namePin: name,
                            keepsFullAddress: true,
                          ),
                        TwoPlaceMap(
                          pins: pins,
                          start: places.pickup,
                          end: places.drop,
                          startTitle: 'Pickup',
                          endTitle: 'Drop',
                          pinsLabel: 'Pickup and drop',
                          failedHelp:
                              'Your pickup and drop are still set. You can book without the map.',
                          pinsAreAddresses: true,
                          readOnly: readOnly,
                        ),
                      ]))))));
  await tester.pumpAndSettle();
  return places;
}

Finder _box(String title) => find.widgetWithText(LocationEndpointEditor, title);

Future<void> _search(WidgetTester tester, String title, String words) async {
  await tester.enterText(
      find.descendant(of: _box(title), matching: find.byType(TextField)), words);
  await tester.tap(find.descendant(
      of: _box(title), matching: find.byTooltip('Search for ${title.toLowerCase()}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('both places share one map, with both pins and a line between them',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _mount(tester);
    expect(find.byType(GoogleMap), findsNothing, reason: 'no place yet, so no map');
    await _search(tester, 'Pickup', 'Bommasandra');
    await _search(tester, 'Drop', 'Guindy');
    expect(find.byType(GoogleMap), findsOneWidget, reason: 'owner, 5 Nov 2026: one map per screen');
    expect(pinOnMap(tester, 'Pickup').position, _bommasandra);
    expect(pinOnMap(tester, 'Drop').position, _guindy);
    expect(oneMap(tester).polylines.single.points, [_bommasandra, _guindy]);
    expect(find.bySemanticsLabel('Pickup is the navy dot. Drop is the gold dot.'), findsOneWidget,
        reason: 'brief 6: colour is never the only signal; the chip says which dot is which');
    semantics.dispose();
  });

  testWidgets('the map moves the pickup first, and says so in words', (tester) async {
    await _mount(tester, pickup: _bommasandra, drop: _guindy);
    expect(find.text('Tap the map to move the pickup pin.'), findsOneWidget);
    expect(pinOnMap(tester, 'Pickup').draggable, isTrue);
    expect(pinOnMap(tester, 'Drop').draggable, isFalse, reason: 'one pin at a time');
  });

  testWidgets('a tap on the map moves only the chosen pin, and looks up its address',
      (tester) async {
    final places = await _mount(tester, pickup: _bommasandra, drop: _guindy);
    const spot = LatLng(12.85, 77.65);
    oneMap(tester).onTap!(spot);
    await tester.pumpAndSettle();
    expect(places.pickup, spot);
    expect(places.drop, _guindy, reason: 'the other pin stays where it was');
    expect(places.named, [spot], reason: 'the address under the moved pin is looked up');
    expect(find.descendant(of: _box('Pickup'), matching: find.text('Pin: Named spot, India')),
        findsOneWidget);
  });

  testWidgets('a chip under the map switches which pin it moves', (tester) async {
    final places = await _mount(tester, pickup: _bommasandra, drop: _guindy);
    await chooseOnMap(tester, 'Drop');
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to move the drop pin.'), findsOneWidget,
        reason: 'the words change with the choice, not only the colour');
    expect(pinOnMap(tester, 'Drop').draggable, isTrue);
    expect(pinOnMap(tester, 'Pickup').draggable, isFalse);
    const spot = LatLng(13.05, 80.25);
    oneMap(tester).onTap!(spot);
    await tester.pumpAndSettle();
    expect(places.drop, spot);
    expect(places.pickup, _bommasandra);
  });

  testWidgets('touching a place box makes the map move that place', (tester) async {
    await _mount(tester, pickup: _bommasandra, drop: _guindy);
    await tester.tap(find.descendant(of: _box('Drop'), matching: find.byType(TextField)));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to move the drop pin.'), findsOneWidget,
        reason: 'owner, 5 Nov 2026: the box touched last is the place being moved');
    await tester.tap(find.descendant(of: _box('Pickup'), matching: find.byType(TextField)));
    await tester.pumpAndSettle();
    expect(find.text('Tap the map to move the pickup pin.'), findsOneWidget);
  });

  testWidgets('dragging the chosen pin moves it, as a tap does', (tester) async {
    final places = await _mount(tester, pickup: _bommasandra, drop: _guindy);
    const spot = LatLng(13.05, 80.25);
    await dragPinOnMap(tester, 'Drop', spot);
    await tester.pumpAndSettle();
    expect(places.drop, spot);
    expect(places.pickup, _bommasandra);
  });

  testWidgets('read-only shows both pins and moves neither', (tester) async {
    await _mount(tester, pickup: _bommasandra, drop: _guindy, readOnly: true);
    expect(oneMap(tester).markers, hasLength(2));
    expect(oneMap(tester).onTap, isNull, reason: 'a tap does nothing');
    expect(oneMap(tester).markers.where((pin) => pin.draggable), isEmpty);
    expect(find.byType(ChoiceChip), findsNothing, reason: 'nothing to choose');
    expect(find.textContaining('Tap the map'), findsNothing);
  });

  testWidgets('a search that finds nothing opens the map, and a tap places that pin',
      (tester) async {
    final pins = TwoPlaceMapPins();
    addTearDown(pins.dispose);
    final words = TextEditingController();
    addTearDown(words.dispose);
    LatLng? drop;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: StatefulBuilder(
                    builder: (context, setState) => Column(children: [
                          LocationEndpointEditor(
                            title: 'Drop',
                            hint: 'Address for the driver',
                            labelController: words,
                            pins: pins,
                            place: MapPlace.end,
                            position: drop ?? pinNotPlacedYet,
                            onPositionChanged: (moved) => setState(() => drop = moved),
                            findPlace: (_) async => GeocodeOutcome.fail('ZERO_RESULTS'),
                            namePin: (point) async => GeocodeOutcome.fail('ZERO_RESULTS'),
                            keepsFullAddress: true,
                          ),
                          TwoPlaceMap(
                            pins: pins,
                            start: null,
                            end: drop,
                            startTitle: 'Pickup',
                            endTitle: 'Drop',
                            pinsLabel: 'Pickup and drop',
                            failedHelp: 'Your pickup and drop are still set.',
                            pinsAreAddresses: true,
                          ),
                        ]))))));
    await tester.enterText(find.byType(TextField), 'Kurudumale');
    await tester.tap(find.byTooltip('Search for drop'));
    await tester.pumpAndSettle();
    expect(find.byType(GoogleMap), findsOneWidget);
    expect(find.text('Tap the map to put the drop pin.'), findsOneWidget,
        reason: 'the box searched is the place the map moves; it has no pin yet to move');
    oneMap(tester).onTap!(_guindy);
    await tester.pumpAndSettle();
    expect(drop, _guindy);
    expect(find.text('Tap the map to move the drop pin.'), findsOneWidget);
  });

  testWidgets('a failed search does not say to tap a map that could not load', (tester) async {
    await _mount(tester, canDraw: false, findsNothing: true);
    await _search(tester, 'Pickup', 'Kurudumale');
    expect(find.text('The map could not load'), findsOneWidget);
    expect(find.text('Could not find this place. Try a nearby town.'), findsOneWidget);
    expect(find.textContaining(RegExp('tap the map', caseSensitive: false)), findsNothing);
  });

  testWidgets('when the map cannot load, it says so and the place boxes still work',
      (tester) async {
    final places = await _mount(tester, canDraw: false);
    await _search(tester, 'Pickup', 'Bommasandra');
    expect(find.text('The map could not load'), findsOneWidget);
    expect(find.text('Type each place in its box and search. The map is not needed.'),
        findsOneWidget,
        reason: 'with only one place set, the design line would not be true yet');
    await _search(tester, 'Drop', 'Guindy');
    expect(places.pickup, _bommasandra, reason: 'search still sets the place');
    expect(places.drop, _guindy);
    expect(find.text('Your pickup and drop are still set. You can book without the map.'),
        findsOneWidget, reason: 'cp-map error state');
    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing, reason: 'no map to move a pin on');
  });

  group('the camera', () {
    test('fits both pins after a change', () {
      expect(
          cameraForPins(_bommasandra, _guindy, zoomForOnePlace: 17).toJson(),
          CameraUpdate.newLatLngBounds(
                  LatLngBounds(southwest: _bommasandra, northeast: _guindy), 48)
              .toJson());
    });

    test('shows one pin at street level for an address, at town level for a town', () {
      expect(cameraForPins(null, _guindy, zoomForOnePlace: 17).toJson(),
          CameraUpdate.newLatLngZoom(_guindy, 17).toJson());
      expect(cameraForPins(_bommasandra, null, zoomForOnePlace: 12).toJson(),
          CameraUpdate.newLatLngZoom(_bommasandra, 12).toJson());
    });

    test('shows all of India before any pin is set', () {
      expect(cameraForPins(null, null, zoomForOnePlace: 17).toJson(),
          CameraUpdate.newLatLngZoom(pinNotPlacedYet, 5).toJson());
    });
  });

  testWidgets('the pins are drawn as two different dots', (tester) async {
    final icons = await tester.runAsync(drawPlacePinIcons);
    expect(icons!.start.toJson(), isNot(equals(icons.end.toJson())),
        reason: 'cp-map: a navy dot for pickup, a gold dot with a navy ring for drop');
  });
}
