// The truck and driver on a trip: the assignment card, the empty-list sentence for drivers, what the e-way
// bill cards say when the bill's truck is not the trip's, and a driver's refused truck change.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/eway_bill_portal_link.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/trip_assignment_card.dart';
import 'package:driver_pilot/unassigned_driver_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

const savedSentence =
    'Saved. The driver is not sent a message. The trip shows on their Loads screen when they pull down to refresh.';
const busySentence =
    'This driver is already on another trip that is in progress.';
const replacedSentence = 'A driver who is replaced stops seeing this trip.';
const changedSentence =
    'This trip, or your trucks and drivers, changed. Pull down to reload this screen.';
const unassignedSentence =
    'Your carrier has not assigned you a trip yet. Ask your carrier to assign one.';
const completedSentence =
    'This trip is complete, so its truck and driver can no longer change.';

const fleet = {
  'vehicles': [
    {
      'id': 'vehicle-1',
      'registrationNumber': 'KA01AB1234',
      'vehicleClass': 'MEDIUM'
    },
    {
      'id': 'vehicle-2',
      'registrationNumber': 'KA02XY9999',
      'vehicleClass': 'MEDIUM'
    },
  ],
  'drivers': [
    {'userId': 'driver-1', 'displayName': 'Synthetic Driver One'},
    {'userId': 'driver-2', 'displayName': 'Synthetic Driver Two'},
  ],
};

void signInAsCarrierStaff({required String subrole, required bool canAssign}) {
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal = {
    'organizationId': 'carrier-a',
    'roles': ['CARRIER'],
    'subrole': subrole,
    'permissions': ['load.read', if (canAssign) 'trip.assign'],
  };
}

Map<String, dynamic> trip({Map<String, dynamic> assigned = const {}}) =>
    {'id': 'trip-a', 'status': 'OPEN', ...assigned};

Future<void> choose(WidgetTester tester, String hint, String option) async {
  await tester.tap(find.ancestor(
      of: find.text(hint), matching: find.byType(DropdownButton<String>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

FilledButton saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

void main() {
  setUp(signInAsShipper);

  group('Truck and driver card', () {
    testWidgets('an owner starts with nothing chosen, picks both, and saves',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      final sent = <String, Object?>{};
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'GET') return jsonResponse(fleet);
        sent['path'] = request.path;
        sent['body'] = request.data;
        return jsonResponse({
          'trip': trip(assigned: {
            'assignedVehicleId': 'vehicle-2',
            'assignedDriverUserId': 'driver-1',
            'assignedTruckNumber': 'KA02XY9999',
            'assignedDriverName': 'Synthetic Driver One',
          }),
          'driverBusy': false,
        });
      });
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      expect(find.text('No truck or driver is assigned to this trip yet.'),
          findsOneWidget);
      expect(find.text('Choose a truck'), findsOneWidget,
          reason: 'no truck is preselected');
      expect(find.text('Choose a driver'), findsOneWidget,
          reason: 'no driver is preselected');
      expect(saveButton(tester).onPressed, isNull,
          reason: 'nothing to save until both are chosen');
      expect(
          find.text(
              'Choose a truck and a driver, then tap Save. You can change them until the trip is complete.'),
          findsOneWidget,
          reason: 'nothing is assigned yet');
      await choose(tester, 'Choose a truck', 'KA02XY9999');
      expect(saveButton(tester).onPressed, isNull);
      await choose(tester, 'Choose a driver', 'Synthetic Driver One');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent['path'], '/v1/pilot/anchor-trips/trip-a/assignment');
      expect(
          sent['body'], {'vehicleId': 'vehicle-2', 'driverUserId': 'driver-1'});
      expect(find.text('Truck: KA02XY9999. Driver: Synthetic Driver One.'),
          findsOneWidget);
      expect(find.text(savedSentence), findsOneWidget);
      expect(find.text(busySentence), findsNothing);
      expect(
          find.text(
              'Saving replaces the truck and driver assigned now. You can change them until the trip is complete.'),
          findsOneWidget);
      expect(find.text(replacedSentence), findsNothing,
          reason: 'the saved driver is the one chosen');
    });

    testWidgets(
        'choosing another driver than the one assigned says the replaced driver stops seeing the trip',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => jsonResponse(fleet));
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(assigned: {
            'assignedVehicleId': 'vehicle-1',
            'assignedDriverUserId': 'driver-2',
          })));
      await tester.pumpAndSettle();
      expect(find.text(replacedSentence), findsNothing);
      await choose(tester, 'Synthetic Driver Two', 'Synthetic Driver One');
      expect(find.text(replacedSentence), findsOneWidget);
      await choose(tester, 'Synthetic Driver One', 'Synthetic Driver Two');
      expect(find.text(replacedSentence), findsNothing);
    });

    testWidgets('the card says what it is doing while the lists load',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      final answer = Completer<void>();
      api.dio.httpClientAdapter = MockApiAdapter((request) async {
        await answer.future;
        return jsonResponse(fleet);
      });
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pump();
      expect(find.text('Loading trucks and drivers...'), findsOneWidget);
      answer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Loading trucks and drivers...'), findsNothing);
      expect(find.text('Choose a truck'), findsOneWidget);
    });

    testWidgets('with no truck to choose, the card says so instead of grey pickers',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          jsonResponse({'vehicles': <Object>[], 'drivers': fleet['drivers']!}));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      expect(find.text('No trucks or drivers are set up for this carrier yet.'),
          findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    });

    testWidgets(
        'a trip that already names a truck and driver shows them chosen',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DISPATCHER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => jsonResponse(fleet));
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(assigned: {
            'assignedVehicleId': 'vehicle-1',
            'assignedDriverUserId': 'driver-2',
            'assignedTruckNumber': 'KA01AB1234',
            'assignedDriverName': 'Synthetic Driver Two',
          })));
      await tester.pumpAndSettle();
      expect(find.text('Choose a truck'), findsNothing);
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the current truck is the chosen one');
      expect(find.text('Synthetic Driver Two'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNotNull);
    });

    testWidgets(
        'the truck list writes a truck as the Truck line does, however it was typed',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'vehicles': [
              {
                'id': 'vehicle-1',
                'registrationNumber': 'ka 01-ab 1234',
                'vehicleClass': 'MEDIUM'
              }
            ],
            'drivers': fleet['drivers']!,
          }));
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(assigned: {
            'assignedVehicleId': 'vehicle-1',
            'assignedTruckNumber': 'KA01AB1234',
          })));
      await tester.pumpAndSettle();
      expect(find.text('Truck: KA01AB1234. Driver: not assigned.'),
          findsOneWidget);
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the chosen truck in the list');
      expect(find.text('ka 01-ab 1234'), findsNothing);
    });

    testWidgets(
        'a driver already on a trip in progress is a warning, not a block',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.method == 'GET'
              ? jsonResponse(fleet)
              : jsonResponse({'trip': trip(), 'driverBusy': true}));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      await choose(tester, 'Choose a truck', 'KA01AB1234');
      await choose(tester, 'Choose a driver', 'Synthetic Driver Two');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(busySentence), findsOneWidget);
      await choose(tester, 'Synthetic Driver Two', 'Synthetic Driver One');
      expect(find.text(busySentence), findsNothing,
          reason: 'the warning was about the driver chosen before');
    });

    testWidgets(
        'a named truck no longer in the fleet shows as unchosen and cannot be sent',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => jsonResponse(fleet));
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(assigned: {
            'assignedVehicleId': 'vehicle-gone',
            'assignedDriverUserId': 'driver-2',
          })));
      await tester.pumpAndSettle();
      expect(find.text('Choose a truck'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull);
    });

    testWidgets("a refusal shows the server's sentence, never HTTP 400",
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => request.method == 'GET'
              ? jsonResponse(fleet)
              : jsonResponse({
                  'error': 'invalid_trip_assignment',
                  'detail': 'Choose a truck from your own fleet.',
                  'field': 'vehicleId'
                }, 400));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      await choose(tester, 'Choose a truck', 'KA01AB1234');
      await choose(tester, 'Choose a driver', 'Synthetic Driver Two');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a truck from your own fleet.'), findsOneWidget);
      expect(find.textContaining('HTTP'), findsNothing);
      expect(find.text(savedSentence), findsNothing);
    });

    testWidgets(
        'a 403 or 404 on Save asks for a reload; a 409 shows the server sentence',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      for (final status in [403, 404, 409]) {
        api.dio.httpClientAdapter = MockApiAdapter((request) =>
            request.method == 'GET'
                ? jsonResponse(fleet)
                : jsonResponse(
                    {'error': 'trip_completed', 'detail': completedSentence},
                    status));
        await mountCard(
            tester, TripAssignmentCard(key: ValueKey(status), trip: trip()));
        await tester.pumpAndSettle();
        await choose(tester, 'Choose a truck', 'KA01AB1234');
        await choose(tester, 'Choose a driver', 'Synthetic Driver Two');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text(status == 409 ? completedSentence : changedSentence),
            findsOneWidget,
            reason: '$status');
      }
    });

    testWidgets('a save refused after a successful one shows no Saved line',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      var saves = 0;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'GET') return jsonResponse(fleet);
        saves++;
        return saves == 1
            ? jsonResponse({
                'trip': trip(assigned: {
                  'assignedVehicleId': 'vehicle-1',
                  'assignedDriverUserId': 'driver-2',
                  'assignedTruckNumber': 'KA01AB1234',
                  'assignedDriverName': 'Synthetic Driver Two',
                }),
                'driverBusy': false,
              })
            : jsonResponse(
                {'error': 'trip_completed', 'detail': completedSentence}, 409);
      });
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      await choose(tester, 'Choose a truck', 'KA01AB1234');
      await choose(tester, 'Choose a driver', 'Synthetic Driver Two');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(savedSentence), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(completedSentence), findsOneWidget);
      expect(find.text(savedSentence), findsNothing,
          reason: 'the second save was refused');
    });

    testWidgets(
        'pulling the trip screen down reloads the trip and the truck and driver lists',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      var tripRequests = 0;
      var fleetRequests = 0;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.path == '/v1/pilot/carrier/fleet') {
          fleetRequests++;
          return jsonResponse(fleet);
        }
        if (request.path == '/v1/pilot/anchor-trips/trip-a') {
          tripRequests++;
          return jsonResponse({'trip': trip()});
        }
        return jsonResponse({'shipments': <Object>[]});
      });
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(body: DriverActiveTripScreen(tripId: 'trip-a'))));
      await tester.pumpAndSettle();
      expect([tripRequests, fleetRequests], [1, 1]);
      // A refresh needs a pull of a quarter of the list's height, and this test screen is 3000 pixels tall.
      await tester.fling(find.byType(ListView), const Offset(0, 1200), 1000);
      await tester.pumpAndSettle();
      expect([tripRequests, fleetRequests], [2, 2],
          reason: 'the card comes back with fresh lists');
    });

    testWidgets('a driver only reads the assignment: no pickers, no buttons',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      var requests = 0;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        requests++;
        return jsonResponse(fleet);
      });
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(assigned: {
            'assignedTruckNumber': 'KA01AB1234',
            'assignedDriverName': 'Synthetic Driver One',
          })));
      await tester.pumpAndSettle();
      expect(find.text('Truck: KA01AB1234. Driver: Synthetic Driver One.'),
          findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(requests, 0, reason: 'the fleet list is not even asked for');
    });
  });

  group('A driver with no trip', () {
    Future<void> mountNotice(WidgetTester tester) => tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UnassignedDriverNotice())));

    testWidgets('a driver is told their carrier has not assigned a trip',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      await mountNotice(tester);
      expect(find.text(unassignedSentence), findsOneWidget);
    });

    testWidgets('an owner is not', (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      await mountNotice(tester);
      expect(find.text(unassignedSentence), findsNothing);
    });

    testWidgets(
        'above an empty list a driver sees only the carrier name; the office keeps its hint',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final subrole in ['DRIVER', 'OWNER']) {
        signInAsCarrierStaff(subrole: subrole, canAssign: subrole == 'OWNER');
        // The Loads screen refreshes the session first, so the server answers with the same login.
        api.dio.httpClientAdapter = MockApiAdapter((request) {
          if (request.path == '/v1/auth/me') {
            return jsonResponse({
              'user': {'id': 'carrier-person'},
              'organizations': [
                {
                  'id': 'carrier-a',
                  'kind': 'CARRIER_FLEET',
                  'displayName': 'Synthetic Carrier A',
                  'kycStatus': 'APPROVED'
                }
              ],
              'principal': {
                'organizationId': 'carrier-a',
                'roles': ['CARRIER'],
                'subrole': subrole,
                'permissions': ['organization.profile.read', 'load.read'],
              },
            });
          }
          if (request.path == '/v1/pilot/anchor-trips') {
            return jsonResponse({'trips': <Object>[]});
          }
          return jsonResponse({'vehicles': <Object>[]});
        });
        await tester.pumpWidget(MaterialApp(
            theme: DriverTheme.theme(),
            home: Scaffold(body: DriverLoadsScreen(key: ValueKey(subrole)))));
        await tester.pumpAndSettle();
        if (subrole == 'DRIVER') {
          expect(find.text('Synthetic Carrier A'), findsOneWidget);
          expect(find.textContaining('tap Publish'), findsNothing);
          expect(find.text(unassignedSentence), findsOneWidget);
        } else {
          expect(
              find.text(
                  'Synthetic Carrier A · No anchor trips · tap Publish to add a lane'),
              findsOneWidget);
        }
      }
    });
  });

  group('A driver whose trip was given to someone else', () {
    const tripNoLongerYours =
        'This trip is no longer assigned to you. Go back to Loads and pull down to refresh.';

    Future<void> mountScreen(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(), home: Scaffold(body: screen)));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'is told a shipment no longer listed is not on their trip, instead of a spinner',
        (tester) async {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      api.dio.httpClientAdapter = MockApiAdapter(
          (_) => jsonResponse({'shipments': <Object>[]}));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(
          find.text(
              'This shipment is not on a trip assigned to you now. Go back and pull down on Shipments to refresh.'),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
        'the office gets its usual sentence for a shipment no longer listed',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter(
          (_) => jsonResponse({'shipments': <Object>[]}));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Could not load this shipment.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
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

  group('A driver publishing a trip', () {
    test('is told the office must assign it before it shows under Loads', () {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      expect(tripPublishedSentence(),
          'Trip published. The carrier owner or dispatcher must assign it to a driver. You will not see it under Loads until they do.');
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      expect(tripPublishedSentence(), 'Trip published.');
    });
  });

  group('A driver changing a truck that is on a trip', () {
    DioException refusal(int status, Map<String, dynamic> body) {
      final options = RequestOptions(path: '/v1/pilot/me/vehicle');
      return DioException(
          requestOptions: options,
          response:
              Response(requestOptions: options, statusCode: status, data: body));
    }

    test('sees the server sentence, not HTTP 409', () {
      const sentence =
          'This truck is on a trip that is not finished. Ask your carrier to change it.';
      expect(
          formatApiError(refusal(
              409, {'error': 'truck_on_unfinished_trip', 'detail': sentence})),
          sentence);
    });

    test('sees the length rule as a sentence', () {
      const sentence = 'A truck number can have at most 20 characters.';
      expect(
          formatApiError(refusal(400, {
            'error': 'invalid_vehicleRegistrationNumber',
            'detail': sentence,
            'field': 'vehicleRegistrationNumber'
          })),
          sentence);
    });
  });

  group('The bill and the trip name different trucks', () {
    final billWithTruck =
        withTruck({'kind': 'BILL', 'billNumber': '123456789012'});
    Map<String, dynamic> onTrip(String truck) =>
        {...shipment(bill: billWithTruck), 'assignedTruckNumber': truck};
    final forCarrierOffice =
        'The e-way bill shows KA01AB1234. The truck on this trip is KA02XY9999. Check which one is right; if the e-way bill is wrong, update it on the $ewayBillPortalName, then here.';

    testWidgets(
        'the carrier office is asked to check which truck is right and fix the bill',
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(find.text(forCarrierOffice), findsOneWidget);
    });

    testWidgets('a driver gets the facts and is told to tell the carrier',
        (tester) async {
      signInAsCarrier(canAddTruck: false);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(
          find.text(
              'The e-way bill shows KA01AB1234. The truck on this trip is KA02XY9999. Tell your carrier.'),
          findsOneWidget);
      expect(find.textContaining('update it'), findsNothing);
    });

    testWidgets(
        'the shipper is told what the carrier assigned and asked to check with them, not sent to the portal',
        (tester) async {
      signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
      await mountCard(tester, EwayBillCard(shipment: onTrip('KA02XY9999')));
      expect(
          find.text(
              'The e-way bill shows KA01AB1234. Your carrier has assigned KA02XY9999 to this trip. Ask your carrier which truck is right.'),
          findsOneWidget);
      expect(find.textContaining('portal, then here'), findsNothing);
    });

    testWidgets('once the shipment is closed nobody is asked about the trucks',
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester,
          EwayBillCarrierCard(shipment: {
            ...onTrip('KA02XY9999'),
            'status': 'DELIVERED',
          }));
      expect(find.textContaining('The truck on this trip'), findsNothing);
    });

    testWidgets('the same truck, written differently, says nothing extra',
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('ka 01-ab 1234')));
      expect(find.textContaining('The truck on this trip'), findsNothing);
    });

    testWidgets("the carrier's Add truck form starts with the trip's truck",
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester,
          EwayBillCarrierCard(shipment: {
            ...shipment(bill: {'kind': 'BILL', 'billNumber': '123456789012'}),
            'assignedTruckNumber': 'KA02XY9999'
          }));
      await tester.tap(find.text('Add truck'));
      await tester.pump();
      expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'Truck number'))
              .controller!
              .text,
          'KA02XY9999');
      expect(
          find.text(
              'Filled in from the truck on this trip. Change it if the e-way bill shows a different truck.'),
          findsOneWidget);
    });

    testWidgets('a form not filled in from the trip says nothing about it',
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester,
          EwayBillCarrierCard(
              shipment: shipment(
                  bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
      await tester.tap(find.text('Add truck'));
      await tester.pump();
      expect(find.textContaining('Filled in from the truck'), findsNothing);
    });
  });
}
