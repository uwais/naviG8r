// The office's Publish form (ca-publish, PR 7 of the redesign): its fields, the From and To place search,
// the route map, and reaching Publish with the keyboard open. The leaving days and the draft have their own
// files.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_office_screens.dart';
import 'support/mock_api.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Publish (ca-publish)', () {
    testWidgets('every field starts empty and nothing is chosen',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      // Tall enough that the whole list is built.
      await mount(tester, const DriverPublishTripScreen(),
          size: const Size(800, 3000));
      final placeFields = tester.widgetList<TextField>(find.descendant(
          of: find.byType(LocationEndpointEditor),
          matching: find.byType(TextField)));
      expect(placeFields.map((field) => field.controller!.text), ['', ''],
          reason:
              'spec: From and To start empty (the mockup shows them filled)');
      expect(find.text('Choose a date'), findsNWidgets(2),
          reason: 'both leaving days start empty');
      expect(
          tester
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .where((chip) => chip.selected),
          isEmpty,
          reason: 'truck size: nothing preselected');
      expect(find.widgetWithText(ChoiceChip, 'Medium'), findsOneWidget,
          reason: 'truck size is a chip choice');
      final room = find.descendant(
          of: find.widgetWithText(Column, 'Capacity'),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(room.first).controller!.text, isEmpty);
      expect(find.text('The weight you can carry for shippers on this trip.'),
          findsOneWidget);
      expect(
          find.text('You choose the truck when you accept the first booking.'),
          findsOneWidget);

      await mount(
          tester, const DriverPublishTripScreen(key: ValueKey('phone')));
      final publish = find.widgetWithText(FilledButton, 'Publish trip');
      expect(
          (Offset.zero & const Size(360, 800))
              .contains(tester.getRect(publish).bottomRight),
          isTrue,
          reason:
              'success criterion: primary action visible without scrolling');
    });

    testWidgets(
        'Publish with nothing filled sends nothing and says what is missing',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverPublishTripScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Publish trip'));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);
      expect(
          find.text(
              'Search for the From place so shippers can find this trip.'),
          findsOneWidget);
    });

    testWidgets('no map shows until its place is found', (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.ok(
                  const LatLng(12.97, 77.59), 'Bengaluru, Karnataka')),
          size: const Size(800, 3000));
      expect(find.byType(GoogleMap), findsNothing,
          reason: 'tester: the maps left no room while typing');
      expect(
          find.text('Drag the pin to the exact spot, or search for a place.'),
          findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Bengaluru');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsOneWidget,
          reason: 'From has a point, To does not yet');
      expect(find.text('Bengaluru, Karnataka'), findsWidgets);
    });

    testWidgets('new words in From after a search drop its point, and Publish asks for a search',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.ok(
                  const LatLng(13.07, 77.8), '$place, Karnataka')),
          size: const Size(800, 3000));
      await tester.enterText(find.byType(TextField).first, 'Hoskote');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Kolar');
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsNothing,
          reason: 'reviewer: the Hoskote point stayed under the name Kolar');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish trip'));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);
      expect(
          find.text(
              'Search for the From place so shippers can find this trip.'),
          findsOneWidget);
    });

    group('the route map', () {
      const hoskote = LatLng(13.07, 77.79);
      const kolar = LatLng(13.13, 78.13);
      Widget publish() => DriverPublishTripScreen(
          findPlace: (place) async => GeocodeOutcome.ok(
              place == 'Hoskote' ? hoskote : kolar, '$place, Karnataka'));

      testWidgets('shows both pins and the line once From and To both have a point',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        await mount(tester, publish(), size: const Size(800, 3000));
        expect(find.byType(NvMap), findsNothing, reason: 'no point yet');
        await tester.enterText(find.byType(TextField).at(0), 'Hoskote');
        await tester.tap(find.byTooltip('Look up place').at(0));
        await tester.pumpAndSettle();
        expect(find.byType(NvMap), findsNothing,
            reason: 'with one point there is no route to show');
        await tester.enterText(find.byType(TextField).at(1), 'Kolar');
        await tester.tap(find.byTooltip('Look up place').at(1));
        await tester.pumpAndSettle();

        expect(find.byType(NvMap), findsOneWidget,
            reason: 'Uwais: one map with both places');
        expect(find.text('From and To'), findsOneWidget,
            reason: 'the pins are named in words, not by colour alone');
        final map = tester.widget<GoogleMap>(find.descendant(
            of: find.byType(NvMap), matching: find.byType(GoogleMap)));
        expect(map.markers.map((pin) => pin.position), [hoskote, kolar]);
        expect(map.polylines.single.points, [hoskote, kolar],
            reason: 'a straight line between the two places');
        final toBox = tester.getRect(find.byType(LocationEndpointEditor).at(1));
        expect(tester.getRect(find.byType(NvMap)).top,
            greaterThan(toBox.bottom),
            reason: 'below the From and To place boxes');
      });

      Future<void> findBoth(WidgetTester tester) async {
        for (final (index, place) in [(0, 'Hoskote'), (1, 'Kolar')]) {
          await tester.enterText(find.byType(TextField).at(index), place);
          await tester.tap(find.byTooltip('Look up place').at(index));
          await tester.pumpAndSettle();
        }
      }

      Finder routeMap() =>
          find.descendant(of: find.byType(NvMap), matching: find.byType(GoogleMap));

      testWidgets('its pins are the colours of the From and To place pins',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        await mount(tester, publish(), size: const Size(800, 3000));
        await findBoth(tester);
        expect(
            tester
                .widget<GoogleMap>(routeMap())
                .markers
                .map((pin) => pin.icon.toJson()),
            [
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
                  .toJson(),
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)
                  .toJson(),
            ],
            reason: 'review: green and red on the route, orange and azure above');
      });

      testWidgets('a dragged pin makes a new route map, so its view fits the new route',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        await mount(tester, publish(), size: const Size(800, 3000));
        await findBoth(tester);
        final before = tester.state(routeMap());
        const nearKolar = LatLng(13.2, 78.3);
        tester
            .widget<GoogleMap>(find.descendant(
                of: find.byType(LocationEndpointEditor).at(1),
                matching: find.byType(GoogleMap)))
            .markers
            .single
            .onDragEnd!(nearKolar);
        await tester.pumpAndSettle();
        expect(tester.widget<GoogleMap>(routeMap()).markers.last.position,
            nearKolar);
        expect(identical(tester.state(routeMap()), before), isFalse,
            reason: 'review: the view is fitted only when the map is made');
      });

      testWidgets('after a pin drag, Publish trip waits until the pin has its town name',
          (tester) async {
        final town = Completer<GeocodeOutcome>();
        signInWith(Server(allowed: ownerAllowed));
        await mount(
            tester,
            DriverPublishTripScreen(
                findPlace: (place) async => GeocodeOutcome.ok(
                    place == 'Hoskote' ? hoskote : kolar, '$place, Karnataka'),
                findTown: (_) => town.future),
            size: const Size(800, 3000));
        await findBoth(tester);
        tester
            .widget<GoogleMap>(find.descendant(
                of: find.byType(LocationEndpointEditor).at(1),
                matching: find.byType(GoogleMap)))
            .markers
            .single
            .onDragEnd!(const LatLng(13.2, 78.3));
        await tester.pumpAndSettle();
        FilledButton publish() =>
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publish trip'));
        expect(publish().onPressed, isNull,
            reason: 'review: the old town name could be published with the new pin');
        expect(
            find.descendant(
                of: find.byType(NvActionBar),
                matching: find.text('Updating address from pin…')),
            findsOneWidget,
            reason: 'a disabled button says why');

        town.complete(GeocodeOutcome.ok(const LatLng(13.2, 78.3), 'Malur, Karnataka', 'Malur'));
        await tester.pumpAndSettle();
        expect(publish().onPressed, isNotNull);
      });
    });

    testWidgets('while the trip is being published, From and To cannot change',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      final answered = api.dio.httpClientAdapter as MockApiAdapter;
      final publishAnswer = Completer<ResponseBody>();
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'GET') return answered.handle(request);
        server.sent.add(request);
        return publishAnswer.future;
      });
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async =>
                  GeocodeOutcome.ok(const LatLng(13.07, 77.8), '$place, Karnataka')),
          size: const Size(800, 3000));
      for (final (index, place) in [(0, 'Hoskote'), (1, 'Kolar')]) {
        await tester.enterText(find.byType(TextField).at(index), place);
        await tester.tap(find.byTooltip('Look up place').at(index));
        await tester.pumpAndSettle();
      }
      for (final _ in [1, 2]) {
        await tester.tap(find.text('Choose a date').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
      await tester.enterText(find.byType(TextField).last, '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Publish trip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(server.sent, hasLength(1));

      Finder inPlaceBox(int index, Finder finder) => find.descendant(
          of: find.byType(LocationEndpointEditor).at(index), matching: finder);
      for (final index in [0, 1]) {
        expect(
            tester.widget<TextField>(inPlaceBox(index, find.byType(TextField))).readOnly,
            isTrue,
            reason: 'review: new words dropped the point the publish then read');
        expect(
            tester
                .widget<IconButton>(inPlaceBox(index, find.byType(IconButton)))
                .onPressed,
            isNull);
        expect(
            tester
                .widget<GoogleMap>(inPlaceBox(index, find.byType(GoogleMap)))
                .markers
                .single
                .draggable,
            isFalse);
      }

      publishAnswer.complete(jsonResponse({'error': 'internal_error'}, 500));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(inPlaceBox(0, find.byType(TextField))).readOnly,
          isFalse,
          reason: 'after a failed publish the places can be changed again');
    });

    testWidgets('a place search that finds nothing still opens the map to drag the pin',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.fail('ZERO_RESULTS')),
          size: const Size(800, 3000));
      await tester.enterText(find.byType(TextField).first, 'Kurudumale');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsOneWidget,
          reason: 'without the map, a place Google cannot find could never be set');
      expect(
          find.text(
              'Could not find this place. Try a nearby town, or drag the pin on the map to it.'),
          findsOneWidget);
      expect(find.textContaining('ZERO_RESULTS'), findsNothing,
          reason: 'no raw codes');
    });

    for (final (status, sentence) in [
      (
        'NETWORK',
        'Could not reach the map service. Check your connection, then search again.'
      ),
      (
        'REQUEST_DENIED',
        'Place search is not working right now. Drag the pin on the map to the place.'
      ),
      (
        'OVER_QUERY_LIMIT',
        'Place search is not working right now. Drag the pin on the map to the place.'
      ),
    ]) {
      testWidgets('a search that fails with $status says what went wrong',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        await mount(
            tester,
            DriverPublishTripScreen(
                findPlace: (place) async => GeocodeOutcome.fail(status)),
            size: const Size(800, 3000));
        await tester.enterText(find.byType(TextField).first, 'Hoskote');
        await tester.tap(find.byTooltip('Look up place').first);
        await tester.pumpAndSettle();
        expect(find.text(sentence), findsOneWidget,
            reason: 'tester: the first Hoskote search said it could not find the place');
        expect(find.textContaining('Could not find this place'), findsNothing);
        expect(find.textContaining(status), findsNothing,
            reason: 'no raw codes');
      });
    }

    testWidgets(
        'a found place fills the field with its short name and publishes it as the city',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      const addresses = {
        'hoskote': 'Hoskote, Karnataka 562114, India',
        'kolar': 'Kolar, Karnataka, India',
      };
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.ok(
                  const LatLng(13.07, 77.79), addresses[place.toLowerCase()]!)),
          size: const Size(800, 3000));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'hoskote');
      await tester.tap(find.byTooltip('Look up place').at(0));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), 'kolar');
      await tester.tap(find.byTooltip('Look up place').at(1));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Hoskote');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, 'Kolar');
      expect(find.text('Hoskote, Karnataka 562114, India'), findsOneWidget,
          reason: 'the full address stays visible under the field');

      await tester.tap(find.text('Choose a date').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medium'));
      await tester.enterText(
          find.descendant(
              of: find.widgetWithText(Column, 'Capacity'),
                  matching: find.byType(TextField))
              .first,
          '500');
      await tester.tap(find.widgetWithText(FilledButton, 'Publish trip'));
      await tester.pumpAndSettle();

      final published = server.sent.single.data as Map<String, dynamic>;
      expect(published['originCity'], 'Hoskote',
          reason: 'tester: the lane read "Hoskote, Karnataka 562114, India to Kolar, Karnataka, India"');
      expect(published['destCity'], 'Kolar');
      expect((published['origin'] as Map)['label'], 'Hoskote');
    });

    testWidgets('a found place whose address starts empty keeps what was typed',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async =>
                  GeocodeOutcome.ok(const LatLng(13.07, 77.79), ', Karnataka, India')),
          size: const Size(800, 3000));
      final from = find.byType(TextField).first;
      await tester.enterText(from, 'Hoskote');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(from).controller!.text, 'Hoskote');
    });

    testWidgets(
        'at 360 by 640 with the keyboard open the form scrolls, and Publish and its message are reachable',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await mount(tester, const DriverPublishTripScreen(),
          size: const Size(360, 640));
      const aboveKeyboard = Rect.fromLTWH(0, 0, 360, 340);
      bool shown(Finder finder) {
        final rect = tester.getRect(finder);
        return aboveKeyboard.contains(rect.topLeft) &&
            aboveKeyboard.contains(rect.bottomRight);
      }

      final publish = find.widgetWithText(FilledButton, 'Publish trip');
      expect(shown(publish), isTrue,
          reason: 'the bottom bar sits above the keyboard');

      final form = find.byType(Scrollable).first;
      const lastLine = 'You choose the truck when you accept the first booking.';
      await tester.scrollUntilVisible(find.text(lastLine), 100,
          scrollable: form);
      await tester.pumpAndSettle();
      final room = find.descendant(
          of: find.widgetWithText(Column, 'Capacity'),
          matching: find.byType(TextField));
      expect(shown(room.first), isTrue,
          reason: 'the last field can be reached with the keyboard open');
      expect(tester.state<ScrollableState>(form).position.pixels,
          greaterThan(0));

      await tester.showKeyboard(room.first);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.drag(form, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'dragging the form closes the keyboard');

      await tester.ensureVisible(find.text(lastLine));
      await tester.showKeyboard(room.first);
      await tester.tap(find.text(lastLine));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'a tap outside the fields closes the keyboard');

      await tester.tap(publish);
      await tester.pumpAndSettle();
      final message = find.text(
          'Search for the From place so shippers can find this trip.');
      expect(shown(message), isTrue,
          reason: 'the form scrolls the message into view');
      expect(
          find.descendant(of: find.byType(NvActionBar), matching: message),
          findsNothing,
          reason: 'the bottom bar holds only Publish trip');
      expect(server.sent, isEmpty);
    });
  });
}
