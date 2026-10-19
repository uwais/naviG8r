// PR 7 of the redesign: the office's Trips list, trip screen with the start sheet, Publish and Profile
// (mockups ca-trips, ca-trip, ca-assign, ca-start, ca-publish, ca-profile, ca-vehicle-sheet).
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/transporter_id_section.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

const ownerAllowed = [
  'trip.assign',
  'trip.publish',
  'load.status_update',
  'eway_bill.add_truck',
  'organization.member.invite',
  'transporter_id.write',
  'bank_account.create_token',
];

/// A dispatcher holds the office's permissions except the owner's bank one.
const dispatcherAllowed = [
  'trip.assign',
  'trip.publish',
  'load.status_update',
  'eway_bill.add_truck',
  'organization.member.invite',
];

final thisYear = DateTime.now().year;

Map<String, dynamic> tripAt(String id,
        {String status = 'OPEN',
        int reservedKg = 975,
        Map<String, dynamic> assigned = const {},
        int startDay = 18}) =>
    {
      'id': id,
      'originCity': 'Bengaluru',
      'destCity': 'Chennai',
      'windowStart':
          '$thisYear-10-${startDay.toString().padLeft(2, '0')}T00:00:00+05:30',
      'windowEnd':
          '$thisYear-10-${(startDay + 1).toString().padLeft(2, '0')}T23:59:59+05:30',
      'vehicleClass': 'MEDIUM',
      'capacityKg': 1000,
      'reservedKg': reservedKg,
      'status': status,
      ...assigned,
    };

const truckAndDriver = {
  'assignedVehicleId': 'vehicle-1',
  'assignedTruckNumber': 'KA01AB1234',
  'assignedDriverUserId': 'driver-1',
  'assignedDriverName': 'Synthetic Driver One',
};

Map<String, dynamic> bookingOn(String tripId, String id,
        {required String shipper,
        required int weightKg,
        String status = 'BOOKED',
        Map<String, dynamic>? bill}) =>
    {
      'id': id,
      'anchorTripId': tripId,
      'status': status,
      'customerOrgName': shipper,
      'weightKg': weightKg,
      'pickupAddress': 'Peenya',
      'dropAddress': 'Guindy',
      if (bill != null) 'ewayBill': bill,
    };

const fleet = {
  'vehicles': [
    {
      'id': 'vehicle-1',
      'registrationNumber': 'KA01AB1234',
      'vehicleClass': 'MEDIUM'
    },
    {
      'id': 'vehicle-3',
      'registrationNumber': 'KA05CD9012',
      'vehicleClass': 'LARGE'
    },
  ],
  'drivers': [
    {'userId': 'driver-1', 'displayName': 'Synthetic Driver One'},
    {'userId': 'driver-2', 'displayName': 'Synthetic Driver Two'},
  ],
};

/// What the carrier screens ask for, and the requests they sent.
class Server {
  Server(
      {required this.allowed,
      this.office = true,
      this.trips = const [],
      this.bookings = const [],
      this.ownTruck = true,
      this.refusesWrites = false,
      this.fleetFails = false,
      this.emptyFleet = false});
  final List<String> allowed;
  final bool office;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> bookings;
  final bool ownTruck;

  /// Every write is answered with a 409 and a code the app has no sentence for.
  final bool refusesWrites;

  /// The fleet request is answered with a 500, as when the server is down.
  final bool fleetFails;

  /// The fleet loads with no trucks and no drivers.
  final bool emptyFleet;
  final sent = <RequestOptions>[];

  void answer() {
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.method != 'GET') {
        sent.add(request);
        if (refusesWrites) {
          return jsonResponse({'error': 'trip_not_startable'}, 409);
        }
        return jsonResponse({
          'trip':
              trips.isEmpty ? null : {...trips.first, 'status': 'IN_PROGRESS'}
        });
      }
      switch (request.path) {
        case '/v1/auth/me':
          return jsonResponse({
            'user': {'id': 'carrier-person', 'fullName': 'Synthetic Person'},
            'organizations': [carrierOrganization],
            'principal': carrierPrincipal(office: office, alsoAllowed: allowed),
          });
        case '/v1/pilot/me':
          return jsonResponse({
            'organizations': [
              {...carrierOrganization, 'transporterId': '29ABCDE1234F1Z5'}
            ],
            'driverProfile': {'primaryVehicleId': ownTruck ? 'vehicle-1' : ''},
            'vehicles': [
              if (ownTruck)
                {
                  'id': 'vehicle-1',
                  'registrationNumber': 'KA01AB1234',
                  'vehicleClass': 'MEDIUM',
                  'capacityKg': 1000
                }
            ],
          });
        case '/v1/pilot/carrier/fleet':
          if (fleetFails) return jsonResponse({'error': 'internal_error'}, 500);
          return jsonResponse(
              emptyFleet ? {'vehicles': [], 'drivers': []} : fleet);
        case '/v1/pilot/anchor-trips':
          return jsonResponse({'trips': trips});
        case '/v1/pilot/carrier/shipments':
          return jsonResponse({'shipments': bookings});
      }
      if (request.path.startsWith('/v1/pilot/anchor-trips/')) {
        return jsonResponse({'trip': trips.first});
      }
      return jsonResponse({'error': 'not_found'}, 404);
    });
  }
}

Server signInWith(Server server) {
  signInAsCarrierLogin(office: server.office, alsoAllowed: server.allowed);
  server.answer();
  return server;
}

/// The screen under a router, so cards and buttons can open other screens, at [size] (a phone by default) and
/// [textScale] (1 is the phone's default text size).
Future<GoRouter> mount(WidgetTester tester, Widget screen,
    {Size size = const Size(360, 800), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/screen', routes: [
    GoRoute(path: '/screen', builder: (_, __) => Scaffold(body: screen)),
    GoRoute(
        path: '/driver/:rest(.*)',
        builder: (_, state) =>
            Scaffold(body: Text('Opened ${state.uri.path}'))),
  ]);
  await tester.pumpWidget(MaterialApp.router(
      theme: DriverTheme.theme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!)));
  await tester.pumpAndSettle();
  return router;
}

/// Every word on screen, sheets and snackbars included.
String screenWords(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

final sizeCodes = RegExp(r'\b(SMALL|MEDIUM|LARGE)\b');

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Trips list (ca-trips)', () {
    final trips = [
      tripAt('trip-open',
          assigned: const {'assignedTruckNumber': 'KA01AB1234'}),
      tripAt('trip-full',
          status: 'FULL',
          reservedKg: 1000,
          assigned: truckAndDriver,
          startDay: 19),
      tripAt('trip-new', reservedKg: 0, startDay: 20),
      tripAt('trip-moving', status: 'IN_PROGRESS', assigned: truckAndDriver),
    ];
    final bookings = [
      for (final id in ['a', 'b', 'c'])
        bookingOn('trip-open', id, shipper: 'Shipper $id', weightKg: 100),
    ];

    testWidgets('cards show the trip as the mockup does, under Open first',
        (tester) async {
      signInWith(
          Server(allowed: ownerAllowed, trips: trips, bookings: bookings));
      await mount(tester, const DriverLoadsScreen());
      for (final chip in ['Open', 'In transit', 'Done']) {
        expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget,
            reason: 'copy.md Trips list chips');
      }
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Open'))
              .selected,
          isTrue,
          reason: 'ca-trips opens on Open');
      expect(find.text('Bengaluru to Chennai'), findsNWidgets(3),
          reason: 'the open and full trips, not the one in transit');
      expect(find.text('18 – 19 Oct'), findsOneWidget, reason: 'Dates fact');
      expect(find.text('25 kg'), findsOneWidget,
          reason: 'Room left 1000 - 975');
      expect(find.text('None'), findsOneWidget,
          reason: 'a full trip has no room');
      expect(find.text('3'), findsOneWidget, reason: 'Bookings count');
      expect(find.text('KA01AB1234 · No driver yet'), findsOneWidget);
      expect(find.text('KA01AB1234 · Synthetic Driver One'), findsOneWidget);
      expect(find.text('Truck chosen when you accept the first booking'),
          findsOneWidget,
          reason: 'copy.md: an open trip with no truck yet');
      expect(find.text('Full'), findsOneWidget, reason: 'status word');

      await tester.tap(find.widgetWithText(ChoiceChip, 'In transit'));
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
    });

    testWidgets(
        'trip cards contain no Start or View: the whole card opens the trip',
        (tester) async {
      signInWith(
          Server(allowed: ownerAllowed, trips: trips, bookings: bookings));
      await mount(tester, const DriverLoadsScreen());
      for (final chip in ['Open', 'In transit', 'Done']) {
        await tester.tap(find.widgetWithText(ChoiceChip, chip));
        await tester.pumpAndSettle();
        expect(find.textContaining('Start'), findsNothing,
            reason:
                'spec/decisions.md: a slip on the list started trips ($chip)');
        expect(find.textContaining('View'), findsNothing, reason: chip);
        expect(find.byType(FilledButton), findsNothing, reason: chip);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25 kg'));
      await tester.pumpAndSettle();
      expect(find.text('Opened /driver/trip/trip-open/active'), findsOneWidget,
          reason: 'the card is its only tap target, and it opens the trip');
    });
  });

  group('Trip screen (ca-trip, ca-start)', () {
    final mehta = bookingOn('trip-a', 'mehta',
        shipper: 'Mehta Hardware',
        weightKg: 400,
        bill: {'kind': 'BILL', 'billNumber': '123456789012'});
    final sharma = bookingOn('trip-a', 'sharma',
        shipper: 'Sharma Textiles',
        weightKg: 80,
        bill: {
          'kind': 'BILL',
          'billNumber': '123456789013',
          'truckNumber': 'KA01AB1234'
        });

    testWidgets('names the trip, its room and its bookings as the mockup does',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        tripAt('trip-a', assigned: const {'assignedTruckNumber': 'KA01AB1234'})
      ], bookings: [
        sharma
      ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
          size: const Size(800, 2000));
      expect(find.text('TRIP'), findsOneWidget);
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('18 – 19 Oct · Medium truck'), findsOneWidget);
      expect(find.text('Room left: 25 kg of 1,000 kg'), findsOneWidget,
          reason:
              'copy.md: Room left: [n] kg of [capacity] kg; mockup ca-trip groups thousands, "1,000 kg"');
      expect(find.text('Truck and driver'), findsOneWidget);
      expect(find.text('Bookings on this trip (1)'), findsOneWidget);
      expect(find.text('Sharma Textiles · 80 kg'), findsOneWidget);
    });

    testWidgets('Start is disabled with its reason until a driver is assigned',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        tripAt('trip-a', assigned: const {'assignedTruckNumber': 'KA01AB1234'})
      ], bookings: [
        sharma
      ]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Start trip'))
              .onPressed,
          isNull);
      expect(find.text('Assign a driver first. Then start on loading day.'),
          findsOneWidget,
          reason: 'copy.md Start (disabled)');
      expect(find.text('Start the trip'), findsOneWidget,
          reason:
              'copy.md Start (disabled) and ca-trip: the block has a heading');
    });

    for (final (who, driver, shares) in [
      ('an office phone', 'driver-1', false),
      ('an owner who drives the trip', 'carrier-person', true),
    ]) {
      testWidgets('a trip in transit on $who: location shared is $shares',
          (tester) async {
        final location = CountingLocation();
        GeolocatorPlatform.instance = location;
        signInWith(Server(allowed: ownerAllowed, trips: [
          tripAt('trip-a',
              status: 'IN_PROGRESS',
              assigned: {...truckAndDriver, 'assignedDriverUserId': driver})
        ], bookings: [
          sharma
        ]));
        await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
            size: const Size(800, 2000));
        expect(location.permissionChecks > 0, shares,
            reason:
                "only the phone in the truck sends its position as the truck's");
        expect(
            find.text(
                'Your location is shared with the shippers while this trip is in transit.'),
            shares ? findsOneWidget : findsNothing,
            reason: 'whoever shares is told so, and nobody else is');
      });
    }

    testWidgets('Start opens the sheet before any request; the sheet sends it',
        (tester) async {
      final server = signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma, mehta]));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      final start = find.widgetWithText(FilledButton, 'Start trip');
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect((Offset.zero & view).contains(tester.getRect(start).bottomRight),
          isTrue,
          reason:
              'success criterion: primary action visible without scrolling at 360 x 800');
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty,
          reason: 'decisions.md: Start only behind the confirm sheet');
      expect(find.text('Start Bengaluru to Chennai now?'), findsOneWidget);
      expect(inSheet(find.text('KA01AB1234')), findsOneWidget);
      expect(inSheet(find.text('Synthetic Driver One')), findsOneWidget);
      expect(inSheet(find.text('2 · 480 kg')), findsOneWidget,
          reason: 'Bookings row');
      expect(
          inSheet(find
              .text('Starting tells each shipper their goods are on the way.')),
          findsOneWidget);

      await tester.tap(inSheet(find.text('Not yet')));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty, reason: 'Not yet starts nothing');

      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(server.sent.map((request) => request.path),
          ['/v1/pilot/anchor-trips/trip-a/start']);
      expect(
          find.text(
              'Trip started. Shippers are told their goods are on the way.'),
          findsOneWidget,
          reason: 'accessibility.md: Start trip announcement');
    });

    testWidgets('a refused Start says so in plain words, never HTTP text',
        (tester) async {
      signInWith(Server(
          allowed: ownerAllowed,
          trips: [tripAt('trip-a', assigned: truckAndDriver)],
          bookings: [sharma],
          refusesWrites: true));
      await mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
      await tester.pumpAndSettle();
      await tester
          .tap(inSheet(find.widgetWithText(FilledButton, 'Start trip')));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget,
          reason: 'a refusal with no sentence of its own gets the plain one');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: never "HTTP 409: {…}"');
      expect(find.textContaining('trip_not_startable'), findsNothing,
          reason: 'no raw codes in the UI');
    });

    testWidgets(
        "the missing-truck warning shows only when a booking's bill lacks the truck",
        (tester) async {
      for (final withMissingTruck in [true, false]) {
        signInWith(Server(
            allowed: ownerAllowed,
            trips: [tripAt('trip-a', assigned: truckAndDriver)],
            bookings: [sharma, if (withMissingTruck) mehta]));
        await mount(
            tester,
            DriverActiveTripScreen(
                key: ValueKey(withMissingTruck), tripId: 'trip-a'));
        await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
        await tester.pumpAndSettle();
        const warning =
            "Mehta Hardware's e-way bill does not have the truck yet.";
        expect(find.text(warning),
            withMissingTruck ? findsOneWidget : findsNothing,
            reason: 'decisions.md: warning only when true');
        expect(find.text('Add the truck first'),
            withMissingTruck ? findsOneWidget : findsNothing);
        expect(inSheet(find.textContaining('Sharma Textiles')), findsNothing,
            reason: "Sharma's bill has the truck");
        if (withMissingTruck) {
          await tester.tap(find.text('Add the truck first'));
          await tester.pumpAndSettle();
          expect(find.text('Opened /driver/shipment/mehta'), findsOneWidget,
              reason: 'opens the booking whose bill needs the truck');
        }
      }
    });
  });

  group('Publish (ca-publish)', () {
    testWidgets('every field starts empty and nothing is chosen',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      // Tall enough that the whole list is built.
      await mount(tester, const DriverPublishTripScreen(),
          size: const Size(800, 3000));
      final placeFields = tester.widgetList<TextField>(find.descendant(
          of: find.byType(LocationEndpointEditor),
          matching: find.byType(TextField)));
      expect(placeFields.map((field) => field.controller!.text), ['', ''],
          reason:
              'spec: From and To start empty (the mockup shows them filled)');
      expect(find.text('Choose a date'), findsNWidgets(2),
          reason: 'Leaves and Arrives by start empty');
      expect(
          tester
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .where((chip) => chip.selected),
          isEmpty,
          reason: 'truck size: nothing preselected');
      expect(find.widgetWithText(ChoiceChip, 'Medium'), findsOneWidget,
          reason: 'truck size is a chip choice');
      final room = find.descendant(
          of: find.widgetWithText(Column, 'Room for shippers'),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(room.first).controller!.text, isEmpty);
      expect(find.text('The weight you can carry for shippers on this trip.'),
          findsOneWidget);
      expect(
          find.text('You choose the truck when you accept the first booking.'),
          findsOneWidget);

      await mount(
          tester, const DriverPublishTripScreen(key: ValueKey('phone')));
      final publish = find.widgetWithText(FilledButton, 'Publish trip');
      expect(
          (Offset.zero & const Size(360, 800))
              .contains(tester.getRect(publish).bottomRight),
          isTrue,
          reason:
              'success criterion: primary action visible without scrolling');
    });

    testWidgets(
        'Publish with nothing filled sends nothing and says what is missing',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverPublishTripScreen());
      await tester.tap(find.widgetWithText(FilledButton, 'Publish trip'));
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty);
      expect(
          find.text(
              'Search for the From place so shippers can find this trip.'),
          findsOneWidget);
    });

    testWidgets('no map shows until its place is found', (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.ok(
                  const LatLng(12.97, 77.59), 'Bengaluru, Karnataka')),
          size: const Size(800, 3000));
      expect(find.byType(GoogleMap), findsNothing,
          reason: 'tester: the maps left no room while typing');
      expect(
          find.text('Drag the pin to fine-tune. Use search to jump to a place.'),
          findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Bengaluru');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsOneWidget,
          reason: 'From has a point, To does not yet');
      expect(find.text('Bengaluru, Karnataka'), findsWidgets);
    });

    testWidgets('a place search that finds nothing still opens the map to drag the pin',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester,
          DriverPublishTripScreen(
              findPlace: (place) async => GeocodeOutcome.fail('ZERO_RESULTS')),
          size: const Size(800, 3000));
      await tester.enterText(find.byType(TextField).first, 'Kurudumale');
      await tester.tap(find.byTooltip('Look up place').first);
      await tester.pumpAndSettle();
      expect(find.byType(GoogleMap), findsOneWidget,
          reason: 'without the map, a place Google cannot find could never be set');
      expect(
          find.text(
              'Could not find this place. Try a nearby town, or drag the pin on the map to it.'),
          findsOneWidget);
      expect(find.textContaining('ZERO_RESULTS'), findsNothing,
          reason: 'no raw codes');
    });

    testWidgets(
        'at 360 by 640 with the keyboard open the form scrolls, and Publish and its message are reachable',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await mount(tester, const DriverPublishTripScreen(),
          size: const Size(360, 640));
      const aboveKeyboard = Rect.fromLTWH(0, 0, 360, 340);
      bool shown(Finder finder) {
        final rect = tester.getRect(finder);
        return aboveKeyboard.contains(rect.topLeft) &&
            aboveKeyboard.contains(rect.bottomRight);
      }

      final publish = find.widgetWithText(FilledButton, 'Publish trip');
      expect(shown(publish), isTrue,
          reason: 'the bottom bar sits above the keyboard');

      final form = find.byType(Scrollable).first;
      const lastLine = 'You choose the truck when you accept the first booking.';
      await tester.scrollUntilVisible(find.text(lastLine), 100,
          scrollable: form);
      await tester.pumpAndSettle();
      final room = find.descendant(
          of: find.widgetWithText(Column, 'Room for shippers'),
          matching: find.byType(TextField));
      expect(shown(room.first), isTrue,
          reason: 'the last field can be reached with the keyboard open');
      expect(tester.state<ScrollableState>(form).position.pixels,
          greaterThan(0));

      await tester.showKeyboard(room.first);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.drag(form, const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'dragging the form closes the keyboard');

      await tester.ensureVisible(find.text(lastLine));
      await tester.showKeyboard(room.first);
      await tester.tap(find.text(lastLine));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse,
          reason: 'a tap outside the fields closes the keyboard');

      await tester.tap(publish);
      await tester.pumpAndSettle();
      final message = find.text(
          'Search for the From place so shippers can find this trip.');
      expect(shown(message), isTrue,
          reason: 'the form scrolls the message into view');
      expect(
          find.descendant(of: find.byType(NvActionBar), matching: message),
          findsNothing,
          reason: 'the bottom bar holds only Publish trip');
      expect(server.sent, isEmpty);
    });
  });

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
              'Dispatchers accept bookings and assign drivers. They do not see payments.'),
          findsOneWidget);
      expect(find.text('Sign out'), findsNothing,
          reason: 'the account menu under the header signs out');
      expect(find.textContaining('Publish'), findsNothing,
          reason: 'the office has a Publish tab; no developer or publish rows');
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
      expect(find.text('A truck is added with its driver: use Add driver.'),
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
      expect(find.text('Earnings & payouts'), findsNothing);
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
              'As on the registration certificate. Spaces are removed for the e-way bill.')),
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

  group('Truck sizes are words, never SMALL, MEDIUM or LARGE', () {
    Future<void> expectNoSizeCodes(WidgetTester tester, String where) async {
      final words = screenWords(tester);
      expect(sizeCodes.hasMatch(words), isFalse, reason: '$where: $words');
    }

    testWidgets(
        'on Publish, Profile, the truck sheet, fleet invite and sign-up',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester, const DriverPublishTripScreen(key: ValueKey('publish')));
      await expectNoSizeCodes(tester, 'Publish');
      await mount(tester, const DriverProfileScreen(key: ValueKey('profile')),
          size: const Size(800, 3000));
      await expectNoSizeCodes(tester, 'Profile');
      await tester.tap(find.text('KA01AB1234'));
      await tester.pumpAndSettle();
      await expectNoSizeCodes(tester, 'Truck sheet');
      await mount(
          tester, const DriverFleetInviteScreen(key: ValueKey('invite')),
          size: const Size(800, 2000));
      await expectNoSizeCodes(tester, 'Fleet invite');
      await mount(tester, const DriverRegisterScreen(key: ValueKey('register')),
          size: const Size(800, 2000));
      await expectNoSizeCodes(tester, 'Sign-up');
    });

    testWidgets('inviting a driver asks for a size instead of sending MEDIUM',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverFleetInviteScreen(),
          size: const Size(800, 2000));
      expect(
          tester
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .where((chip) => chip.selected),
          isEmpty,
          reason: 'nothing preselected, the role included');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Driver or Dispatcher.'), findsOneWidget,
          reason: 'decisions.md guardrail 6: the role is chosen, not assumed');
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(
                  find.widgetWithText(TextField, 'Vehicle capacity (kg)'))
              .controller
              ?.text,
          isEmpty,
          reason: 'decisions.md guardrail 6: no capacity filled in for them');
      await tester.tap(find.text('Invite driver'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a truck size.'), findsOneWidget);
      await tester.tap(find.text('Medium'));
      await tester.tap(find.text('Invite driver'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a positive vehicle capacity.'), findsOneWidget,
          reason: 'an empty capacity is asked for, not sent as 0');
      expect(server.sent, isEmpty);
    });
  });

  testWidgets('the four screens and both sheets fit 360 dp at 200% text',
      (tester) async {
    final server = signInWith(Server(allowed: ownerAllowed, trips: [
      tripAt('trip-a', assigned: truckAndDriver)
    ], bookings: [
      bookingOn('trip-a', 'mehta',
          shipper: 'Mehta Hardware',
          weightKg: 400,
          bill: {'kind': 'BILL', 'billNumber': '123456789012'})
    ]));
    Future<void> expectNoOverflow(String where) async {
      expect(tester.takeException(), isNull,
          reason: 'brief 7: 200% text, $where');
    }

    await mount(tester, const DriverLoadsScreen(key: ValueKey('trips')),
        textScale: 2);
    await expectNoOverflow('Trips');
    await mount(tester,
        const DriverActiveTripScreen(key: ValueKey('trip'), tripId: 'trip-a'),
        textScale: 2);
    await expectNoOverflow('Trip');
    await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
    await tester.pumpAndSettle();
    await expectNoOverflow('Start sheet');
    expect(server.sent, isEmpty);
    await tester.ensureVisible(find.text('Not yet'));
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Assign driver'), 200);
    await tester.tap(find.text('Assign driver'));
    await tester.pumpAndSettle();
    await expectNoOverflow('Assign sheet');
    await mount(tester, const DriverPublishTripScreen(key: ValueKey('publish')),
        textScale: 2);
    await expectNoOverflow('Publish');
    await mount(tester, const DriverProfileScreen(key: ValueKey('profile')),
        textScale: 2);
    await expectNoOverflow('Profile');
  });

  test(
      'screen titles: the office trip names itself, Publish and Company as in the mockups',
      () {
    expect(driverShellTitle('/driver/trip/t/active'), '',
        reason: 'ca-trip: TRIP over the route, no shell title');
    expect(driverShellTitle('/driver/trip/t/active', forDriver: true), '',
        reason: 'PR 8, dr-trip: the route names the driver trip screen');
    expect(driverShellTitle('/driver/trip/t/eway-bills', forDriver: true), '',
        reason: 'PR 8, dr-ewb: "E-way bills" beside the truck names the screen');
    expect(driverShellTitle('/driver/publish'), 'Publish a trip');
    expect(driverShellTitle('/driver/profile'), 'Company');
    expect(driverShellTitle('/driver/profile', forDriver: true), 'Profile');
  });
}

/// A widget test has no location service. Starting a trip asks for one; this one says it is off for good.
class NoLocation extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;
}

/// [NoLocation] that counts how often the screen asked, which it does only when it means to share.
class CountingLocation extends NoLocation {
  int permissionChecks = 0;

  @override
  Future<LocationPermission> checkPermission() {
    permissionChecks++;
    return super.checkPermission();
  }
}
