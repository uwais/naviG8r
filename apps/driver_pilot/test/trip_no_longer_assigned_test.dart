// A driver's screens once the server's answer has changed under them: a trip given to someone else since they
// opened it, and the shipment screen after Confirm delivery.
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
    'This trip is no longer assigned to you. Pull down on the Loads screen to refresh.';

const notOnYourTrip =
    'This shipment is not on a trip assigned to you now. Go back and pull down on Shipments to refresh.';

/// Stands in for the phone's location service, which a widget test does not have. Location is allowed, no
/// one-off position comes back, and each time the trip screen listens for positions it gets a stream of its own.
class FakeLocationService extends GeolocatorPlatform {
  final streams = <StreamController<Position>>[];

  /// While a test holds this, the phone has not yet answered where it is now.
  Completer<void>? positionHeld;

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
    return positions.stream;
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
      expect(find.text('Could not load this shipment.'), findsOneWidget);
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
      await mountScreen(tester, const DriverShipmentsScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
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
      await tester.tap(find.text('Start load'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget,
          reason: 'on screen, with no snack bar repeating it');
      for (final stale in ['Load not started', 'Start load']) {
        expect(find.text(stale), findsNothing, reason: stale);
      }
      expect(find.textContaining('unavailable'), findsNothing);
    });

    testWidgets(
        'when Complete load answers 404, only the sentence is left and location sharing stops',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
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

      await tester.tap(find.text('Complete load'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget,
          reason: 'on screen, with no snack bar repeating it');
      expect(find.text('Load in progress'), findsNothing);
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
          'Live GPS is shared with customers while the load is in progress.';
      expect(find.text('Load in progress'), findsOneWidget);
      expect(find.text(gpsLine), findsOneWidget);
      expect(location.sharing, isTrue);

      await pullDown(tester);
      expect(find.text(tripNoLongerYours), findsOneWidget);
      for (final stale in [
        'Load in progress',
        'Load not started',
        gpsLine,
        'Truck and driver'
      ]) {
        expect(find.text(stale), findsNothing, reason: stale);
      }
      expect(find.textContaining('Status:'), findsNothing);
      expect(location.sharing, isFalse);

      await pullDown(tester);
      expect(find.text('Load in progress'), findsOneWidget,
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
      api.dio.httpClientAdapter =
          MockApiAdapter((_) => jsonResponse({'error': 'not_found'}, 404));
      await mountScreen(
          tester, const DriverPodScreen(shipmentId: 'shipment-a'));
      await tester.tap(find.text('Confirm POD'));
      await tester.pumpAndSettle();
      expect(find.text(tripNoLongerYours), findsOneWidget);
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
          'shipments': [shipmentOnTripA(status: status)]
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
      await tester.tap(find.text('Confirm POD'));
      await tester.pumpAndSettle();
      expect(find.text('Status: Delivery confirmed'), findsOneWidget);
      expect(find.text('Confirm delivery'), findsNothing);
    });
  });
}
