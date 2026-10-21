// Place search on Publish: each failure is named for what it was, and a found place has a short name.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';

void answerWith(ResponseBody Function(RequestOptions request) handle) {
  GoogleGeocodingService.dio.httpClientAdapter = MockApiAdapter(handle);
}

Future<PlaceSearchFailure?> searchFailure() async =>
    (await GoogleGeocodingService.forwardAddress('Hoskote', apiKey: 'test-key'))
        .failure;

void main() {
  final realAdapter = GoogleGeocodingService.dio.httpClientAdapter;
  tearDown(() => GoogleGeocodingService.dio.httpClientAdapter = realAdapter);

  group('forwardAddress names the failure', () {
    test('no match is not found', () async {
      answerWith((_) => jsonResponse({'status': 'ZERO_RESULTS', 'results': []}));
      expect(await searchFailure(), PlaceSearchFailure.notFound);
    });

    test('a timeout is could not reach', () async {
      answerWith((request) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 12), requestOptions: request));
      expect(await searchFailure(), PlaceSearchFailure.unreachable);
    });

    test('no connection is could not reach', () async {
      answerWith((request) => throw DioException.connectionError(
          requestOptions: request, reason: 'Failed host lookup'));
      expect(await searchFailure(), PlaceSearchFailure.unreachable);
    });

    test('an HTTP error code is could not reach', () async {
      answerWith((_) => jsonResponse({'error': 'unavailable'}, 503));
      expect(await searchFailure(), PlaceSearchFailure.unreachable);
    });

    for (final status in ['REQUEST_DENIED', 'OVER_QUERY_LIMIT', 'OVER_DAILY_LIMIT']) {
      test('$status is not working', () async {
        answerWith((_) => jsonResponse({'status': status, 'results': []}));
        expect(await searchFailure(), PlaceSearchFailure.notWorking);
      });
    }

    test('no key is not working, and nothing is sent', () async {
      var asked = false;
      answerWith((_) {
        asked = true;
        return jsonResponse({});
      });
      final outcome = await GoogleGeocodingService.forwardAddress('Hoskote', apiKey: '');
      expect(outcome.failure, PlaceSearchFailure.notWorking);
      expect(asked, isFalse);
    });

    test('nothing typed is its own failure', () async {
      final outcome =
          await GoogleGeocodingService.forwardAddress('  ', apiKey: 'test-key');
      expect(outcome.failure, PlaceSearchFailure.nothingTyped);
    });

    test('a found place has no failure', () async {
      answerWith((_) => jsonResponse({
            'status': 'OK',
            'results': [
              {
                'formatted_address': 'Hoskote, Karnataka 562114, India',
                'geometry': {
                  'location': {'lat': 13.07, 'lng': 77.79}
                },
              }
            ],
          }));
      final outcome =
          await GoogleGeocodingService.forwardAddress('Hoskote', apiKey: 'test-key');
      expect(outcome.isOk, isTrue);
      expect(outcome.failure, isNull);
    });
  });

  group('place names', () {
    test('the first part of the address', () {
      expect(placeNameFromAddress('Hoskote, Karnataka 562114, India'), 'Hoskote');
      expect(placeNameFromAddress('Kolar, Karnataka, India'), 'Kolar');
      expect(placeNameFromAddress('Hoskote'), 'Hoskote');
    });

    test('an empty first part gives no name', () {
      expect(placeNameFromAddress(', Karnataka, India'), isNull);
      expect(placeNameFromAddress(''), isNull);
      expect(placeNameFromAddress(null), isNull);
    });

    test('a dragged pin asks for its town, so the name is not a house number',
        () async {
      RequestOptions? asked;
      answerWith((request) {
        asked = request;
        return jsonResponse({
          'status': 'OK',
          'results': [
            {'formatted_address': 'Hoskote, Karnataka 562114, India'}
          ],
        });
      });
      final town = await GoogleGeocodingService.reverseLatLng(
          const LatLng(13.07, 77.79),
          apiKey: 'test-key');
      expect(asked!.queryParameters['result_type'], 'locality');
      expect(town.placeName, 'Hoskote');
    });

    test('a pin with no town comes back as not found', () async {
      answerWith((_) => jsonResponse({'status': 'ZERO_RESULTS', 'results': []}));
      final town = await GoogleGeocodingService.reverseLatLng(
          const LatLng(13.2, 78.1),
          apiKey: 'test-key');
      expect(town.isOk, isFalse);
      expect(town.placeName, isNull);
    });

    test('a typed road address takes its town, not the road', () async {
      answerWith((_) => jsonResponse({
            'status': 'OK',
            'results': [
              {
                'formatted_address': 'NH 75, Hoskote, Karnataka 562114, India',
                'address_components': [
                  {
                    'long_name': 'NH 75',
                    'types': ['route']
                  },
                  {
                    'long_name': 'Hoskote',
                    'types': ['locality', 'political']
                  },
                ],
                'geometry': {
                  'location': {'lat': 13.07, 'lng': 77.79}
                },
              }
            ],
          }));
      final outcome = await GoogleGeocodingService.forwardAddress(
          'NH 75 Hoskote',
          apiKey: 'test-key');
      expect(outcome.placeName, 'Hoskote',
          reason: 'reviewer: a road address made the city name "NH 75"');
    });
  });

  group('the place editor', () {
    Future<TextEditingController> mountEditor(WidgetTester tester,
        {PlaceFinder? findPlace,
        required PinNamer namePin,
        VoidCallback? onPinStale}) async {
      final field = TextEditingController();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LocationEndpointEditor(
        title: 'From',
        hint: 'City or area',
        labelController: field,
        markerId: 'from',
        markerHue: BitmapDescriptor.hueOrange,
        position: const LatLng(13.07, 77.79),
        onPositionChanged: (_) {},
        onPinStale: onPinStale,
        findPlace: findPlace ?? (place) async => GeocodeOutcome.fail('ZERO_RESULTS'),
        namePin: namePin,
      )))));
      return field;
    }

    Future<void> dragPin(WidgetTester tester) async {
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.markers.single.onDragEnd!(const LatLng(13.2, 78.1));
      await tester.pumpAndSettle();
    }

    testWidgets('a pin dragged to a spot with no town drops the old name and asks for one',
        (tester) async {
      final field = await mountEditor(tester,
          namePin: (point) async => GeocodeOutcome.fail('ZERO_RESULTS'));
      field.text = 'Hoskote';
      await dragPin(tester);
      expect(field.text, isEmpty,
          reason: 'reviewer: the trip was published as Hoskote at a village 30 km away');
      expect(
          find.text('Could not name the place at the pin. Type its name above.'),
          findsOneWidget);
      expect(find.textContaining('ZERO_RESULTS'), findsNothing,
          reason: 'no raw codes');
    });

    testWidgets('a pin dragged to a town takes its name, with the address below',
        (tester) async {
      final field = await mountEditor(tester,
          namePin: (point) async =>
              GeocodeOutcome.ok(point, 'Kolar, Karnataka, India', 'Kolar'));
      field.text = 'Hoskote';
      await dragPin(tester);
      expect(field.text, 'Kolar');
      expect(find.text('Kolar, Karnataka, India'), findsOneWidget);
    });

    testWidgets('a pin dragged where the town lookup fails keeps the name and asks to check it',
        (tester) async {
      final field = await mountEditor(tester,
          namePin: (point) async => GeocodeOutcome.fail('NETWORK'));
      field.text = 'Hoskote';
      await dragPin(tester);
      expect(field.text, 'Hoskote',
          reason: 'reviewer: a dropped connection emptied a name that may still be right');
      expect(
          find.text('Could not check the place name at the pin. Make sure it is still right.'),
          findsOneWidget);
    });

    testWidgets('a slow town lookup does not overwrite a newer drag', (tester) async {
      final answers = <Completer<GeocodeOutcome>>[];
      final field = await mountEditor(tester, namePin: (point) {
        answers.add(Completer<GeocodeOutcome>());
        return answers.last.future;
      });
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.markers.single.onDragEnd!(const LatLng(13.2, 78.1));
      map.markers.single.onDragEnd!(const LatLng(13.1, 78.2));
      answers[1].complete(GeocodeOutcome.ok(const LatLng(13.1, 78.2), 'Kolar, Karnataka, India', 'Kolar'));
      await tester.pumpAndSettle();
      answers[0].complete(GeocodeOutcome.ok(const LatLng(13.2, 78.1), 'Malur, Karnataka, India', 'Malur'));
      await tester.pumpAndSettle();
      expect(field.text, 'Kolar',
          reason: 'reviewer: the first drag answered last and put back the town the pin had left');
      expect(find.text('Kolar, Karnataka, India'), findsOneWidget);
    });

    testWidgets('a slow town lookup does not overwrite a newer search', (tester) async {
      final answer = Completer<GeocodeOutcome>();
      final field = await mountEditor(tester,
          findPlace: (place) async =>
              GeocodeOutcome.ok(const LatLng(13.0, 77.8), 'Hoskote, Karnataka, India', 'Hoskote'),
          namePin: (point) => answer.future);
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      map.markers.single.onDragEnd!(const LatLng(13.2, 78.1));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Hoskote');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pumpAndSettle();
      answer.complete(GeocodeOutcome.ok(const LatLng(13.2, 78.1), 'Malur, Karnataka, India', 'Malur'));
      await tester.pumpAndSettle();
      expect(field.text, 'Hoskote');
      expect(find.text('Updating address from pin…'), findsNothing);
    });

    testWidgets('a slow search does not overwrite a newer drag', (tester) async {
      final searched = Completer<GeocodeOutcome>();
      final field = await mountEditor(tester,
          findPlace: (place) => searched.future,
          namePin: (point) async =>
              GeocodeOutcome.ok(point, 'Kolar, Karnataka, India', 'Kolar'));
      await tester.enterText(find.byType(TextField), 'Hoskote');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pump();
      // Pumped by hand: the search's spinner never settles while it waits.
      tester.widget<GoogleMap>(find.byType(GoogleMap)).markers.single.onDragEnd!(const LatLng(13.2, 78.1));
      await tester.pump();
      await tester.pump();
      searched.complete(
          GeocodeOutcome.ok(const LatLng(13.0, 77.8), 'Hoskote, Karnataka, India', 'Hoskote'));
      await tester.pumpAndSettle();
      expect(field.text, 'Kolar',
          reason: 'review: a search answering after a drag put its town back over the dragged pin');
      expect(tester.widget<GoogleMap>(find.byType(GoogleMap)).markers.single.position,
          const LatLng(13.2, 78.1));
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the overtaken search leaves no spinner behind');
    });

    testWidgets('new words after a search make the found pin stale', (tester) async {
      var stale = 0;
      final field = await mountEditor(tester,
          findPlace: (place) async => GeocodeOutcome.ok(
              const LatLng(13.0, 77.8), 'Hoskote, Karnataka, India', 'Hoskote'),
          namePin: (point) async => GeocodeOutcome.fail('NO_API_KEY'),
          onPinStale: () => stale++);
      await tester.enterText(find.byType(TextField), 'hoskote');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pumpAndSettle();
      expect(field.text, 'Hoskote');
      expect(stale, 0, reason: 'the search names the place it found');
      await tester.enterText(find.byType(TextField), 'Hoskote ');
      await tester.pumpAndSettle();
      expect(stale, 0, reason: 'a space at the end is the same words');

      await tester.enterText(find.byType(TextField), 'Kolar');
      await tester.pumpAndSettle();
      expect(stale, 1,
          reason: 'reviewer: the Hoskote pin stayed under the name Kolar');
      expect(find.text('Hoskote, Karnataka, India'), findsNothing,
          reason: 'the address of the old pin goes with it');
    });

    testWidgets('after a drag to a spot with no town, typing its name keeps the pin',
        (tester) async {
      var stale = 0;
      final field = await mountEditor(tester,
          namePin: (point) async => GeocodeOutcome.fail('ZERO_RESULTS'),
          onPinStale: () => stale++);
      await dragPin(tester);
      expect(field.text, isEmpty);
      await tester.enterText(find.byType(TextField), 'Malur');
      await tester.pumpAndSettle();
      expect(stale, 0,
          reason: 'the field asked for the name of the place at the pin');
    });

    testWidgets('without a maps key a dragged pin keeps the name typed by hand',
        (tester) async {
      final field = await mountEditor(tester,
          namePin: (point) async => GeocodeOutcome.fail('NO_API_KEY'));
      field.text = 'Hoskote';
      await dragPin(tester);
      expect(field.text, 'Hoskote');
    });

    testWidgets('a search message is read out by a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await mountEditor(tester,
          findPlace: (place) async => GeocodeOutcome.fail('NETWORK'),
          namePin: (point) async => GeocodeOutcome.fail('NO_API_KEY'));
      await tester.enterText(find.byType(TextField), 'Hoskote');
      await tester.tap(find.byTooltip('Search for place'));
      await tester.pumpAndSettle();
      const sentence =
          'Could not reach the map service. Check your connection, then search again.';
      expect(tester.getSemantics(find.text(sentence)),
          containsSemantics(label: sentence, isLiveRegion: true),
          reason: 'reviewer: the message appeared in a plain Text and was not announced');
      handle.dispose();
    });
  });
}
