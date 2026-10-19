// Place search on Publish: each failure is named for what it was, and a found place has a short name.
import 'package:dio/dio.dart';
import 'package:driver_pilot/google_geocoding.dart';
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
      final address = await GoogleGeocodingService.reverseLatLng(
          const LatLng(13.07, 77.79),
          apiKey: 'test-key');
      expect(asked!.queryParameters['result_type'], 'locality');
      expect(placeNameFromAddress(address), 'Hoskote');
    });
  });
}
