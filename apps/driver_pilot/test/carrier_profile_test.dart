// The office's Profile and its truck sheet (ca-profile, ca-vehicle-sheet, PR 7 of the redesign): what the
// owner and a dispatcher see, and an empty or failed fleet.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/transporter_id_section.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';

/// A dispatcher holds the office's permissions except the owner's bank one.
const dispatcherAllowed = [
  'trip.assign',
  'trip.publish',
  'load.status_update',
  'organization.member.invite',
];

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Profile (ca-profile, ca-vehicle-sheet)', () {
    testWidgets(
        'the owner sees the company, trucks, drivers, bank details and team',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      expect(find.text('Approved by NaviG8r'), findsOneWidget);
      expect(find.text(transporterIdHelperText), findsOneWidget,
          reason: 'copy.md: tells the transporter ID from the shipper GSTIN');
      expect(
          transporterIdHelperText, contains("It is not the shipper's GSTIN."));
      expect(find.text('Trucks (2)'), findsOneWidget);
      expect(find.text('KA05CD9012'), findsOneWidget);
      expect(find.text('Large truck'), findsOneWidget, reason: 'size in words');
      expect(find.text('Drivers (2)'), findsOneWidget);
      expect(find.text('Synthetic Driver One · Synthetic Driver Two'),
          findsOneWidget);
      expect(find.widgetWithText(NvButton, 'Add driver'), findsOneWidget);
      expect(find.text('Bank details'), findsOneWidget, reason: 'owner only');
      expect(find.text('Team'), findsOneWidget);
      expect(
          find.text(
              'Dispatchers accept bookings and choose drivers. They do not see payments.'),
          findsOneWidget);
      expect(find.text('Sign out'), findsNothing,
          reason: 'the account menu under the header signs out');
      expect(find.textContaining('Publish'), findsNothing,
          reason: 'the office has an Add trip tab; no developer or publish rows');
      expect(find.textContaining('Add a trip'), findsNothing,
          reason: 'the office has an Add trip tab; no add-a-trip row here');
    });

    testWidgets(
        'a fleet that failed to load says so, and never reads as an empty fleet',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, fleetFails: true));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      expect(find.text('Trucks'), findsOneWidget,
          reason: 'no count when the fleet did not load');
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: "the person's own truck is known without the fleet");
      expect(find.text('Could not load your trucks.'), findsOneWidget);
      expect(find.text('Drivers'), findsOneWidget,
          reason: 'no count when the fleet did not load');
      expect(find.text('Could not load your drivers.'), findsOneWidget,
          reason: 'the drivers card says it failed too');
      expect(find.widgetWithText(NvButton, 'Try again'), findsNWidgets(2),
          reason: 'each card offers a retry');
      expect(find.text('No drivers yet.'), findsNothing,
          reason: 'a failed load is not an empty fleet');
      expect(find.text('You have no trucks yet.'), findsNothing,
          reason: 'a failed load is not an empty fleet');
      expect(find.textContaining('(0)'), findsNothing);
    });

    testWidgets('an office with no trucks or drivers is told how to add them',
        (tester) async {
      signInWith(
          Server(allowed: ownerAllowed, ownTruck: false, emptyFleet: true));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      expect(find.text('Trucks (0)'), findsOneWidget);
      expect(find.text('You have no trucks yet.'), findsOneWidget,
          reason: 'ca-profile: the empty fleet, said plainly');
      expect(find.text('To add a truck, add its driver with Add driver.'),
          findsOneWidget,
          reason: 'copy.md: how a truck gets added');
      expect(find.text('No drivers yet.'), findsOneWidget,
          reason: 'copy.md: the empty drivers card');
    });

    testWidgets('a dispatcher profile has no bank section and no payment link',
        (tester) async {
      signInWith(Server(allowed: dispatcherAllowed));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      expect(find.text('Trucks (2)'), findsOneWidget,
          reason: 'the screen loaded');
      expect(find.text('Bank details'), findsNothing,
          reason: 'copy.md: bank details owner only');
      expect(find.text('Earnings and payments'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets("only the person's own truck opens, and its size is a choice",
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      await tester.tap(find.text('KA05CD9012'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'another truck cannot be changed from the app');

      await tester.tap(find.text('KA01AB1234'));
      await tester.pumpAndSettle();
      expect(inSheet(find.text('Truck')), findsOneWidget);
      expect(inSheet(find.text('Registration number')), findsOneWidget);
      expect(
          inSheet(find.text(
              'Type it as on your registration certificate (RC). We remove the spaces for the e-way bill.')),
          findsOneWidget);
      expect(inSheet(find.text('[Size guide from the team]')), findsNWidgets(3),
          reason: 'the size guide placeholder from pending_copy.dart');
      expect(
          tester
              .widget<RadioListTile<String>>(find.ancestor(
                  of: inSheet(find.text('Large')),
                  matching: find.byType(RadioListTile<String>)))
              .groupValue,
          'MEDIUM',
          reason: "the truck's saved size");
      expect(find.text('Remove truck'), findsNothing,
          reason: 'no endpoint removes a truck (RECON gap 25)');
      await tester.tap(inSheet(find.text('Large')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Save truck')));
      await tester.pumpAndSettle();
      expect(server.sent.single.path, '/v1/pilot/me/vehicle');
      expect(server.sent.single.data, {
        'vehicleRegistrationNumber': 'KA01AB1234',
        'vehicleClass': 'LARGE',
        'vehicleCapacityKg': 1000.0,
      });
      expect(find.byType(BottomSheet), findsNothing,
          reason: 'closes after saving');
    });

    testWidgets(
        "with no truck of the owner's own, the fleet's trucks show, not an empty field",
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, ownTruck: false));
      await mount(tester, const DriverProfileScreen(),
          size: const Size(800, 3000));
      expect(find.text('Trucks (2)'), findsOneWidget);
      expect(find.text('KA01AB1234'), findsOneWidget);
      expect(find.text('KA05CD9012'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'brief section 4: the list, not an empty registration field');
    });
  });
}
