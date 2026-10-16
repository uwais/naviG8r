// Accepting a booking whose trip names no truck (owner decision, 16 Oct 2026): the carrier office chooses the
// truck first, from every Accept button; a driver, or a trip that already names its truck, accepts with one tap.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_words.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

const sheetTitle = 'Which truck carries this trip?';
const acceptWithTruck = 'Accept with this truck';
const acceptWithoutTruck = 'Accept without a truck';
const keptTruckSentence =
    'This trip already has truck KA01AB1234, so the booking was accepted with it. To change the truck, use Truck and driver on the trip screen.';

const twoTrucks = {
  'vehicles': [
    {'id': 'vehicle-1', 'registrationNumber': 'UP 1 345', 'vehicleClass': 'MEDIUM'},
    {'id': 'vehicle-2', 'registrationNumber': 'KA02XY9999', 'vehicleClass': 'MEDIUM'},
  ],
  'drivers': <Object>[],
};

/// The office holds trip.assign; a driver does not. Both may accept on an approved carrier.
void signInAs({required bool office}) => signInAsCarrierLogin(
    office: office,
    alsoAllowed: ['carrier.offer_accept', if (office) 'trip.assign']);

Map<String, dynamic> pendingShipment({String? tripTruck}) => {
      ...shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT'),
      if (tripTruck != null) 'assignedTruckNumber': tripTruck,
    };

/// What the screens asked for: each accept's body, and how often the truck list was loaded.
class Requests {
  final acceptBodies = <Object?>[];
  var fleetLoads = 0;
}

/// Answers the carrier screens' requests: the shipment list, the trip, the truck list and Accept. Accept's reply
/// carries [tripTruckAfterAccept] as the trip's truck, as the server sends it.
Requests answer(
    {Map<String, dynamic>? shipment,
    Object fleet = twoTrucks,
    int fleetStatus = 200,
    String? tripTruckAfterAccept}) {
  final requests = Requests();
  final listed = shipment ?? pendingShipment();
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    if (request.method == 'POST') {
      requests.acceptBodies.add(request.data);
      return jsonResponse({
        'shipment': {
          ...listed,
          'status': 'BOOKED',
          if (tripTruckAfterAccept != null)
            'assignedTruckNumber': tripTruckAfterAccept,
        }
      });
    }
    if (request.path == '/v1/pilot/carrier/fleet') {
      requests.fleetLoads++;
      return jsonResponse(fleet, fleetStatus);
    }
    if (request.path == '/v1/pilot/anchor-trips/trip-a') {
      final namedTrucks = requests.acceptBodies
          .whereType<Map>()
          .map((body) => body['vehicleId'])
          .whereType<String>();
      return jsonResponse({
        'trip': {
          'id': 'trip-a',
          'status': 'OPEN',
          if (namedTrucks.isNotEmpty) 'assignedVehicleId': namedTrucks.first,
        }
      });
    }
    return jsonResponse({
      'shipments': [listed]
    });
  });
  return requests;
}

Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

FilledButton acceptWithTruckButton(WidgetTester tester) =>
    tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, acceptWithTruck));

Future<void> tapAcceptOnShipmentsList(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
  await tester.pumpAndSettle();
}

void main() {
  group('The carrier office accepting on a trip that names no truck', () {
    testWidgets(
        'chooses the truck first, from the Shipments list, and Accept sends it',
        (tester) async {
      signInAs(office: true);
      final requests = answer();
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(find.text(sheetTitle), findsOneWidget);
      expect(requests.acceptBodies, isEmpty,
          reason: 'nothing is accepted before a truck is chosen');
      expect(inSheet(find.text('UP010345')), findsOneWidget,
          reason: "each truck in the portal's form");
      expect(inSheet(find.text('KA02XY9999')), findsOneWidget);
      expect(acceptWithTruckButton(tester).onPressed, isNull,
          reason: 'with two trucks none is chosen for the office');
      expect(find.text(acceptWithoutTruck), findsNothing);
      await tester.tap(inSheet(find.text('KA02XY9999')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [
        {'vehicleId': 'vehicle-2'}
      ]);
      expect(find.text(sheetTitle), findsNothing);
      expect(find.text('Booking accepted.'), findsOneWidget);
    });

    testWidgets('Cancel closes the sheet and accepts nothing', (tester) async {
      signInAs(office: true);
      final requests = answer();
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      await tester.tap(inSheet(find.text('UP010345')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(sheetTitle), findsNothing);
      expect(requests.acceptBodies, isEmpty);
      expect(find.text('Booking accepted.'), findsNothing);
    });

    testWidgets('the only truck is already chosen', (tester) async {
      signInAs(office: true);
      final requests = answer(fleet: {
        'vehicles': [
          {'id': 'vehicle-1', 'registrationNumber': 'UP1345', 'vehicleClass': 'MEDIUM'}
        ],
        'drivers': <Object>[],
      });
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(
          tester
              .widget<RadioListTile<String>>(find.byType(RadioListTile<String>))
              .groupValue,
          'vehicle-1');
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [
        {'vehicleId': 'vehicle-1'}
      ]);
    });

    testWidgets(
        'with no trucks the sheet says so, and the office can still accept without one',
        (tester) async {
      signInAs(office: true);
      final requests =
          answer(fleet: {'vehicles': <Object>[], 'drivers': <Object>[]});
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(
          find.text(
              'No trucks are set up for this carrier yet. You can accept now, but the shipper sees no truck until one is named on the trip screen. Trucks are added by inviting their drivers from Profile.'),
          findsOneWidget);
      expect(find.text(acceptWithTruck), findsNothing);
      await tester.tap(find.text(acceptWithoutTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [null],
          reason: 'accepted as before this change, with no truck sent');
      expect(find.text('Booking accepted.'), findsOneWidget);
    });

    testWidgets(
        'when the trucks cannot load, the sheet offers Try again and no accept',
        (tester) async {
      signInAs(office: true);
      final requests = answer(fleetStatus: 500);
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(find.text('Could not load your trucks.'), findsOneWidget);
      expect(find.text(acceptWithTruck), findsNothing);
      expect(find.text(acceptWithoutTruck), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(requests.fleetLoads, 2);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, isEmpty);
    });

    testWidgets('the shipment screen asks for the truck too', (tester) async {
      signInAs(office: true);
      final requests = answer();
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      await tester.tap(find.text('Accept booking'));
      await tester.pumpAndSettle();
      expect(find.text(sheetTitle), findsOneWidget);
      await tester.tap(inSheet(find.text('UP010345')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [
        {'vehicleId': 'vehicle-1'}
      ]);
    });

    testWidgets(
        'is told when the trip got another truck first, and kept it',
        (tester) async {
      signInAs(office: true);
      final requests = answer(tripTruckAfterAccept: 'KA01AB1234');
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      await tester.tap(inSheet(find.text('KA02XY9999')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [
        {'vehicleId': 'vehicle-2'}
      ]);
      expect(find.text(keptTruckSentence), findsOneWidget);
      expect(find.text('Booking accepted.'), findsNothing,
          reason: 'the office reads which truck the trip has first');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(keptTruckSentence), findsNothing);
      expect(find.text('Booking accepted.'), findsOneWidget);
    });

    testWidgets(
        'is told nothing more when the trip took the chosen truck, however it was typed',
        (tester) async {
      signInAs(office: true);
      answer(tripTruckAfterAccept: 'UP010345');
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      await tester.tap(inSheet(find.text('UP010345')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'vehicle-1 is registered as "UP 1 345"');
      expect(find.text('Booking accepted.'), findsOneWidget);
    });

    testWidgets(
        'and so does the trip screen, whose Truck and driver card then shows that truck',
        (tester) async {
      signInAs(office: true);
      final requests = answer(fleet: {
        ...twoTrucks,
        'drivers': [
          {'userId': 'driver-1', 'displayName': 'Synthetic Driver One'}
        ],
      });
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await tester.tap(find.widgetWithText(TextButton, 'Accept'));
      await tester.pumpAndSettle();
      expect(find.text(sheetTitle), findsOneWidget);
      await tester.tap(inSheet(find.text('KA02XY9999')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(acceptWithTruck));
      await tester.pumpAndSettle();
      expect(requests.acceptBodies, [
        {'vehicleId': 'vehicle-2'}
      ]);
      final truckPicker = tester.widget<DropdownButton<String>>(
          find.descendant(
              of: find.widgetWithText(InputDecorator, 'Truck'),
              matching: find.byType(DropdownButton<String>)));
      expect(truckPicker.value, 'vehicle-2',
          reason: 'the reloaded trip names the truck, so the picker shows it');
    });
  });

  group('Accept with one tap, as before', () {
    testWidgets('for a driver: no sheet and no truck sent', (tester) async {
      signInAs(office: false);
      final requests = answer();
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(find.text(sheetTitle), findsNothing);
      expect(requests.acceptBodies, [null]);
      expect(requests.fleetLoads, 0);
    });

    testWidgets('for the office when the trip already names its truck',
        (tester) async {
      signInAs(office: true);
      final requests =
          answer(shipment: pendingShipment(tripTruck: 'KA02XY9999'));
      await mountScreen(tester, const DriverShipmentsScreen());
      await tapAcceptOnShipmentsList(tester);
      expect(find.text(sheetTitle), findsNothing);
      expect(requests.acceptBodies, [null]);
      expect(requests.fleetLoads, 0);
    });
  });

  test("truck numbers in the portal's form, by the same rule as the server",
      () {
    const cases = {
      'UP 1 345': 'UP010345',
      'UP1345': 'UP010345',
      'UP 32 345': 'UP320345',
      'MH 12 345': 'MH120345',
      'mh-12-345': 'MH120345',
      'KA01AB1234': 'KA01AB1234',
      'ka 01-ab 1234': 'KA01AB1234',
      'MH12A1': 'MH12A0001',
      'DL3CAB1234': 'DL03CAB1234',
      'KA011234': 'KA011234',
      'UP010345': 'UP010345',
      '22 BH 1234 AA': '22BH1234AA',
      'KA01AB12345': 'KA01AB12345',
      'TEST-A': 'TESTA',
    };
    for (final entry in cases.entries) {
      expect(portalTruckNumber(entry.key), entry.value, reason: entry.key);
    }
  });
}
