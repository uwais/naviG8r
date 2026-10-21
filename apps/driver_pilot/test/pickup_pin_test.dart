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

    // Second review, 21 Oct 2026: the pin stayed while the words merely contained the saved town.
    Future<void> expectPinDropped(
        WidgetTester tester, String searched, String retyped) async {
      final box = await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), searched);
      await _search(tester);
      expect(box.pin, isNotNull);
      await tester.enterText(find.byType(TextField), retyped);
      await tester.pumpAndSettle();
      expect(box.pin, isNull, reason: '"$retyped" is not the place "$searched" was found for');
      expect(box.staleCount, 1);
    }

    testWidgets('a road named after the saved town, in another town, drops the pin',
        (tester) async {
      await expectPinDropped(
          tester, 'Hosur', '12 Hosur Road, Koramangala, Bengaluru');
    });

    testWidgets("a town named in another town's road drops the pin", (tester) async {
      await expectPinDropped(tester, 'Okhla, Delhi', 'Delhi Road, Meerut');
    });

    testWidgets('another area of the same town drops the pin', (tester) async {
      await expectPinDropped(
          tester, 'Bommasandra, Bengaluru', 'Whitefield, Bengaluru');
    });
  });

  testWidgets('e: a drag into another town than the typed words warns under the box',
      (tester) async {
    String? warning;
    final words = TextEditingController(text: 'Plot 12, Koramangala, Bengaluru');
    addTearDown(words.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LocationEndpointEditor(
      title: 'Pickup',
      hint: 'City or area',
      labelController: words,
      markerId: 'pickup',
      markerHue: BitmapDescriptor.hueGreen,
      position: const LatLng(12.93, 77.62),
      onPositionChanged: (_) {},
      onPinInAnotherTown: (sentence) => warning = sentence,
      namePin: (point) async => GeocodeOutcome.ok(point, _pinAddress, 'Chennai'),
      keepsFullAddress: true,
    )))));
    await tester.pumpAndSettle();
    await _drag(tester, const LatLng(13.05, 80.25));
    const sentence =
        'The pin is in Chennai, but the address says Bengaluru. Move the pin or change the address.';
    expect(find.text(sentence), findsOneWidget);
    expect(warning, sentence, reason: 'the screen is told, to block Book and pay');
    expect(words.text, 'Plot 12, Koramangala, Bengaluru');

    await tester.enterText(find.byType(TextField), 'Plot 12, Adyar, Chennai');
    await tester.pumpAndSettle();
    expect(find.text(sentence), findsNothing);
    expect(warning, isNull, reason: 'the words now name the town of the pin');
  });

  testWidgets('f: a pickup or drop box stops at 500 characters and counts them; a city box does not',
      (tester) async {
    await _mountPickup(tester);
    final box = tester.widget<TextField>(find.byType(TextField));
    expect(box.maxLength, 500, reason: 'the server refuses a longer address');
    await tester.enterText(find.byType(TextField), 'a' * 600);
    await tester.pumpAndSettle();
    expect(box.controller!.text.length, 500);
    expect(find.text('500/500'), findsOneWidget, reason: 'the counter shows under the box');

    await _mountPickup(tester, keepsFullAddress: false);
    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, isNull);
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
