// What follows from the truck and driver named on a trip: the assignment card and its "Who drives this trip?"
// sheet, the empty-list sentence for drivers, the message after a driver publishes a trip, a driver's refused
// truck change, and what the e-way bill cards say when the bill's truck is not the trip's.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/trip_assignment_card.dart';
import 'package:driver_pilot/unassigned_driver_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

const savedSentence =
    'Saved. A new driver gets a notice in the app. The trip shows on their Trips screen when they refresh it.';
const busySentence =
    'This driver is already on another trip that is on the way.';
const replacedSentence = 'If you change the driver, the old driver stops seeing this trip.';
const changedSentence =
    'This trip, or your trucks and drivers, changed. Tap Refresh to load this screen again.';
const unassignedSentence =
    'Your office has not given you a trip yet. Ask your office for one.';
const completedSentence =
    'This trip is complete, so its truck and driver can no longer change.';
const staleChoiceSentence =
    'Choose a truck from your own fleet. Tap Refresh to load your trucks and drivers again.';
const onTheRoadSentence =
    'This trip is on the road with no driver. If a driver started it, they stop seeing it when you choose someone else.';
const sheetTitle = 'Who drives this trip?';
const driverSees =
    'The driver sees the trip and the e-way bill, never the payment.';

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

Map<String, dynamic> trip({Map<String, dynamic> assigned = const {}}) =>
    {'id': 'trip-a', 'status': 'OPEN', ...assigned};

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Choose driver'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String option) async {
  await tester.tap(inSheet(find.text(option)));
  await tester.pumpAndSettle();
}

/// The sheet's one primary button, whatever its label says now.
FilledButton sheetPrimary(WidgetTester tester) =>
    tester.widget<FilledButton>(inSheet(find.byType(FilledButton)));

/// Which row of a choice list is chosen: the radio group's value, null when none is.
String? chosenIn(WidgetTester tester, String anyOption) => tester
    .widget<RadioListTile<String>>(find.ancestor(
        of: inSheet(find.text(anyOption)),
        matching: find.byType(RadioListTile<String>)))
    .groupValue;

Future<void> chooseAndSave(WidgetTester tester,
    {String truck = 'KA01AB1234', String driver = 'Synthetic Driver Two'}) async {
  await openSheet(tester);
  await choose(tester, truck);
  await choose(tester, driver);
  await tester.tap(inSheet(find.text('Choose $driver')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(signInAsShipper);

  group('Truck and driver card', () {
    testWidgets(
        'an owner assigns from the sheet: nothing chosen at first, the sheet names the trip, both are saved',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      final sent = <String, Object?>{};
      final reported = <Map<String, dynamic>>[];
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
      await mountCard(
          tester,
          TripAssignmentCard(
              trip: trip(),
              tripInWords: 'Bengaluru to Chennai, 18 – 19 Oct',
              onAssigned: reported.add));
      await tester.pumpAndSettle();
      expect(find.text('Not chosen yet'), findsNWidgets(2),
          reason: 'ca-trip: the Truck and Driver rows say Not assigned');
      expect(find.text('Choose driver'), findsOneWidget,
          reason: 'ca-trip: the card opens the assign sheet');

      await openSheet(tester);
      expect(find.text(sheetTitle), findsOneWidget, reason: 'ca-assign title');
      expect(
          inSheet(find.text('Bengaluru to Chennai, 18 – 19 Oct. $driverSees')),
          findsOneWidget,
          reason: 'copy.md Assign sheet: the trip, and what the driver sees');
      expect(chosenIn(tester, 'Synthetic Driver One'), isNull,
          reason: 'spec: no driver preselected');
      expect(chosenIn(tester, 'KA01AB1234'), isNull,
          reason: 'the trip names no truck, so none is chosen');
      expect(sheetPrimary(tester).onPressed, isNull,
          reason: 'nothing to save until a driver and a truck are chosen');
      expect(inSheet(find.text('Choose a driver first.')), findsOneWidget,
          reason: 'a disabled button says why');

      await choose(tester, 'Synthetic Driver One');
      expect(inSheet(find.text('Choose a truck first.')), findsOneWidget);
      await choose(tester, 'KA02XY9999');
      expect(
          inSheet(find.text(
              'Bengaluru to Chennai, 18 – 19 Oct, truck KA02XY9999. $driverSees')),
          findsOneWidget,
          reason: 'copy.md Assign sheet names the truck');
      await tester.tap(inSheet(find.text('Choose Synthetic Driver One')));
      await tester.pumpAndSettle();
      expect(sent['path'], '/v1/pilot/anchor-trips/trip-a/assignment');
      expect(
          sent['body'], {'vehicleId': 'vehicle-2', 'driverUserId': 'driver-1'});
      expect(find.text(sheetTitle), findsNothing,
          reason: 'the sheet closes after a save');
      expect(find.text('KA02XY9999'), findsOneWidget);
      expect(find.text('Synthetic Driver One'), findsOneWidget);
      expect(find.text(savedSentence), findsOneWidget);
      expect(find.text(busySentence), findsNothing);
      expect(reported.single['assignedDriverUserId'], 'driver-1',
          reason: 'the trip screen is told, so it can offer Start');
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
      await openSheet(tester);
      expect(find.text(replacedSentence), findsNothing);
      await choose(tester, 'Synthetic Driver One');
      expect(find.text(replacedSentence), findsOneWidget);
      await choose(tester, 'Synthetic Driver Two');
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
      expect(find.text('Choose driver'), findsOneWidget);
    });

    testWidgets('with no truck to choose, the card says so instead of a sheet',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          jsonResponse({'vehicles': <Object>[], 'drivers': fleet['drivers']!}));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      expect(find.text('You have no trucks or drivers yet.'),
          findsOneWidget);
      expect(find.text('Choose driver'), findsNothing);
    });

    testWidgets(
        'a trip that names its truck and driver shows them; the sheet keeps the truck and chooses no driver',
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
      expect(find.text('KA01AB1234'), findsOneWidget);
      expect(find.text('Synthetic Driver Two'), findsOneWidget);
      expect(find.text('Not chosen yet'), findsNothing);
      await openSheet(tester);
      expect(chosenIn(tester, 'KA01AB1234'), 'vehicle-1',
          reason: "the trip's own truck, so it can still be changed here");
      expect(chosenIn(tester, 'Synthetic Driver One'), isNull,
          reason: 'spec: no driver preselected');
      expect(sheetPrimary(tester).onPressed, isNull);
    });

    testWidgets(
        'the card and the sheet write a truck as the e-way bill does, however it was typed',
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
              trip: trip(assigned: {'assignedVehicleId': 'vehicle-1'})));
      await tester.pumpAndSettle();
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the Truck row, from the fleet list');
      await openSheet(tester);
      expect(inSheet(find.text('KA01AB1234')), findsOneWidget);
      expect(find.text('ka 01-ab 1234'), findsNothing);
      expect(inSheet(find.text('Medium truck')), findsOneWidget,
          reason: 'sizes in words, never the code');
    });

    testWidgets('a driver already on a trip in progress is a warning, not a block',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.method == 'GET'
              ? jsonResponse(fleet)
              : jsonResponse({'trip': trip(), 'driverBusy': true}));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      await chooseAndSave(tester);
      expect(find.text(busySentence), findsOneWidget);
      await openSheet(tester);
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
      await openSheet(tester);
      expect(chosenIn(tester, 'KA01AB1234'), isNull);
      await choose(tester, 'Synthetic Driver Two');
      expect(sheetPrimary(tester).onPressed, isNull);
      expect(inSheet(find.text('Choose a truck first.')), findsOneWidget);
    });

    testWidgets(
        "a truck or driver that stopped being valid shows the server's sentence in the open sheet, never HTTP 400",
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
      await chooseAndSave(tester);
      expect(inSheet(find.text(staleChoiceSentence)), findsOneWidget,
          reason: 'cp-sheet: an error keeps the sheet open');
      expect(chosenIn(tester, 'Synthetic Driver Two'), 'driver-2',
          reason: 'and keeps the choice');
      expect(find.textContaining('HTTP'), findsNothing);
      expect(find.text(savedSentence), findsNothing);
    });

    testWidgets('any other 400 shows only the server sentence', (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.method == 'GET'
              ? jsonResponse(fleet)
              : jsonResponse({
                  'error': 'invalid_json',
                  'detail': 'Send the truck and the driver as JSON.'
                }, 400));
      await mountCard(tester, TripAssignmentCard(trip: trip()));
      await tester.pumpAndSettle();
      await chooseAndSave(tester);
      expect(find.text('Send the truck and the driver as JSON.'), findsOneWidget);
      expect(find.textContaining('Pull down'), findsNothing);
    });

    testWidgets(
        'a trip on the road with no driver assigned warns that a driver who started it would stop seeing it',
        (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      api.dio.httpClientAdapter =
          MockApiAdapter((request) => jsonResponse(fleet));
      final cases = <String, Map<String, dynamic>>{
        'on the road, no driver': {'id': 'trip-a', 'status': 'IN_PROGRESS'},
        'on the road, driver assigned': {
          'id': 'trip-b',
          'status': 'IN_PROGRESS',
          'assignedVehicleId': 'vehicle-1',
          'assignedDriverUserId': 'driver-2',
        },
        'not started, no driver': {'id': 'trip-c', 'status': 'OPEN'},
      };
      for (final entry in cases.entries) {
        await mountCard(tester,
            TripAssignmentCard(key: ValueKey(entry.key), trip: entry.value));
        await tester.pumpAndSettle();
        await openSheet(tester);
        expect(find.text(onTheRoadSentence),
            entry.key == 'on the road, no driver' ? findsOneWidget : findsNothing,
            reason: entry.key);
        await tester.tap(inSheet(find.text('Cancel')));
        await tester.pumpAndSettle();
      }
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
        await chooseAndSave(tester);
        expect(find.text(status == 409 ? completedSentence : changedSentence),
            findsOneWidget,
            reason: '$status');
        await tester.tap(inSheet(find.text('Cancel')));
        await tester.pumpAndSettle();
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
      await chooseAndSave(tester);
      expect(find.text(savedSentence), findsOneWidget);
      await openSheet(tester);
      await choose(tester, 'Synthetic Driver Two');
      await tester.tap(inSheet(find.text('Choose Synthetic Driver Two')));
      await tester.pumpAndSettle();
      expect(find.text(completedSentence), findsOneWidget);
      await tester.tap(inSheet(find.text('Cancel')));
      await tester.pumpAndSettle();
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

    testWidgets('a driver only reads the assignment: no sheet, no buttons',
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
      expect(find.text('KA01AB1234'), findsOneWidget);
      expect(find.text('Synthetic Driver One'), findsOneWidget);
      expect(find.text('Choose driver'), findsNothing);
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
        'with no trips a driver is told none is assigned; the office is told none is open and how to publish',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final subrole in ['DRIVER', 'OWNER']) {
        signInAsCarrierStaff(subrole: subrole, canAssign: subrole == 'OWNER');
        // The Trips screen refreshes the session first, so the server answers with the same login.
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
                'permissions': [
                  'organization.profile.read',
                  'load.read',
                  if (subrole == 'OWNER') 'trip.publish'
                ],
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
        const publishHelp =
            'Shippers can book it once you add it.';
        if (subrole == 'DRIVER') {
          expect(find.text(unassignedSentence), findsOneWidget);
          expect(find.text(publishHelp), findsNothing,
              reason: 'drivers have no Publish tab');
        } else {
          expect(find.text('No open trips.'), findsOneWidget,
              reason: 'ca-trips: the Open chip is shown first');
          expect(find.text(publishHelp), findsOneWidget);
          expect(find.text(unassignedSentence), findsNothing);
        }
      }
    });
  });

  group('A driver publishing a trip', () {
    test(
        'is told for ten seconds that it shows under Trips only if it is assigned to them; the office as before',
        () {
      signInAsCarrierStaff(subrole: 'DRIVER', canAssign: false);
      final forDriver = tripPublishedMessage();
      expect((forDriver.content as Text).data,
          'Trip added. Your office must choose a driver for it. You see it under Trips only if they choose you.');
      expect(forDriver.duration, const Duration(seconds: 10));
      expect(forDriver.action?.label, 'Close');

      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      final forOffice = tripPublishedMessage();
      expect((forOffice.content as Text).data, 'Trip added.');
      expect(forOffice.duration, const SnackBar(content: SizedBox()).duration,
          reason: 'the default length');
      expect(forOffice.action, isNull);
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
        'The e-way bill shows KA01AB1234. The truck on this trip is KA02XY9999. Check which one is right. If the e-way bill is wrong, ask the shipper to change it. If you changed the truck on the e-way bill portal yourself, change it there and tell the shipper.';

    testWidgets(
        'the carrier office is asked to check which truck is right and to ask the shipper about the bill',
        (tester) async {
      signInAsCarrier(office: true);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(find.text(forCarrierOffice), findsOneWidget);
      expect(find.textContaining('update it on the'), findsNothing,
          reason: 'the carrier is not sent to the portal to change the bill');
    });

    testWidgets('a driver gets the facts and is told to tell the carrier',
        (tester) async {
      signInAsCarrier(office: false);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(
          find.text(
              'The e-way bill shows KA01AB1234. The truck on this trip is KA02XY9999. Tell your office.'),
          findsOneWidget);
      expect(find.textContaining('update it'), findsNothing);
    });

    testWidgets(
        'the shipper is told what the carrier assigned, to check with them, and that the bill is theirs to change',
        (tester) async {
      signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
      await mountCard(tester, EwayBillCard(shipment: onTrip('KA02XY9999')));
      expect(
          find.text(
              'The e-way bill shows KA01AB1234. The carrier put KA02XY9999 on this trip. Ask the carrier which truck is right. If the e-way bill is wrong, change it in your billing software or on the e-way bill portal, then here. If the portal refuses, the carrier may have changed it. Ask them to change it.'),
          findsOneWidget);
    });

    testWidgets('once the shipment is closed nobody is asked about the trucks',
        (tester) async {
      signInAsCarrier(office: true);
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
      signInAsCarrier(office: true);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('ka 01-ab 1234')));
      expect(find.textContaining('The truck on this trip'), findsNothing);
    });

    testWidgets(
        "the shipper's Add truck form starts with the truck the carrier named at acceptance",
        (tester) async {
      signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
      await mountCard(
          tester,
          EwayBillCard(shipment: {
            ...shipment(bill: savedBill),
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
      signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
      await mountCard(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
      await tester.tap(find.text('Add truck'));
      await tester.pump();
      expect(find.textContaining('Filled in from the truck'), findsNothing);
    });
  });
}
