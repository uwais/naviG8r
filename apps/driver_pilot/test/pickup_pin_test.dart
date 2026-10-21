// Rishabh, 21 Oct 2026: "Yes keep typed address. Assuming dragging will be done at high zoom? What if
// dragging happens first?" A booking's pickup or drop keeps the shipper's words when the pin moves;
// a drag into an empty box fills it with the pin's address; a small edit after a search keeps the
// pin; and the map works at street level. A trip's city fields are unchanged.
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _pinAddress =
    '14, Lattice Bridge Rd, Adyar, Chennai, Tamil Nadu 600020, India';

class _Box {
  _Box(this.words);
  final TextEditingController words;
  LatLng? pin;
  int staleCount = 0;
}

/// A pickup box as Book shows it: the map once there is a pin, or after a search was tried.
Future<_Box> _mountPickup(WidgetTester tester,
    {LatLng? startingPin,
    String startingWords = '',
    bool keepsFullAddress = true,
    PlaceFinder? findPlace}) async {
  final box = _Box(TextEditingController(text: startingWords))..pin = startingPin;
  addTearDown(box.words.dispose);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: StatefulBuilder(
                  builder: (context, setState) => LocationEndpointEditor(
                        title: 'Pickup',
                        hint: 'City or area',
                        labelController: box.words,
                        markerId: 'pickup',
                        markerHue: BitmapDescriptor.hueGreen,
                        position: box.pin ?? pinNotPlacedYet,
                        onPositionChanged: (pin) => setState(() => box.pin = pin),
                        onPinStale: () => setState(() {
                          box.pin = null;
                          box.staleCount++;
                        }),
                        showMap: box.pin != null,
                        findPlace: findPlace ??
                            (place) async => GeocodeOutcome.ok(
                                const LatLng(12.8, 77.7),
                                'Bommasandra, Bengaluru, Karnataka 560099, India',
                                'Bengaluru'),
                        namePin: (point) async =>
                            GeocodeOutcome.ok(point, _pinAddress, 'Chennai'),
                        keepsFullAddress: keepsFullAddress,
                      ))))));
  await tester.pumpAndSettle();
  return box;
}

Future<void> _drag(WidgetTester tester, LatLng to) async {
  tester.widget<GoogleMap>(find.byType(GoogleMap)).markers.single.onDragEnd!(to);
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Search for place'));
  await tester.pumpAndSettle();
}

double _openingZoom(WidgetTester tester) =>
    tester.widget<GoogleMap>(find.byType(GoogleMap)).initialCameraPosition.zoom;

void main() {
  testWidgets('a: typed words, then a drag: the words stay, only the point moves',
      (tester) async {
    final box = await _mountPickup(tester,
        startingPin: const LatLng(13.0, 80.2), startingWords: 'Plot 12, 4th Cross, Adyar, Chennai');
    await _drag(tester, const LatLng(13.05, 80.25));
    expect(box.words.text, 'Plot 12, 4th Cross, Adyar, Chennai',
        reason: 'the plot number is what the carrier needs');
    expect(box.pin, const LatLng(13.05, 80.25));
    expect(find.text('Pin is near: $_pinAddress'), findsOneWidget,
        reason: "Google's address for the pin shows under the box, to check");
  });

  testWidgets("b: a drag into an empty box fills it with the pin's address",
      (tester) async {
    final box = await _mountPickup(tester,
        findPlace: (place) async => GeocodeOutcome.fail('ZERO_RESULTS'));
    await _search(tester);
    expect(find.byType(GoogleMap), findsOneWidget,
        reason: 'a search that found nothing still opens the map to drag');
    await _drag(tester, const LatLng(13.05, 80.25));
    expect(box.words.text, _pinAddress,
        reason: 'the shipper can then add the plot or flat number');
    expect(box.pin, const LatLng(13.05, 80.25));

    await tester.enterText(find.byType(TextField), 'Flat 3, $_pinAddress');
    await tester.pumpAndSettle();
    expect(box.pin, const LatLng(13.05, 80.25),
        reason: 'adding a flat number keeps the dragged pin');
  });

  group('c: after a search pick', () {
    testWidgets('the box keeps the words searched, and a small edit keeps the pin',
        (tester) async {
      final box = await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
      await _search(tester);
      expect(box.pin, const LatLng(12.8, 77.7));
      expect(box.words.text, 'Bommasandra, Bengaluru');

      await tester.enterText(
          find.byType(TextField), 'Flat 3, Plot 12, Bommasandra, Bengaluru');
      await tester.pumpAndSettle();
      expect(box.pin, const LatLng(12.8, 77.7),
          reason: 'a flat number added is the same place');
      expect(box.staleCount, 0);
    });

    testWidgets('clearing or replacing the words drops the pin', (tester) async {
      final box = await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
      await _search(tester);
      await tester.enterText(find.byType(TextField), 'Hosur');
      await tester.pumpAndSettle();
      expect(box.pin, isNull, reason: 'words without the town are another place');

      await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
      await _search(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(box.pin, isNull, reason: 'an empty box has no place');
    });
  });

  group('d: zoom', () {
    testWidgets('a pickup map opens at street level after a search pick',
        (tester) async {
      await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
      await _search(tester);
      expect(_openingZoom(tester), 17);
    });

    testWidgets('a pickup map that opens with its point set is at street level',
        (tester) async {
      await _mountPickup(tester,
          startingPin: const LatLng(13.0, 80.2), startingWords: 'Guindy, Chennai');
      expect(_openingZoom(tester), 17);
    });

    testWidgets("a trip's city field keeps its town zoom", (tester) async {
      await _mountPickup(tester,
          startingPin: const LatLng(13.0, 80.2),
          startingWords: 'Hoskote',
          keepsFullAddress: false);
      expect(_openingZoom(tester), 12);
    });
  });
}
