// A driver's screens once the server's answer has changed under them: a trip given to someone else since they
// opened it, an owner's phone once they no longer drive the trip, and the shipment screen after Confirm delivery.
import 'dart:async';

import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_fixtures.dart';
import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

const tripNoLongerYours =
    'This trip is no longer yours. Go back to Trips and tap Refresh.';

const notOnYourTrip =
    'This booking is no longer on your trip. Go back to Trips and tap Refresh.';

/// Stands in for the phone's location service, which a widget test does not have. Location is allowed, no
/// one-off position comes back, and each time the trip screen listens for positions it gets a stream of its own.
class FakeLocationService extends GeolocatorPlatform {
  final streams = <StreamController<Position>>[];

  /// While a test holds this, the phone has not yet answered where it is now.
  Completer<void>? positionHeld;

  /// Each handler the trip screen listens with. Calling one hands the screen a position that was
  /// already on its way when sharing stopped.
  final positionHandlers = <void Function(Position)>[];

  /// The trip screen shares the location while it listens for positions.
  bool get sharing => streams.any((positions) => positions.hasListener);

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    await positionHeld?.future;
    throw TimeoutException('A widget test has no position.');
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final positions = StreamController<Position>();
    streams.add(positions);
    return _KeepsHandler(positions.stream, positionHandlers.add);
  }
}

/// A stream of positions that also gives each listener's handler to [keep].
class _KeepsHandler extends StreamView<Position> {
  _KeepsHandler(super.stream, this.keep);
  final void Function(void Function(Position)) keep;

  @override
  StreamSubscription<Position> listen(void Function(Position)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    if (onData != null) keep(onData);
    return super.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

/// A refresh needs a pull of a quarter of the list's height, and this test screen is 3000 pixels tall.
Future<void> pullDown(WidgetTester tester) async {
  await tester.fling(find.byType(ListView), const Offset(0, 1200), 1000);
  await tester.pumpAndSettle();
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

/// A driver of an approved carrier, so Accept, Start and Confirm delivery are on offer.
void signInAsApprovedDriver() => signInAsCarrierLogin(
    office: false,
    alsoAllowed: ['carrier.offer_accept', 'load.status_update', 'pod.upload']);

const tripInProgress = {
  'trip': {'id': 'trip-a', 'status': 'IN_PROGRESS'}
};

void main() {
  late FakeLocationService location;

  setUp(() {
    signInAsShipper();
    location = FakeLocationService();
    GeolocatorPlatform.instance = location;
  });

  group('A driver whose trip was given to someone else', () {
    testWidgets(
        'is told a shipment no longer listed is not on their trip, instead of a spinner',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      api.dio.httpClientAdapter =
          MockApiAdapter((_) => jsonResponse({'shipments': <Object>[]}));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text(notOnYourTrip), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsNothing,
          reason: 'trying again would ask the same list');
    });

    testWidgets(
        'the office keeps its usual sentence and Try again for a shipment no longer listed',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((_) => jsonResponse({'shipments': <Object>[]}));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Could not load this booking.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets(
        'a shipment that leaves their list after Accept is replaced by the sentence, not kept on screen',
        (tester) async {
      signInAsApprovedDriver();
      var accepted = false;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'POST') {
          accepted = true;
          return jsonResponse(<String, Object>{});
        }
        return jsonResponse({
          'shipments': accepted
              ? <Object>[]
              : [shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT')]
        });
      });
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      await tester.tap(find.text('Accept booking'));
      await tester.pumpAndSettle();
      expect(find.text(notOnYourTrip), findsOneWidget);
      expect(find.text('Accept booking'), findsNothing,
          reason: 'the stale screen is gone');
    });

    testWidgets('is told the trip is no longer theirs when Accept answers 404',
        (tester) async {
      signInAsApprovedDriver();
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => request.method == 'POST'
              ? jsonResponse({'error': 'not_found'}, 404)
              : jsonResponse({
                  'shipments': [
                    shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT')
                  ]
                }));
      // Accept is on the booking screen since the redesign (PR 6), not on the list.
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      await tester.tap(find.widgetWithText(FilledButton, 'Accept booking'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget);
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets('when Start answers 404, only the sentence is left on screen',
        (tester) async {
      signInAsApprovedDriver();
      // The server refuses the trip itself from then on, as it does the start.
      var refused = false;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'POST') {
          refused = true;
          return jsonResponse({'error': 'not_found'}, 404);
        }
        if (request.path == '/v1/pilot/anchor-trips/trip-a') {
          return refused
              ? jsonResponse({'error': 'not_found'}, 404)
              : jsonResponse({
                  'trip': {'id': 'trip-a', 'status': 'OPEN'}
                });
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA()]
        });
      });
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await tester.tap(find.text('Start trip'));
      await tester.pumpAndSettle();
      // PR 7: Start opens the confirm sheet first; its Start trip sends the request.
      expect(refused, isFalse, reason: 'nothing is sent before the sheet');
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Start trip')));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget,
          reason: 'on screen, with no snack bar repeating it');
      for (final stale in ['Ready to start', 'Start trip', 'Show e-way bills']) {
        expect(find.text(stale), findsNothing, reason: stale);
      }
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets(
        'when Complete trip answers 404, only the sentence is left and location sharing stops',
        (tester) async {
      // PR 8: Complete trip shows only to a login that may change a trip's status, as every driver may.
      signInAsApprovedDriver();
      var refused = false;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'POST') {
          refused = true;
          return jsonResponse({'error': 'not_found'}, 404);
        }
        if (request.path == '/v1/pilot/anchor-trips/trip-a') {
          return refused
              ? jsonResponse({'error': 'not_found'}, 404)
              : jsonResponse(tripInProgress);
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA(status: 'PENDING_RELEASE')]
        });
      });
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(location.streams, hasLength(1),
          reason: 'opening the screen listens for positions once');
      expect(location.sharing, isTrue);

      await tester.tap(find.text('Complete trip'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget,
          reason: 'on screen, with no snack bar repeating it');
      expect(find.text('On the way'), findsNothing);
      expect(location.sharing, isFalse);
    });

    testWidgets(
        'a trip that answers 404 on a pull-down shows only the sentence and stops sharing; once given back, a pull-down shares again',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      var tripRequests = 0;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.path == '/v1/pilot/anchor-trips/trip-a') {
          tripRequests++;
          // Given to someone else before the second load, and given back before the third.
          if (tripRequests == 2) {
            return jsonResponse({'error': 'not_found'}, 404);
          }
          return jsonResponse(tripInProgress);
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA(status: 'PENDING_RELEASE')]
        });
      });
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      const gpsLine =
          'Shippers see your location while this app is open.';
      expect(find.text('On the way'), findsOneWidget);
      expect(find.text(gpsLine), findsOneWidget);
      expect(location.sharing, isTrue);

      await pullDown(tester);
      expect(find.text(tripNoLongerYours), findsOneWidget);
      for (final stale in [
        'On the way',
        'Show e-way bills',
        gpsLine,
        'Truck and driver'
      ]) {
        expect(find.text(stale), findsNothing, reason: stale);
      }
      expect(find.textContaining('Status:'), findsNothing);
      expect(location.sharing, isFalse);

      await pullDown(tester);
      expect(find.text('On the way'), findsOneWidget,
          reason: 'pulling down asks again');
      expect(location.streams, hasLength(2),
          reason: 'listening again after the give-back');
      expect(location.sharing, isTrue);
    });

    testWidgets(
        'sharing does not switch on behind the sentence when the trip goes while the phone is still finding its position',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      location.positionHeld = Completer<void>();
      var tripRequests = 0;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.path == '/v1/pilot/anchor-trips/trip-a') {
          tripRequests++;
          return tripRequests == 1
              ? jsonResponse(tripInProgress)
              : jsonResponse({'error': 'not_found'}, 404);
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA(status: 'PENDING_RELEASE')]
        });
      });
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await pullDown(tester);
      expect(find.text(tripNoLongerYours), findsOneWidget);

      location.positionHeld!.complete();
      await tester.pumpAndSettle();
      expect(location.streams, isEmpty,
          reason: 'the phone answered after the trip was given away');
    });

    testWidgets('is told the trip is no longer theirs when it answers 404',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.path == '/v1/pilot/anchor-trips/trip-a'
              ? jsonResponse({'error': 'not_found'}, 404)
              : jsonResponse({'shipments': <Object>[]}));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text(tripNoLongerYours), findsOneWidget);
    });

    testWidgets('is told the same when confirming delivery answers 404',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      // The list still had the delivery and its photo when the screen opened; confirming answers 404.
      api.dio.httpClientAdapter = MockApiAdapter((request) => request.path ==
              '/v1/pilot/carrier/shipments'
          ? jsonResponse({
              'shipments': [
                shipmentOnTripA(photoIds: ['photo-1'])
              ]
            })
          : jsonResponse({'error': 'not_found'}, 404));
      await mountScreen(
          tester, const DriverPodScreen(shipmentId: 'shipment-a'));
      await tester.tap(find.text('Confirm delivery'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget);
    });
  });

  group('An owner driving a trip in transit', () {
    const sharedLine =
        'Shippers see your location while this app is open.';
    const stoppedLine =
        "You are no longer this trip's driver. Location sharing stopped.";
    Map<String, dynamic> tripDrivenBy(String driver) => {
          'id': 'trip-a',
          'status': 'IN_PROGRESS',
          'assignedVehicleId': 'vehicle-1',
          'assignedTruckNumber': 'KA01AB1234',
          'assignedDriverUserId': driver,
        };
    final somewhere = Position(
        latitude: 12.97,
        longitude: 77.59,
        timestamp: DateTime(2026, 10, 19),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);

    /// The office answers as the trip stands, with the owner and a second driver in the fleet, and keeps every
    /// position this phone sends.
    List<Object?> answerAsTheOffice(Map<String, dynamic> Function() trip) {
      final positionsSent = <Object?>[];
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        switch (request.path) {
          case '/v1/pilot/anchor-trips/trip-a':
            return jsonResponse({'trip': trip()});
          case '/v1/pilot/anchor-trips/trip-a/location':
            positionsSent.add(request.data);
            return jsonResponse(<String, Object>{});
          case '/v1/pilot/anchor-trips/trip-a/assignment':
            return jsonResponse({
              'trip': tripDrivenBy((request.data as Map)['driverUserId'] as String),
              'driverBusy': false
            });
          case '/v1/pilot/carrier/fleet':
            return jsonResponse({
              'vehicles': [
                {
                  'id': 'vehicle-1',
                  'registrationNumber': 'KA01AB1234',
                  'vehicleClass': 'MEDIUM'
                }
              ],
              'drivers': [
                {'userId': 'carrier-person', 'displayName': 'Synthetic Owner'},
                {'userId': 'driver-2', 'displayName': 'Synthetic Driver Two'},
              ],
            });
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA(status: 'PENDING_RELEASE')]
        });
      });
      return positionsSent;
    }

    /// The Assign driver sheet on the trip screen, with the trip's truck and [driver] chosen.
    Future<void> assignFromTheTripScreen(
        WidgetTester tester, String driver) async {
      await tester.tap(find.text('Choose driver'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('KA01AB1234')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text(driver)));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Choose $driver')));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'shares again the moment they assign the trip back to themselves from the trip screen',
        (tester) async {
      signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
      final positionsSent =
          answerAsTheOffice(() => tripDrivenBy('carrier-person'));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await assignFromTheTripScreen(tester, 'Synthetic Driver Two');
      expect(location.sharing, isFalse);
      expect(find.text(stoppedLine), findsOneWidget);

      await assignFromTheTripScreen(tester, 'Synthetic Owner');
      expect(location.sharing, isTrue,
          reason: 'reviewer: the screen said shared while nothing was sent');
      location.streams.last.add(somewhere);
      await tester.pumpAndSettle();
      expect(positionsSent, hasLength(1),
          reason: "given back, the phone sends the truck's position again");
      expect(find.text(sharedLine), findsOneWidget);
      expect(find.text(stoppedLine), findsNothing);
    });

    testWidgets(
        'a position already on its way when they assign another driver is not sent',
        (tester) async {
      signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
      final positionsSent =
          answerAsTheOffice(() => tripDrivenBy('carrier-person'));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await assignFromTheTripScreen(tester, 'Synthetic Driver Two');
      expect(location.sharing, isFalse);
      location.positionHandlers.single(somewhere);
      await tester.pumpAndSettle();
      expect(positionsSent, isEmpty,
          reason:
              "reviewer: a post racing the stop could land as the truck's position");
    });

    testWidgets(
        'stops sharing the moment they assign another driver from the trip screen, and is told so',
        (tester) async {
      signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
      final positionsSent =
          answerAsTheOffice(() => tripDrivenBy('carrier-person'));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(location.sharing, isTrue, reason: 'the owner is the driver');
      expect(find.text(sharedLine), findsOneWidget);

      await tester.tap(find.text('Choose driver'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('KA01AB1234')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Synthetic Driver Two')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Choose Synthetic Driver Two')));
      await tester.pumpAndSettle();

      expect(location.sharing, isFalse,
          reason: "this phone is no longer in the truck, so it stops listening");
      location.streams.single.add(somewhere);
      await tester.pumpAndSettle();
      expect(positionsSent, isEmpty,
          reason: "the office's position is never sent as the truck's");
      expect(find.text(sharedLine), findsNothing);
      expect(find.text(stoppedLine), findsOneWidget);
    });

    testWidgets(
        'stops sharing when a pull-down shows the trip was given to another driver elsewhere, and is told so',
        (tester) async {
      signInAsCarrierOwner(alsoAllowed: ['trip.assign', 'load.status_update']);
      var driver = 'carrier-person';
      final positionsSent = answerAsTheOffice(() => tripDrivenBy(driver));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(location.sharing, isTrue);

      driver = 'driver-2';
      await pullDown(tester);
      expect(location.sharing, isFalse);
      location.streams.single.add(somewhere);
      await tester.pumpAndSettle();
      expect(positionsSent, isEmpty);
      expect(find.text(sharedLine), findsNothing);
      expect(find.text(stoppedLine), findsOneWidget);

      driver = 'carrier-person';
      await pullDown(tester);
      expect(location.streams, hasLength(2),
          reason: 'given back to the owner, the phone shares again');
      expect(location.sharing, isTrue);
      expect(find.text(sharedLine), findsOneWidget);
      expect(find.text(stoppedLine), findsNothing);
    });
  });

  group('The shipment screen', () {
    testWidgets('reloads after Confirm delivery, so it is not offered twice',
        (tester) async {
      signInAsApprovedDriver();
      var status = 'BOOKED';
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'POST') {
          status = 'PENDING_RELEASE';
          return jsonResponse(<String, Object>{});
        }
        return jsonResponse({
          'shipments': [
            shipmentOnTripA(status: status, photoIds: ['photo-1'])
          ]
        });
      });
      final router =
          GoRouter(initialLocation: '/driver/shipment/shipment-a', routes: [
        GoRoute(
            path: '/driver/shipment/:shipmentId',
            builder: (_, state) => Scaffold(
                body: DriverShipmentDetailScreen(
                    shipmentId: state.pathParameters['shipmentId'] ?? '')),
            routes: [
              GoRoute(
                  path: 'pod',
                  builder: (_, state) => Scaffold(
                      body: DriverPodScreen(
                          shipmentId:
                              state.pathParameters['shipmentId'] ?? ''))),
            ]),
      ]);
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Delivery confirmed'), findsOneWidget);
      expect(find.text('Confirm delivery'), findsNothing);
    });
  });
}
