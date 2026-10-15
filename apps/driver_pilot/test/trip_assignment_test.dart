// The truck and driver on a trip: the assignment card, the empty-list sentence for drivers, and what the
// e-way bill cards say when the bill's truck is not the trip's.
import 'package:driver_pilot/authorization_session.dart';
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
      expect(find.text('No truck or driver named for this trip yet.'),
          findsOneWidget);
      expect(find.text('Choose a truck'), findsOneWidget,
          reason: 'no truck is preselected');
      expect(find.text('Choose a driver'), findsOneWidget,
          reason: 'no driver is preselected');
      expect(saveButton(tester).onPressed, isNull,
          reason: 'nothing to save until both are chosen');
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
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('This driver is already on a trip in progress.'),
          findsNothing);
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
      expect(find.text('This driver is already on a trip in progress.'),
          findsOneWidget);
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
      expect(find.text('Saved.'), findsNothing);
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
      expect(find.text('Your carrier has not assigned you a trip yet.'),
          findsOneWidget);
    });

    testWidgets('an owner is not', (tester) async {
      signInAsCarrierStaff(subrole: 'OWNER', canAssign: true);
      await mountNotice(tester);
      expect(find.text('Your carrier has not assigned you a trip yet.'),
          findsNothing);
    });
  });

  group('The bill and the trip name different trucks', () {
    final billWithTruck =
        withTruck({'kind': 'BILL', 'billNumber': '123456789012'});
    Map<String, dynamic> onTrip(String truck) =>
        {...shipment(bill: billWithTruck), 'assignedTruckNumber': truck};
    final request =
        'The bill shows KA01AB1234. The truck on this trip is KA02XY9999. Update the bill on the $ewayBillPortalName, then here.';

    testWidgets(
        'the carrier owner gets one plain sentence asking for the update',
        (tester) async {
      signInAsCarrier(canAddTruck: true);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(find.text(request), findsOneWidget);
    });

    testWidgets('a driver gets the facts but is not asked to change the bill',
        (tester) async {
      signInAsCarrier(canAddTruck: false);
      await mountCard(
          tester, EwayBillCarrierCard(shipment: onTrip('KA02XY9999')));
      expect(
          find.text(
              'The bill shows KA01AB1234. The truck on this trip is KA02XY9999.'),
          findsOneWidget);
      expect(find.textContaining('Update the bill'), findsNothing);
    });

    testWidgets('the shipper sees the same sentence', (tester) async {
      signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
      await mountCard(tester, EwayBillCard(shipment: onTrip('KA02XY9999')));
      expect(find.text(request), findsOneWidget);
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
    });
  });
}
