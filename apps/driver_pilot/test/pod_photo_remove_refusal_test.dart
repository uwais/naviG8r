// R2, bug-hunt batch 2: a driver's Remove answered 404 said "That photo was already removed." even when the 404
// meant the office had given the trip to someone else. The photo is said to be gone only when the server still
// lists the delivery without it.
import 'dart:typed_data';

import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/pod_photo_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/mock_api.dart';

final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
const _noLongerYours =
    'This trip is no longer yours. Go back to Trips and tap Refresh.';

void main() {
  testWidgets(
      'R2 a 404 on Remove after the trip was given away says the trip is no longer yours',
      (tester) async {
    final realPicker = pickPodPhoto;
    addTearDown(() => pickPodPhoto = realPicker);
    pickPodPhoto = (_) async => _jpeg;
    final carrier = signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-today', status: 'IN_PROGRESS')],
      bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles', drop: 'Guindy, Chennai')
      ],
    ));
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path.contains('/pod-photos')) {
        if (request.method == 'DELETE') {
          // The office gave the trip to another driver: this login no longer sees the delivery.
          carrier.bookings.clear();
          return jsonResponse({'error': 'not_found'}, 404);
        }
        return jsonResponse({
          'photo': {'id': 'photo-1', 'contentType': 'image/jpeg'}
        }, 201);
      }
      return carrier.answer(request);
    });
    await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
        size: const Size(400, 1600));
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(find.text('Photo added'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text(_noLongerYours), findsOneWidget);
    expect(find.text('That photo was already removed.'), findsNothing);
  });
}
