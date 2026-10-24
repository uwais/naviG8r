// The driver bugs the 23 Oct 2026 hunt confirmed (D1 to D12), each on the screens as a driver uses them.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/pod_photo_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'support/app_lifecycle.dart';
import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

const sharedLine =
    'Shippers see your location while this screen is open.';
const locationOffLine =
    'Location is off, so shippers cannot see the truck. Turn it on in your phone settings.';
const noLongerYours =
    'This trip is no longer yours. Go back to Trips and tap Refresh.';

final somewhere = Position(
    latitude: 12.97,
    longitude: 77.59,
    timestamp: DateTime(2026, 10, 22),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0);

/// A phone that allows location. [switchedOn] is the phone setting; each stream the screen listens to is kept.
class PhoneLocation extends GeolocatorPlatform {
  bool switchedOn = true;
  final streams = <StreamController<Position>>[];
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<bool> isLocationServiceEnabled() async => switchedOn;
  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    if (!switchedOn) throw const LocationServiceDisabledException();
    return somewhere;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final positions = StreamController<Position>();
    streams.add(positions);
    return positions.stream;
  }
}

final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

/// The driver's trip screen for trip-a, whose status the server answers with [status] each time it is asked.
Future<PhoneLocation> mountDriverTrip(
    WidgetTester tester, String Function() status) async {
  final location = PhoneLocation();
  GeolocatorPlatform.instance = location;
  signInAsCarrierLogin(
      office: false, alsoAllowed: ['load.status_update', 'pod.upload']);
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    if (request.path == '/v1/pilot/anchor-trips/trip-a') {
      return jsonResponse({
        'trip': {
          'id': 'trip-a',
          'status': status(),
          'assignedTruckNumber': 'KA01AB1234',
          'assignedDriverUserId': 'carrier-person',
        }
      });
    }
    if (request.path.endsWith('/location')) return jsonResponse({});
    return jsonResponse({
      'shipments': [shipmentOnTripA(status: 'BOOKED')]
    });
  });
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(body: DriverActiveTripScreen(tripId: 'trip-a'))));
  await tester.pumpAndSettle();
  return location;
}

/// The trip screen in progress, then location switched off on the phone, which stops the stream.
Future<PhoneLocation> mountWithLocationTurnedOff(WidgetTester tester) async {
  final location = await mountDriverTrip(tester, () => 'IN_PROGRESS');
  expect(location.streams, hasLength(1));
  location.switchedOn = false;
  location.streams.single.addError(const LocationServiceDisabledException());
  await tester.pumpAndSettle();
  expect(find.text(locationOffLine), findsOneWidget);
  return location;
}

CarrierServer signInAsDriverWithBooking(
        {String tripStatus = 'IN_PROGRESS',
        String bookingStatus = 'BOOKED',
        Map<String, dynamic>? bill,
        List<String> photoIds = const []}) =>
    signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-today', status: tripStatus)],
      bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles',
            drop: 'Guindy, Chennai',
            status: bookingStatus,
            bill: bill,
            photoIds: photoIds)
      ],
    ));

void main() {
  testWidgets(
      'D1: a trip started from another phone starts sharing on the 15 second check',
      (tester) async {
    var status = 'OPEN';
    final location = await mountDriverTrip(tester, () => status);
    expect(location.streams, isEmpty);
    status = 'IN_PROGRESS';
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text(sharedLine), findsOneWidget);
    expect(location.streams, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'D2: a driver cannot confirm delivery before the trip starts, as the office cannot',
      (tester) async {
    signInAsDriverWithBooking(tripStatus: 'OPEN');
    await mountCarrierApp(tester, '/driver/shipment/guindy',
        size: const Size(400, 1600));
    final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
    expect(
        confirm.evaluate().isEmpty ||
            tester.widget<FilledButton>(confirm).onPressed == null,
        isTrue);
  });

  testWidgets('D2: once the trip is on the way the driver can confirm delivery',
      (tester) async {
    signInAsDriverWithBooking();
    await mountCarrierApp(tester, '/driver/shipment/guindy',
        size: const Size(400, 1600));
    final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
  });

  testWidgets(
      'D3: location turned off and on again starts sharing again on the 15 second check',
      (tester) async {
    final location = await mountWithLocationTurnedOff(tester);
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(location.streams, hasLength(1),
        reason: 'still off: nothing to listen to yet');
    expect(find.text(locationOffLine), findsOneWidget);

    location.switchedOn = true;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(location.streams, hasLength(2));
    expect(find.text(locationOffLine), findsNothing);
    expect(find.text(sharedLine), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'D3: location turned on again while the app was away starts sharing when it comes back',
      (tester) async {
    final location = await mountWithLocationTurnedOff(tester);
    await sendAppToBackground(tester);
    location.switchedOn = true;
    await bringAppBack(tester);
    await tester.pumpAndSettle();
    expect(location.streams, hasLength(2));
    expect(find.text(locationOffLine), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'D4: removing a photo the server no longer has says so and shows the photos the server has',
      (tester) async {
    final realPicker = pickPodPhoto;
    addTearDown(() => pickPodPhoto = realPicker);
    pickPodPhoto = (_) async => jpeg;
    final carrier = signInAsDriverWithBooking();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path.contains('/pod-photos')) {
        if (request.method == 'DELETE') {
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
    expect(find.text('That photo was already removed.'), findsOneWidget);
    expect(find.text(noLongerYours), findsNothing);
    expect(find.text('Photo added'), findsNothing,
        reason: 'the server lists no photo for this delivery');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm delivery'))
            .onPressed,
        isNull);
  });

  testWidgets(
      'D4: a Remove the server refuses for another reason shows the photos the server has',
      (tester) async {
    final carrier = signInAsDriverWithBooking(photoIds: ['p1', 'p2']);
    var removed = false;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.method == 'DELETE') {
        // The first photo was removed from another phone; this delete is refused.
        carrier.bookings.single['podPhotos'] = podPhotos(['p2']);
        removed = true;
        return jsonResponse({'error': 'pod_photos_closed'}, 409);
      }
      return carrier.answer(request);
    });
    await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
        size: const Size(400, 1600));
    expect(find.text('2 photos added'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(removed, isTrue);
    expect(find.text('This delivery can no longer change its photos.'),
        findsOneWidget);
    expect(find.text('Photo added'), findsOneWidget);
  });

  testWidgets(
      'D5: the proof of delivery screen for a delivery already confirmed says so and holds Confirm',
      (tester) async {
    signInAsDriverWithBooking(
        bookingStatus: 'PENDING_RELEASE', photoIds: ['p1']);
    await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
        size: const Size(400, 1600));
    expect(find.text('Delivery already confirmed.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm delivery'))
            .onPressed,
        isNull);
  });

  test('D5: the server code for a delivery that cannot be confirmed reads plainly',
      () {
    api = Api('http://test');
    final request = RequestOptions(path: '/shipments/guindy/driver-pod');
    final refusal = DioException(
        requestOptions: request,
        response: Response(
            requestOptions: request,
            statusCode: 400,
            data: {
              'error': 'shipment_not_deliverable',
              'status': 'PENDING_RELEASE'
            }));
    expect(formatApiError(refusal), 'Delivery already confirmed.');
  });

  testWidgets('D8: a second tap while the camera is opening is ignored',
      (tester) async {
    final realPicker = pickPodPhoto;
    addTearDown(() => pickPodPhoto = realPicker);
    final firstPick = Completer<Uint8List?>();
    var picks = 0;
    pickPodPhoto = (ImageSource source) {
      picks++;
      if (picks == 1) return firstPick.future;
      // image_picker refuses a second pick while one is open.
      throw Exception('already_active');
    };
    var uploads = 0;
    final carrier = signInAsDriverWithBooking();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path.contains('/pod-photos')) {
        uploads++;
        return jsonResponse({
          'photo': {'id': 'photo-1', 'contentType': 'image/jpeg'}
        }, 201);
      }
      return carrier.answer(request);
    });
    await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
        size: const Size(400, 1600));
    await tester.tap(find.text('Take photo'));
    await tester.pump();
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    firstPick.complete(jpeg);
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(uploads, 1);
    expect(find.text('Photo added'), findsOneWidget);
    expect(find.textContaining('Could not open'), findsNothing);
  });

  testWidgets(
      'D9: the driver e-way bills screen marks a bill whose valid-until time has passed',
      (tester) async {
    signInAsDriverWithBooking(bill: {
      'kind': 'BILL',
      'billNumber': '341200987654',
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    await mountCarrierApp(tester, '/driver/trip/trip-today/eway-bills',
        size: const Size(400, 1600));
    expect(find.text('Valid-until time has passed. Call your office.'),
        findsOneWidget);
  });

  testWidgets('D10: the driver booking screen says On the way once the trip starts',
      (tester) async {
    signInAsDriverWithBooking();
    await mountCarrierApp(tester, '/driver/shipment/guindy',
        size: const Size(400, 1600));
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Accepted'), findsNothing);
  });

  testWidgets(
      'D12: Remove and Take photo are not on offer while Confirm delivery is sending',
      (tester) async {
    final answer = Completer<ResponseBody>();
    final carrier = signInAsDriverWithBooking(photoIds: ['p1']);
    api.dio.httpClientAdapter = MockApiAdapter((request) async =>
        request.path.endsWith('/driver-pod')
            ? await answer.future
            : carrier.answer(request));
    await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
        size: const Size(400, 1600));
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
    await tester.pump();
    expect(find.text('Remove'), findsNothing);
    expect(find.text('Take photo'), findsNothing);
    expect(find.text('Choose from gallery'), findsNothing);
    answer.complete(jsonResponse({'shipment': carrier.bookings.single}));
    await tester.pumpAndSettle();
  });
}
