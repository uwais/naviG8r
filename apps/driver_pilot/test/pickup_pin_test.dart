// Owner, 21 Oct 2026: "Simplify: pin decides, shipper confirms. Remove the town-matching warning and
// keep-pin rules. Typed words always kept; Book shows the pin's address and a map to check." A
// booking's pickup or drop: a search pick or a drag sets the pin, typing never moves or drops it, an
// empty box takes Google's address, and "Pin: ..." under the box says where the pin is. A trip's city
// fields are unchanged.
import 'dart:async';

import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _pinAddress =
    '14, Lattice Bridge Rd, Adyar, Chennai, Tamil Nadu 600020, India';
const _searchedAddress = 'Bommasandra, Bengaluru, Karnataka 560099, India';

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
    PlaceFinder? findPlace,
    PinNamer? namePin}) async {
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
                                const LatLng(12.8, 77.7), _searchedAddress, 'Bengaluru'),
                        namePin: namePin ??
                            (point) async => GeocodeOutcome.ok(point, _pinAddress, 'Chennai'),
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
  });

  testWidgets("a Pin line under the box shows Google's address for the pin",
      (tester) async {
    await _mountPickup(tester,
        startingPin: const LatLng(13.0, 80.2), startingWords: 'Plot 12, Bengaluru');
    await _drag(tester, const LatLng(13.05, 80.25));
    expect(find.text('Pin: $_pinAddress'), findsOneWidget,
        reason: 'owner, 21 Oct 2026: the shipper checks the pin by its address, whatever the words say');

    await tester.enterText(find.byType(TextField), '');
    await tester.enterText(find.byType(TextField), 'Gate 2');
    await tester.pumpAndSettle();
    expect(find.text('Pin: $_pinAddress'), findsOneWidget,
        reason: 'typing does not move the pin, so its address stays');

    await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
    await _search(tester);
    expect(find.text('Pin: $_searchedAddress'), findsOneWidget,
        reason: 'a search pick shows the address the pin went to');
  });

  testWidgets('a dragged pin Google cannot name says so on its Pin line', (tester) async {
    await _mountPickup(tester,
        startingPin: const LatLng(13.0, 80.2),
        startingWords: 'Plot 12, Adyar, Chennai',
        namePin: (point) async => GeocodeOutcome.fail('NETWORK'));
    await _drag(tester, const LatLng(13.05, 80.25));
    expect(find.text('Pin: address not known. Check the pin on the map.'), findsOneWidget);
  });

  testWidgets('after a drag, any words typed keep the pin, even another town',
      (tester) async {
    final box = await _mountPickup(tester,
        startingPin: const LatLng(13.0, 80.2), startingWords: 'Plot 12, 4th Cross, Adyar, Chennai');
    await _drag(tester, const LatLng(13.05, 80.25));
    await tester.enterText(find.byType(TextField), 'Guindy, Bengaluru');
    await tester.pumpAndSettle();
    expect(box.pin, const LatLng(13.05, 80.25),
        reason: 'owner, 21 Oct 2026: the pin decides the place; the words are for the driver');
    expect(find.textContaining('The pin is in'), findsNothing,
        reason: 'the town-matching warning is gone');
    expect(box.staleCount, 0);
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
    testWidgets('the box keeps the words searched, not the address Google gives',
        (tester) async {
      final box = await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), 'Plot 12, Bommasandra');
      await _search(tester);
      expect(box.pin, const LatLng(12.8, 77.7));
      expect(box.words.text, 'Plot 12, Bommasandra');
    });

    testWidgets('typing anything after a search keeps the pin', (tester) async {
      final box = await _mountPickup(tester);
      await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
      await _search(tester);
      for (final words in [
        'Flat 3, Plot 12, Bommasandra, Bengaluru',
        'Whitefield, Bengaluru',
        'Hosur',
        '',
      ]) {
        await tester.enterText(find.byType(TextField), words);
        await tester.pumpAndSettle();
        expect(box.pin, const LatLng(12.8, 77.7),
            reason: 'owner, 21 Oct 2026: typing never moves or drops the pin ("$words")');
      }
      expect(box.staleCount, 0);
    });

    testWidgets('a search answer that comes after the shipper typed keeps the typed words',
        (tester) async {
      final answer = Completer<GeocodeOutcome>();
      final box = await _mountPickup(tester, findPlace: (place) => answer.future);
      await tester.enterText(find.byType(TextField), 'Bommasandra');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Plot 12, Bommasandra, Bengaluru');
      answer.complete(GeocodeOutcome.ok(const LatLng(12.8, 77.7), _searchedAddress, 'Bengaluru'));
      await tester.pumpAndSettle();
      expect(box.pin, const LatLng(12.8, 77.7), reason: 'the answer sets the pin');
      expect(box.words.text, 'Plot 12, Bommasandra, Bengaluru',
          reason: 'and leaves the words typed meanwhile');
    });

    testWidgets("a search with the box emptied meanwhile fills it with Google's address",
        (tester) async {
      final answer = Completer<GeocodeOutcome>();
      final box = await _mountPickup(tester, findPlace: (place) => answer.future);
      await tester.enterText(find.byType(TextField), 'Bommasandra');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '');
      answer.complete(GeocodeOutcome.ok(const LatLng(12.8, 77.7), _searchedAddress, 'Bengaluru'));
      await tester.pumpAndSettle();
      expect(box.words.text, _searchedAddress);
    });
  });

  testWidgets('a slow pin name does not overwrite a newer search pick', (tester) async {
    final named = Completer<GeocodeOutcome>();
    final box = await _mountPickup(tester,
        startingPin: const LatLng(13.0, 80.2),
        namePin: (point) => named.future);
    await _drag(tester, const LatLng(13.05, 80.25));
    await tester.enterText(find.byType(TextField), 'Bommasandra, Bengaluru');
    await _search(tester);
    named.complete(GeocodeOutcome.ok(const LatLng(13.05, 80.25), _pinAddress, 'Chennai'));
    await tester.pumpAndSettle();
    expect(box.pin, const LatLng(12.8, 77.7));
    expect(find.text('Pin: $_searchedAddress'), findsOneWidget,
        reason: 'the address shown is for the pin as it is now');
    expect(find.text('Pin: $_pinAddress'), findsNothing);
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
