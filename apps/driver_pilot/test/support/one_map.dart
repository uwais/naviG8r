// A screen's one map for its two places (TwoPlaceMap), as tests reach it: its pins by name, the chips that
// choose which pin it moves, and a drag of the chosen pin.
import 'package:driver_pilot/two_place_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Finder oneMapFinder() => find.descendant(
    of: find.byType(TwoPlaceMap), matching: find.byType(GoogleMap));

GoogleMap oneMap(WidgetTester tester) => tester.widget<GoogleMap>(oneMapFinder());

/// The pin named [title] (Pickup, Drop, From, To) on the screen's one map.
Marker pinOnMap(WidgetTester tester, String title) => oneMap(tester)
    .markers
    .singleWhere((pin) => pin.infoWindow.title == title);

/// Taps the chip under the map that makes it move the [title] pin. Pumped by hand, so it also works while
/// a spinner elsewhere never settles.
Future<void> chooseOnMap(WidgetTester tester, String title) async {
  final chip = find.descendant(
      of: find.byType(TwoPlaceMap),
      matching: find.widgetWithText(ChoiceChip, title));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

/// Chooses the [title] pin, as a person would, and drags it to [to]. The caller pumps after.
Future<void> dragPinOnMap(WidgetTester tester, String title, LatLng to) async {
  await chooseOnMap(tester, title);
  pinOnMap(tester, title).onDragEnd!(to);
}
