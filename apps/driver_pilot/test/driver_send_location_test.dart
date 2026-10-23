// Send my location now on a trip in transit: only on the phone in the truck, sent at once whatever the
// 30 seconds between automatic sends, and a plain line when location is off.
import 'dart:async';

import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_fixtures.dart';
import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

const sendNow = 'Send my location now';
const locationOff =
    'Location is off. Turn it on in your phone settings to share it.';

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

/// Stands in for the phone's location service. By default location is allowed and the phone knows where it is.
class PhoneLocation extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;

  /// False stands for location switched off in the phone's settings.
  bool switchedOn = true;
  int positionsAsked = 0;
  final streams = <StreamController<Position>>[];

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positionsAsked++;
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

/// The server as a trip in transit driven by [driver], keeping every position the phone sends.
List<Object?> answerWithTripInTransit({String driver = 'carrier-person'}) {
  final positionsSent = <Object?>[];
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    switch (request.path) {
      case '/v1/pilot/anchor-trips/trip-a':
        return jsonResponse({
          'trip': {
            'id': 'trip-a',
            'status': 'IN_PROGRESS',
            'assignedVehicleId': 'vehicle-1',
            'assignedTruckNumber': 'KA01AB1234',
            'assignedDriverUserId': driver,
          }
        });
      case '/v1/pilot/anchor-trips/trip-a/location':
        positionsSent.add(request.data);
        return jsonResponse(<String, Object>{});
    }
    return jsonResponse({
      'shipments': [shipmentOnTripA(status: 'PENDING_RELEASE')]
    });
  });
  return positionsSent;
}

Future<void> mountTripScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(body: DriverActiveTripScreen(tripId: 'trip-a'))));
  await tester.pumpAndSettle();
}

void main() {
  late PhoneLocation location;

  setUp(() {
    signInAsShipper();
    location = PhoneLocation();
    GeolocatorPlatform.instance = location;
    // 10:10 UTC is 15:40 in India.
    currentTime = () => DateTime.utc(2026, 10, 22, 10, 10);
  });

  tearDown(() => currentTime = DateTime.now);

  testWidgets(
      'a driver on a trip in transit has the button by the location sentence',
      (tester) async {
    signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
    answerWithTripInTransit();
    await mountTripScreen(tester);
    expect(
        find.text('Shippers see your location while this trip is on the way.'),
        findsOneWidget);
    expect(find.text(sendNow), findsOneWidget);
    expect(find.text(locationOff), findsNothing);
  });

  testWidgets(
      'an office phone on a trip in transit has no button and sends nothing',
      (tester) async {
    signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
    final positionsSent = answerWithTripInTransit(driver: 'driver-1');
    await mountTripScreen(tester);
    expect(find.text(sendNow), findsNothing,
        reason: "an office phone is not where the truck is");
    expect(location.positionsAsked, 0);
    expect(positionsSent, isEmpty);
  });

  testWidgets('an owner who drives the trip has the button', (tester) async {
    signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
    answerWithTripInTransit();
    await mountTripScreen(tester);
    expect(find.text(sendNow), findsOneWidget);
  });

  testWidgets(
      'a tap sends a fresh position at once, inside the 30 seconds, and shows the time in India',
      (tester) async {
    signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
    final positionsSent = answerWithTripInTransit();
    await mountTripScreen(tester);
    location.streams.single.add(somewhere);
    await tester.pumpAndSettle();
    expect(positionsSent, hasLength(1), reason: 'the automatic send');
    final positionsAskedBefore = location.positionsAsked;

    await tester.tap(find.text(sendNow));
    await tester.pumpAndSettle();
    expect(location.positionsAsked, positionsAskedBefore + 1,
        reason: 'a fresh position, not the last one kept');
    expect(positionsSent, hasLength(2),
        reason: 'the tap does not wait out the 30 seconds');
    expect(positionsSent.last, containsPair('lat', 12.97));
    expect(find.text('Location sent at 15:40 IST'), findsOneWidget);
  });

  testWidgets(
      'location refused: the line shows on load, and a tap sends nothing',
      (tester) async {
    location.permission = LocationPermission.deniedForever;
    signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
    final positionsSent = answerWithTripInTransit();
    await mountTripScreen(tester);
    expect(find.text(locationOff), findsOneWidget,
        reason: 'the automatic sharing says so instead of failing silently');

    await tester.tap(find.text(sendNow));
    await tester.pumpAndSettle();
    expect(find.text(locationOff), findsOneWidget);
    expect(positionsSent, isEmpty);
    expect(find.textContaining('Location sent'), findsNothing);
  });

  testWidgets(
      'location switched off in settings: the line shows, and a tap sends nothing',
      (tester) async {
    location.switchedOn = false;
    signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
    final positionsSent = answerWithTripInTransit();
    await mountTripScreen(tester);
    expect(find.text(locationOff), findsOneWidget);

    await tester.tap(find.text(sendNow));
    await tester.pumpAndSettle();
    expect(find.text(locationOff), findsOneWidget);
    expect(positionsSent, isEmpty);
  });

  testWidgets(
      'location turned on after the screen loaded: a tap sends, and automatic sharing starts',
      (tester) async {
    location.permission = LocationPermission.denied;
    signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
    final positionsSent = answerWithTripInTransit();
    await mountTripScreen(tester);
    expect(find.text(locationOff), findsOneWidget);
    expect(location.streams, isEmpty);

    location.permission = LocationPermission.whileInUse;
    await tester.tap(find.text(sendNow));
    await tester.pumpAndSettle();
    expect(positionsSent, hasLength(1));
    expect(find.text(locationOff), findsNothing);
    expect(find.text('Location sent at 15:40 IST'), findsOneWidget);
    expect(location.streams, hasLength(1),
        reason: 'the sentence says shippers see the location, so it is sent');
  });
}
