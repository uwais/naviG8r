// A place box built again while its search was out (scrolled off and back on Find) must not leave the
// screen waiting: the box it replaced told the screen "searching" and was gone before saying "done".
import 'dart:async';

import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  testWidgets('a box built again clears the searching and naming its old box left',
      (tester) async {
    final words = TextEditingController(text: 'Bommasandra');
    addTearDown(words.dispose);
    final search = Completer<GeocodeOutcome>();
    var boxNumber = 0;
    var searching = false;
    var naming = true;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(builder: (context, setState) {
      rebuild = setState;
      return LocationEndpointEditor(
        key: ValueKey(boxNumber),
        title: 'Pickup',
        hint: 'Address for the driver',
        labelController: words,
        markerId: 'pickup',
        markerHue: BitmapDescriptor.hueGreen,
        position: pinNotPlacedYet,
        onPositionChanged: (_) {},
        onSearching: (value) => searching = value,
        onPinNaming: (value) => naming = value,
        showMap: false,
        findPlace: (_) => search.future,
        keepsFullAddress: true,
      );
    }))));
    await tester.pump();
    await tester.tap(find.byTooltip('Search for place'));
    await tester.pump();
    expect(searching, isTrue, reason: 'the search is out');

    naming = true;
    rebuild(() => boxNumber++);
    await tester.pump();
    await tester.pump();
    expect(searching, isFalse,
        reason: 'review: the flag stuck and the screen waited for a search nobody was running');
    expect(naming, isFalse);
  });
}
