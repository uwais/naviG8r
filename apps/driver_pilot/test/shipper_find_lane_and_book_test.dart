// PR 4 of the redesign: the shipper Home, Find a lane, and Book with the full price before paying
// (sh-home, sh-lanes-*, sh-book-*). Names, places and amounts are the mockups' synthetic ones.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/book_a_lane.dart';
import 'package:driver_pilot/shipper/find_a_lane.dart';
import 'package:driver_pilot/shipper/place_input.dart';
import 'package:driver_pilot/shipper/shipper_home.dart';
import 'package:driver_pilot/shipper/shipper_routes.dart';
import 'package:driver_pilot/customer_layout.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:driver_pilot/ui/nv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_screen_checks.dart';

Map<String, dynamic> lane(
        {String id = 'lane-1',
        String from = 'Bengaluru',
        String to = 'Chennai',
        String carrier = 'Ravi Roadways',
        num capacityKg = 1000,
        num reservedKg = 895,
        String status = 'OPEN'}) =>
    {
      'id': id,
      'originCity': from,
      'destCity': to,
      'carrierDisplayName': carrier,
      'vehicleClass': 'MEDIUM',
      'capacityKg': capacityKg,
      'reservedKg': reservedKg,
      'status': status,
      'windowStart': '2026-10-18T03:30:00.000Z',
      'windowEnd': '2026-10-19T12:00:00.000Z',
      'origin': {'lat': 12.97, 'lng': 77.59},
      'destination': {'lat': 13.08, 'lng': 80.27},
    };

/// What the fake server answers, by path; anything else is an empty 200.
class FakeServer {
  final requests = <RequestOptions>[];
  final answers = <String, ResponseBody Function(RequestOptions)>{};

  int countOf(String path) =>
      requests.where((request) => request.uri.path == path).length;

  void answer(String path, Object body, [int status = 200]) =>
      answers[path] = (_) => jsonResponse(body, status);
}

Future<GeocodeOutcome> findAnyPlace(String place) async =>
    GeocodeOutcome.ok(const LatLng(12.8, 77.7), place);

/// A phone 360 dp wide, or [width] for the desktop layout. [height] is 800 for "visible without
/// scrolling" checks; taller elsewhere, because the test font draws every letter a full square
/// wide and lists build only what shows.
Future<FakeServer> showShipperApp(WidgetTester tester, String start,
    {double height = 2000,
    double width = 360,
    PlaceFinder findPlace = findAnyPlace}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  CustomerSession.skipRefreshInTests = true;
  addTearDown(() => CustomerSession.skipRefreshInTests = false);
  CustomerSession.applyForTest(
      userFullName: 'Priya Raman',
      userPhone: '9845012345',
      customerOrgId: 'org-sharma',
      customerOrgName: 'Sharma Textiles',
      customerRole: 'CUSTOMER_MEMBER');
  // What every shipper holds on the server (api/rbac.ts), beyond applyForTest's defaults.
  AuthorizationSession.principal!['permissions'] = [
    ...AuthorizationSession.principal!['permissions'] as List,
    'eway_bill.write',
    'eway_bill.add_truck',
    'notification.read',
  ];
  api.selectOrganization('org-sharma');
  final server = FakeServer();
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    server.requests.add(request);
    final answer = server.answers[request.uri.path];
    return answer == null ? jsonResponse({}) : answer(request);
  });
  final router = GoRouter(initialLocation: start, routes: [
    GoRoute(
        path: '/customer',
        builder: (_, __) => const CustomerHomeScreen(),
        routes: [
          GoRoute(
              path: 'trips',
              builder: (_, state) => CustomerTripsScreen(
                  startWithMatch: state.uri.queryParameters['tab'] == 'match',
                  findPlace: findPlace)),
          GoRoute(
              path: 'book',
              builder: (_, state) => CustomerBookShipmentScreen.fromQuery(
                  state.uri.queryParameters,
                  findPlace: findPlace)),
          GoRoute(
              path: 'shipments',
              builder: (_, __) => const Text('Shipments list')),
          GoRoute(
              path: 'shipments/:id',
              // A Scaffold, as the real shipment screen has, so a snack bar shown on arrival appears.
              builder: (_, state) => Scaffold(
                  body: Text('Shipment ${state.pathParameters['id']}'))),
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  return server;
}

/// The text box inside the NvField labelled [label].
Finder field(String label) => find.descendant(
    of: find.widgetWithText(NvField, label), matching: find.byType(TextField));

/// Book for lane-1 as a lane card opens it after a match search for 80 kg.
const searchedBook =
    '/customer/book?anchorTripId=lane-1&weightKg=80&pickup=Bommasandra%2C+Bengaluru&pickupLat=12.8&pickupLng=77.7&drop=Guindy%2C+Chennai&dropLat=13.0&dropLng=80.2';

Future<FakeServer> showPricedBook(WidgetTester tester,
    {double height = 2000, double width = 360}) async {
  final server =
      await showShipperApp(tester, searchedBook, height: height, width: width);
  server.answer('/anchor-trips/lane-1', {'trip': lane()});
  server.answer('/shipments/quote', {
    'quote': {'grossPaise': 264000}
  });
  await tester.pumpAndSettle();
  await tester.tap(find.text('Get price'));
  await tester.pumpAndSettle();
  return server;
}

void main() {
  group('Home', () {
    testWidgets('the first task that needs the shipper comes first',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'waiting',
            'status': 'PENDING_CARRIER_ACCEPT',
            'carrierDisplayName': 'Deccan Movers'
          },
          {
            'id': 'needs-bill',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways',
            'pickupAddress': 'Bommasandra, Bengaluru',
            'dropAddress': 'Guindy, Chennai',
            'assignedTruckNumber': 'KA01AB1234',
          },
        ]
      });
      await tester.pumpAndSettle();

      expect(find.text('NEEDS YOU'), findsOneWidget,
          reason: 'sh-home: the needs-you card leads Home');
      expect(find.text('Make the e-way bill'), findsOneWidget,
          reason: 'copy.md: the card names the task');
      expect(
          find.text(
              'Bommasandra, Bengaluru to Guindy, Chennai. Ravi Roadways accepted and named the truck.'),
          findsOneWidget,
          reason: 'copy.md: the card says which shipment and who did what');
      expect(find.widgetWithText(FilledButton, 'Open shipment'), findsOneWidget,
          reason: 'screens.md: the first needs-you task is the primary action');
      expect(find.widgetWithText(OutlinedButton, 'Find a lane for new goods'),
          findsOneWidget,
          reason: 'with a task waiting, Find a lane steps back');
      expect(find.text('Waiting for carrier'), findsOneWidget,
          reason: 'sh-home: Your shipments counts by status word');

      await tester.tap(find.text('Open shipment'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment needs-bill'), findsOneWidget,
          reason: 'Open shipment opens the shipment the task is on');
    });

    testWidgets('with nothing to do, Find a lane is the primary action',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      expect(find.text('NEEDS YOU'), findsNothing,
          reason: 'copy.md: nothing needs you, the card is hidden');
      expect(find.widgetWithText(FilledButton, 'Find a lane for new goods'),
          findsOneWidget,
          reason: 'copy.md: Find a lane becomes primary');
      await tester.tap(find.text('Find a lane for new goods'));
      await tester.pumpAndSettle();
      expect(find.text('Find a lane'), findsWidgets,
          reason: 'the button opens Find a lane');
    });

    testWidgets(
        'Home has an Updates row instead of a bell, and no Book or Sign out of its own',
        (tester) async {
      final server = await showShipperApp(tester, '/customer');
      server.answer(
          '/v1/notifications/shipments', {'shipments': [], 'unreadCount': 2});
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsWidgets, reason: 'sh-home: titled Home');
      expect(find.byType(NotificationBell), findsNothing,
          reason: 'screens.md: the Updates row replaces the bell');
      expect(find.text('Book a shipment'), findsNothing,
          reason: 'decisions.md: no Book with no lane');
      expect(find.text('Sign out'), findsNothing,
          reason: 'the account menu is the one place to sign out');
      expect(find.text('Book freight'), findsNothing,
          reason: 'the old Home title is gone');
      expect(find.text('Updates'), findsOneWidget,
          reason: 'copy.md: the Updates row on Home');
      expect(find.text('2 new'), findsOneWidget,
          reason: 'the row says how many updates are unread');

      await tester.tap(find.text('Updates'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxScreen), findsOneWidget,
          reason: 'screens.md: notifications open from the Updates row');
      // Closes the inbox, whose 30 second poll would otherwise outlive the test.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Find a lane', () {
    testWidgets(
        'Browse shows lane cards with route, carrier, size and room left, unsorted',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips');
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(
              id: 'lane-2',
              to: 'Hyderabad',
              carrier: 'Deccan Movers',
              reservedKg: 1000,
              status: 'FULL'),
        ]
      });
      await tester.pumpAndSettle();

      expect(find.text('Pick a lane going your way.'), findsOneWidget,
          reason: 'copy.md: lanes sub');
      expect(
          find.text(
              'Every lane, whatever its status, not sorted by distance. To see the closest to your route first, use Match my route.'),
          findsOneWidget,
          reason:
              'copy.md: Browse is not ranked and says so; it lists full and finished lanes too (RECON gap 19), so it never says "open"');
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'copy.md: lane card route');
      expect(find.text('Ravi Roadways · Medium truck'), findsOneWidget,
          reason: 'copy.md: carrier and size on the card');
      expect(find.text('Leaves'), findsNWidgets(2),
          reason: 'the dates are when the truck leaves, never an arrival');
      expect(find.text('105 kg'), findsOneWidget,
          reason: 'room left = capacity 1000 minus booked 895');
      expect(find.text('Capacity 1000 kg (895 kg reserved)'), findsNothing,
          reason: 'copy.md Formats: never capacity with reserved');
      expect(find.text('None'), findsOneWidget,
          reason: 'copy.md: a full lane says "Room left: None"');
      expect(find.text('Full'), findsOneWidget, reason: 'the status is a word');
      expect(find.text('Book this lane'), findsNothing,
          reason: 'cp-card: no buttons inside a card; the card opens');

      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(find.text('Book space'), findsOneWidget,
          reason: 'a lane card opens Book for that lane');
    });

    testWidgets(
        'Match keeps the server order and says "closest to your route first"',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
          {
            'trip': lane(id: 'lane-far', to: 'Madurai'),
            'eligibility': {'eligible': false}
          },
          {
            'trip': lane(id: 'lane-3', from: 'Hosur', to: 'Kanchipuram'),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '',
          reason: 'decisions.md 6: nothing preselected, no preset weight');
      expect(tester.widget<TextField>(field('Pickup')).controller!.text, '',
          reason: 'no preset pickup');

      await tester.enterText(field('Pickup'), 'Bommasandra, Bengaluru');
      await tester.enterText(field('Drop'), 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();

      expect(
          find.text(
              '2 lanes with room for 80 kg, closest to your route first.'),
          findsOneWidget,
          reason: 'copy.md: match result line');
      final first = tester.getTopLeft(find.text('Bengaluru to Chennai')).dy;
      final second = tester.getTopLeft(find.text('Hosur to Kanchipuram')).dy;
      expect(first < second, isTrue,
          reason: 'screens.md: the server order is kept, not re-sorted');
      expect(find.text('Bengaluru to Madurai'), findsNothing,
          reason: 'lanes failing the distance test stay hidden');

      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.tap(find.text('Bengaluru to Chennai'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '80',
          reason: 'screens.md: Book starts at the searched weight');
      expect(tester.widget<TextField>(field('Pickup')).controller!.text,
          'Bommasandra, Bengaluru',
          reason: 'screens.md: Book starts at the searched pickup');
    });

    testWidgets('Match with no lanes offers a lower weight or every lane',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match');
      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      server.answer('/anchor-trips', {
        'trips': [lane()]
      });
      await tester.pumpAndSettle();
      await tester.enterText(field('Pickup'), 'Bommasandra, Bengaluru');
      await tester.enterText(field('Drop'), 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '500');
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();

      expect(find.text('No lanes pass near this route with room for 500 kg.'),
          findsOneWidget,
          reason: 'copy.md: empty match');
      expect(
          find.text('Try a lower weight, or browse all lanes.'), findsOneWidget,
          reason: 'copy.md: empty match help');
      expect(find.widgetWithText(FilledButton, 'Change weight'), findsOneWidget,
          reason: 'sh-lanes-empty: Change weight is primary');

      await tester.tap(find.text('Browse all lanes'));
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget,
          reason: 'Browse all lanes switches to Browse');
    });
  });

  group('Book', () {
    testWidgets('a Book link with no lane goes to Find a lane', (tester) async {
      final router = GoRouter(
          initialLocation: '/customer/book', routes: customerFlowRoutes());
      addTearDown(router.dispose);
      FlutterSecureStorage.setMockInitialValues({});
      api = Api('http://test');
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({}));
      CustomerSession.skipRefreshInTests = true;
      addTearDown(() => CustomerSession.skipRefreshInTests = false);
      CustomerSession.applyForTest(
          userFullName: 'Priya Raman',
          customerOrgId: 'org-sharma',
          customerOrgName: 'Sharma Textiles',
          customerRole: 'CUSTOMER_MEMBER');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/customer/trips',
          reason:
              'decisions.md: Book is reached from a lane card, never with no lane');
    });

    testWidgets(
        'fields start empty without a search, and Pay is absent before a price',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/book?anchorTripId=lane-1');
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.pumpAndSettle();
      expect(find.text('Book space'), findsOneWidget, reason: 'copy.md: title');
      expect(find.text('Check the price, then pay.'), findsOneWidget,
          reason: 'copy.md: sub');
      expect(find.text('Room left: 105 kg'), findsOneWidget,
          reason: 'room left from capacity 1000 and booked 895');
      expect(find.text('Ravi Roadways · Leaves 18 – 19 Oct'), findsOneWidget,
          reason: 'the dates are when the truck leaves, never an arrival');
      expect(find.text('Up to 105 kg on this lane.'), findsOneWidget,
          reason: 'copy.md: weight help');
      for (final label in ['Weight', 'Pickup', 'Drop']) {
        expect(tester.widget<TextField>(field(label)).controller!.text, '',
            reason: 'screens.md: with no search, $label starts empty');
      }
      expect(find.text('Get price'), findsOneWidget,
          reason: 'copy.md: Get price comes first');
      expect(find.textContaining('Pay ₹'), findsNothing,
          reason: 'copy.md: Pay only after a price');
    });

    testWidgets(
        'the price state shows the full price, the contact line and Pay',
        (tester) async {
      final server = await showPricedBook(tester);
      expect(server.countOf('/shipments/quote'), 1);
      expect(find.text('₹2,640'), findsOneWidget,
          reason: 'copy.md: the price, Indian grouping');
      expect(find.text('This is the full price. Nothing is added at payment.'),
          findsOneWidget,
          reason: 'decisions.md 6: full price on the same screen as Pay');
      expect(
          find.text(
              'Changing weight, pickup or drop clears this price, and you get a new one.'),
          findsOneWidget,
          reason: 'copy.md: price note');
      expect(
          find.text(
              'Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact [NaviG8r contact].'),
          findsOneWidget,
          reason:
              'owner decision: no cancel in the app, the contact sits above Pay');
      expect(find.text('Pay ₹2,640 and book'), findsOneWidget,
          reason: 'copy.md: Pay names the amount');
      expect(find.text('Get price'), findsNothing,
          reason: 'one primary action at a time');
    });

    testWidgets('changing the weight clears the price and hides Pay',
        (tester) async {
      await showPricedBook(tester);
      await tester.tap(find.text('Change weight, pickup or drop'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Weight'), '90');
      await tester.pumpAndSettle();
      expect(find.text('₹2,640'), findsNothing,
          reason: 'brief A.2: shown price is the charged price');
      expect(find.textContaining('Pay ₹'), findsNothing,
          reason: 'screens.md: any change hides Pay');
      expect(find.text('Get price'), findsOneWidget,
          reason: 'a new price is one tap away');
    });

    testWidgets(
        'Pay opens the confirm sheet first; only Continue books, and Go back does not',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();

      expect(find.byType(NvSheet), findsOneWidget,
          reason: 'decisions.md: a confirm sheet before the payment provider');
      Finder inSheet(String text) =>
          find.descendant(of: find.byType(NvSheet), matching: find.text(text));
      expect(inSheet('Pay ₹2,640 to book?'), findsOneWidget,
          reason: 'copy.md: the sheet asks with the amount');
      expect(inSheet('You pay'), findsOneWidget,
          reason: 'copy.md: the sheet names what is paid');
      expect(inSheet('₹2,640'), findsOneWidget,
          reason: 'the full price again, before money moves');
      expect(inSheet('Bengaluru to Chennai'), findsOneWidget,
          reason: 'copy.md: Lane row');
      expect(inSheet('80 kg'), findsOneWidget, reason: 'copy.md: Weight row');
      expect(inSheet('Leaves'), findsOneWidget,
          reason: 'the dates row says when the truck leaves');
      expect(inSheet('18 – 19 Oct'), findsOneWidget);
      expect(
          inSheet(
              'You cannot cancel in the app. To change the booking, contact [NaviG8r contact].'),
          findsOneWidget,
          reason: 'owner decision: the no-cancel line is in the sheet');
      expect(
          inSheet(
              "Next, you choose how to pay on the payment provider's screen."),
          findsOneWidget,
          reason: 'copy.md: says what comes next');
      expect(server.countOf('/shipments/book'), 0,
          reason: 'nothing is booked before Continue');

      await tester.tap(inSheet('Go back'));
      await tester.pumpAndSettle();
      expect(find.byType(NvSheet), findsNothing);
      expect(server.countOf('/shipments/book'), 0,
          reason: 'Go back books nothing');

      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Continue to payment'));
      await tester.pumpAndSettle();
      expect(server.countOf('/shipments/book'), 1,
          reason: 'Continue runs the existing booking call');
      final booked = server.requests
          .lastWhere((request) => request.uri.path == '/shipments/book')
          .data as Map;
      expect(booked['weightKg'], 80, reason: 'the priced weight is booked');
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason: 'after booking, the shipment opens');
    });

    testWidgets(
        'too heavy shows the plain sentence under Weight, never HTTP text',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {'error': 'insufficient_capacity'}, 400);
      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This lane does not have room for that weight. Enter a lower weight, or choose another lane.'),
          findsOneWidget,
          reason: 'copy.md: too heavy, replaces "HTTP 400"');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no raw codes');
      expect(find.text('Choose another lane'), findsOneWidget,
          reason: 'copy.md: the way to another lane');
      expect(find.textContaining('Pay ₹'), findsNothing,
          reason: 'the refused price is cleared');
    });

    // The booking exists before checkout opens, so after checkout the shipper goes to it and Pay is
    // never offered again: a second Pay would book a second shipment.
    Future<(FakeServer, List<String>)> payThroughCheckout(WidgetTester tester,
        {required Map<String, dynamic> checkoutAnswer,
        bool confirmFails = false}) async {
      final announced = watchAnnouncements(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'),
          (call) async => call.method == 'open' ? checkoutAnswer : null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      if (confirmFails) {
        server.answer(
            '/v1/payments/razorpay/confirm', {'error': 'internal_error'}, 500);
      }
      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();
      return (server, announced);
    }

    testWidgets(
        'a closed or failed checkout opens the unpaid booking instead of offering Pay again',
        (tester) async {
      final (server, announced) =
          await payThroughCheckout(tester, checkoutAnswer: {
        'type': 1,
        'data': {'code': 2, 'message': 'Payment cancelled'}
      });
      expect(server.countOf('/shipments/book'), 1);
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason:
              'the booking already exists; tapping Pay again would book a second shipment');
      expect(find.text('Payment did not go through. This booking is not paid.'),
          findsOneWidget,
          reason: 'says why the shipment opened, in plain words');
      expect(find.textContaining('Payment cancelled'), findsNothing,
          reason: "the payment provider's own message is not shown");
      expect(announced,
          contains('Payment did not go through. This booking is not paid.'),
          reason: 'never announce "Booked. Waiting" for an unpaid booking');
    });

    testWidgets(
        'a payment the app could not confirm opens the shipment without saying it is paid',
        (tester) async {
      final (_, announced) =
          await payThroughCheckout(tester, confirmFails: true, checkoutAnswer: {
        'type': 0,
        'data': {
          'razorpay_order_id': 'order_synthetic',
          'razorpay_payment_id': 'pay_synthetic',
          'razorpay_signature': 'signature_synthetic'
        }
      });
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked, but the payment could not be confirmed yet. The shipment shows whether it went through.'),
          reason:
              'the confirm call failed, so the app does not know the payment is held');
    });

    testWidgets(
        'a booking whose payment never started is not announced as paid',
        (tester) async {
      final announced = watchAnnouncements(tester);
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CREATED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to payment'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked, but payment did not start. This booking is not paid.'),
          reason: 'checkout never opened, so nothing was paid');
    });

    testWidgets('a link point off the globe is looked up from its words',
        (tester) async {
      final server = await showShipperApp(
          tester, searchedBook.replaceFirst('pickupLat=12.8', 'pickupLat=NaN'));
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answer('/shipments/quote', {
        'quote': {'grossPaise': 264000}
      });
      await tester.pumpAndSettle();
      expect(find.text('Bommasandra, Bengaluru'), findsWidgets,
          reason: 'the words from the link stay');
      await tester.tap(find.text('Get price'));
      await tester.pumpAndSettle();
      final quoted = server.requests
          .lastWhere((request) => request.uri.path == '/shipments/quote')
          .data as Map;
      expect((quoted['pickup'] as Map)['lat'], 12.8,
          reason: 'a NaN latitude is never sent; the words were looked up');
    });

    testWidgets('a weight over the room left is refused before pricing',
        (tester) async {
      final server = await showShipperApp(tester, searchedBook);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.pumpAndSettle();
      await tester.enterText(field('Weight'), '150');
      await tester.tap(find.text('Get price'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This lane does not have room for that weight. Enter a lower weight, or choose another lane.'),
          findsOneWidget,
          reason: 'sh-book-error: the too-heavy sentence under Weight');
      expect(server.countOf('/shipments/quote'), 0,
          reason: 'no price for a weight the lane cannot take');
    });

    testWidgets('a server error never shows HTTP text', (tester) async {
      final server = await showShipperApp(tester, searchedBook);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answer('/shipments/quote', {'error': 'boom', 'detail': 'x'}, 500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get price'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no "HTTP 500" in the app');
      expect(
          find.text(
              'Could not get a price. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a plain sentence instead');
    });

    testWidgets('a lane that is not open says so instead of offering a price',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/book?anchorTripId=lane-1');
      server.answer('/anchor-trips/lane-1',
          {'trip': lane(reservedKg: 1000, status: 'FULL')});
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This lane is no longer taking bookings. Choose another lane.'),
          findsOneWidget,
          reason: 'a full lane cannot be booked');
      expect(find.text('Get price'), findsNothing,
          reason: 'no price for a lane that takes no bookings');
    });

    testWidgets(
        'Pay and the contact line are on screen without scrolling at 360 x 800',
        (tester) async {
      await showPricedBook(tester, height: 800);
      for (final words in [
        'Pay ₹2,640 and book',
        'Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact [NaviG8r contact].'
      ]) {
        final shown = tester.getRect(find.text(words));
        expect(shown.top >= 0 && shown.bottom <= 800, isTrue,
            reason:
                'decisions.md 8: the primary action and the way out show at 360 x 800');
      }
    });

    testWidgets('Home, Browse and the Match form fit 360 dp at 200% text',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'a',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways'
          },
          {'id': 'b', 'status': 'PENDING_CARRIER_ACCEPT'},
        ]
      });
      server.answer('/anchor-trips', {
        'trips': [lane()]
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Home fits at 200% text');
      await tester.tap(find.text('Find a lane').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Browse fits at 200% text');
      await tester.tap(find.text('Match my route'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: the Match form fits at 200% text');
    });

    testWidgets('the price state fits 360 dp at 200% text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await showPricedBook(tester, height: 800);
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: 200% text at 360 dp');
      expect(find.textContaining('Pay ₹'), findsOneWidget,
          reason: 'Pay stays in the action bar at 200% text');
    });
  });

  desktopTests();
  announcementTests();
  placeInputTests();
  placeSearchFailureTests();
  doubleTextTests();
}

const contactAbovePay =
    'Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact [NaviG8r contact].';

void desktopTests() {
  group('Desktop width (PR 9)', () {
    testWidgets(
        'at 1280 x 900 the price card and Pay are on screen together, beside the fields',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await showPricedBook(tester, width: 1280, height: 900);
      const screen = Rect.fromLTWH(0, 0, 1280, 900);
      bool onScreen(Finder finder) {
        final shown = tester.getRect(finder);
        return screen.contains(shown.topLeft) &&
            screen.contains(shown.bottomRight);
      }

      final price = find.text('₹2,640');
      final pay = find.text('Pay ₹2,640 and book');
      expect(onScreen(price) && onScreen(pay), isTrue,
          reason: 'PR 9: the price card and Pay are on screen together');
      final fields = tester.getRect(find.text('Change weight, pickup or drop'));
      expect(tester.getRect(price).left, greaterThan(fields.right),
          reason: 'wb-book: the price card sits in the side column');
      expect(tester.getRect(pay).left, greaterThan(fields.right),
          reason: 'wb-book: Pay sits with the price, not in a bottom bar');
      expect(tester.getRect(find.text(contactAbovePay)).bottom,
          lessThanOrEqualTo(tester.getRect(pay).top),
          reason:
              'owner decision: the no-cancel line stays directly above Pay');
      expect(find.byType(NvActionBar), findsNothing,
          reason: 'desktop: no bottom action bar');
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'PR 9: the top bar replaces the bottom tabs');

      final topBar = find.byType(CustomerTopNavigation);
      for (final words in ['NaviG8r', 'Home', 'Find a lane', 'Shipments']) {
        expect(find.descendant(of: topBar, matching: find.text(words)),
            findsOneWidget,
            reason: 'PR 9: the top bar shows "$words"');
      }
      expect(
          find.bySemanticsLabel(
              'Sharma Textiles, Priya Raman, Shipper. Switch company or sign out'),
          findsOneWidget,
          reason: 'PR 9: the account button is in the top bar');
      final back = find.descendant(
          of: find.byType(CustomerPageFrame),
          matching: find.text('Find a lane'));
      expect(back, findsOneWidget,
          reason:
              'wb-book: Back to the lanes sits in the page, above the title');
      expect(tester.getRect(back).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('Book space')).top));
      semantics.dispose();
    });

    testWidgets(
        'content is at most 1200 wide and centred; the top links open tabs',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer', width: 1600, height: 900);
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      final content = tester.getRect(
          find.widgetWithText(FilledButton, 'Find a lane for new goods'));
      expect(content.width, lessThanOrEqualTo(1200),
          reason: 'PR 9: content max width 1200');
      expect(content.center.dx, closeTo(800, 1),
          reason: 'the content column is centred');

      await tester.tap(find.descendant(
          of: find.byType(CustomerTopNavigation),
          matching: find.text('Find a lane')));
      await tester.pumpAndSettle();
      expect(find.text('Pick a lane going your way.'), findsOneWidget,
          reason: 'the top bar link opens Find a lane');
    });

    testWidgets(
        'at 1280 lanes are a card grid, and Match sits beside its results',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips',
          width: 1280, height: 900);
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(
              id: 'lane-2',
              from: 'Hosur',
              to: 'Kanchipuram',
              carrier: 'KTC Freight'),
        ]
      });
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Bengaluru to Chennai'));
      final second = tester.getRect(find.text('Hosur to Kanchipuram'));
      expect(second.top, first.top,
          reason: 'PR 9: lanes become a card grid, side by side');
      expect(second.left, greaterThan(first.right));

      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await tester.tap(find.text('Match my route'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Pickup'), 'Bommasandra, Bengaluru');
      await tester.enterText(field('Drop'), 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      final result = tester.getRect(find
          .text('1 lane with room for 80 kg, closest to your route first.'));
      expect(
          result.left, greaterThan(tester.getRect(find.text('Change')).right),
          reason: 'wb-lanes: the search sits beside its results');
    });

    testWidgets('at 360 x 800 the layout is the phone layout', (tester) async {
      await showPricedBook(tester, height: 800);
      expect(find.byType(CustomerTopNavigation), findsNothing,
          reason: 'PR 9: below 1024 there is no top bar');
      expect(
          find.ancestor(
              of: find.text('Pay ₹2,640 and book'),
              matching: find.byType(NvActionBar)),
          findsOneWidget,
          reason: 'phone: Pay stays in the bottom action bar');
      await scrollTo(tester, find.text('₹2,640'));
      expect(
          find.ancestor(
              of: find.text('₹2,640'), matching: find.byType(ListView)),
          findsOneWidget,
          reason: 'phone: the price card is in the one column');
      expect(
          find.descendant(
              of: find.byType(NvHeader), matching: find.text('Find a lane')),
          findsOneWidget,
          reason: 'phone: Back is in the header');

      await tester.pumpWidget(const SizedBox());
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget,
          reason: 'phone: the tabs stay at the bottom');
    });
  });
}

void placeInputTests() {
  test(
      'a dragged pin counts for the words beside it, not for words typed after',
      () async {
    final place = PlaceInput(words: 'Bommasandra, Bengaluru');
    place.pinnedAt(const LatLng(12.9, 77.6));
    expect(place.placed, isTrue,
        reason: 'the drag places the words the shipper is looking at');
    place.words.text = 'Guindy, Chennai';
    expect(place.placed, isFalse,
        reason:
            'new words with the old pin would book one place labelled as another');
    await place.place(findAnyPlace, emptyError: 'empty');
    expect(place.point, const LatLng(12.8, 77.7),
        reason: 'the new words are looked up');
    place.dispose();
  });
}

/// The real place search with no maps key, as a build without MAPS_API_KEY runs it.
Future<GeocodeOutcome> findWithNoMapsKey(String place) =>
    GoogleGeocodingService.forwardAddress(place, apiKey: '');

PlaceFinder failsWith(String status) =>
    (_) async => GeocodeOutcome.fail(status);

void placeSearchFailureTests() {
  final failures = [
    (
      kind: 'no maps key',
      findPlace: findWithNoMapsKey,
      sentence: 'Place search is not working right now. Try again later.'
    ),
    (
      kind: 'no match',
      findPlace: failsWith('ZERO_RESULTS'),
      sentence: 'Could not find this place. Try a nearby town.'
    ),
    (
      kind: 'no connection',
      findPlace: failsWith('NETWORK'),
      sentence:
          'Could not reach the map service. Check your connection, then search again.'
    ),
    (
      kind: 'a refused key',
      findPlace: failsWith('REQUEST_DENIED'),
      sentence: 'Place search is not working right now. Try again later.'
    ),
  ];

  Future<FakeServer> fillMatch(WidgetTester tester, PlaceFinder findPlace,
      {String pickup = 'gurugram', String drop = 'jaipur'}) async {
    final server = await showShipperApp(tester, '/customer/trips?tab=match',
        findPlace: findPlace);
    await tester.pumpAndSettle();
    await tester.enterText(field('Pickup'), pickup);
    await tester.enterText(field('Drop'), drop);
    await tester.enterText(field('Weight'), '80');
    await tester.tap(find.text('Find matching lanes'));
    await tester.pumpAndSettle();
    return server;
  }

  Future<FakeServer> fillBook(WidgetTester tester, PlaceFinder findPlace,
      {String pickup = 'gurugram', String drop = 'jaipur'}) async {
    final server = await showShipperApp(tester,
        '/customer/book?anchorTripId=lane-1&weightKg=80&pickup=$pickup&drop=$drop',
        findPlace: findPlace);
    server.answer('/anchor-trips/lane-1', {'trip': lane()});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get price'));
    await tester.pumpAndSettle();
    return server;
  }

  group('a failed place search says what failed', () {
    for (final failure in failures) {
      testWidgets('Match: ${failure.kind}', (tester) async {
        final server = await fillMatch(tester, failure.findPlace);
        expect(find.text(failure.sentence), findsNWidgets(2),
            reason: 'one sentence under Pickup and one under Drop');
        expect(server.countOf('/v1/customer/eligible-anchor-trips'), 0);
        if (failure.kind == 'no maps key') {
          expect(find.textContaining('Could not find this place'), findsNothing,
              reason:
                  'Uwais: "gurugram" and "jaipur" were called unknown places when the app had no maps key');
        }
      });

      testWidgets('Book: ${failure.kind}', (tester) async {
        final server = await fillBook(tester, failure.findPlace);
        expect(find.text(failure.sentence), findsNWidgets(2),
            reason: 'one sentence under Pickup and one under Drop');
        expect(server.countOf('/shipments/quote'), 0);
        if (failure.kind == 'no maps key') {
          expect(find.textContaining('Could not find this place'), findsNothing,
              reason:
                  'Uwais: "gurugram" and "jaipur" were called unknown places when the app had no maps key');
        }
      });
    }

    testWidgets('Match: blank places are asked for, not searched',
        (tester) async {
      var searched = false;
      await fillMatch(tester, (place) async {
        searched = true;
        return findAnyPlace(place);
      }, pickup: '  ', drop: '  ');
      expect(find.text('Enter the pickup place.'), findsOneWidget);
      expect(find.text('Enter the drop place.'), findsOneWidget);
      expect(searched, isFalse);
    });

    testWidgets('Book: blank places are asked for, not searched',
        (tester) async {
      var searched = false;
      await fillBook(tester, (place) async {
        searched = true;
        return findAnyPlace(place);
      }, pickup: '', drop: '');
      expect(find.text('Enter the pickup place.'), findsOneWidget);
      expect(find.text('Enter the drop place.'), findsOneWidget);
      expect(searched, isFalse);
    });
  });
}

void announcementTests() {
  testWidgets('Browse says it is loading lanes, then how many it found',
      (tester) async {
    final announced = watchAnnouncements(tester);
    final server = await showShipperApp(tester, '/customer/trips');
    server.answer('/anchor-trips', {
      'trips': [lane(), lane(id: 'lane-2', to: 'Hyderabad')]
    });
    await tester.pumpAndSettle();
    expect(announced, containsAllInOrder(['Loading lanes.', '2 lanes']),
        reason:
            'accessibility.md: "Loading lanes." once, then the count when loaded');
  });
}

void doubleTextTests() {
  group('200% text at 360 x 800 (PR 10)', () {
    testWidgets('Home, Browse, the Match form, its results and its empty state',
        (tester) async {
      useDoubleTextSize(tester);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'needs-bill',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways',
            'pickupAddress': 'Bommasandra, Bengaluru',
            'dropAddress': 'Guindy, Chennai',
            'assignedTruckNumber': 'KA01AB1234',
          },
          {'id': 'b', 'status': 'PENDING_CARRIER_ACCEPT'},
        ]
      });
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(id: 'lane-2', to: 'Hyderabad', reservedKg: 1000, status: 'FULL')
        ]
      });
      server.answer(
          '/v1/notifications/shipments', {'shipments': [], 'unreadCount': 3});
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Home');

      await tester.tap(find.text('Find a lane').last);
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Browse');

      await tester.tap(find.text('Match my route'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'the Match form');

      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await scrollTo(tester, field('Pickup'));
      await tester.enterText(field('Pickup'), 'Bommasandra, Bengaluru');
      await scrollTo(tester, field('Drop'));
      await tester.enterText(field('Drop'), 'Guindy, Chennai');
      await scrollTo(tester, field('Weight'));
      await tester.enterText(field('Weight'), '80');
      await scrollTo(tester, find.text('Find matching lanes'));
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Match results');

      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await scrollTo(tester, find.text('Change'));
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Find matching lanes'));
      await tester.tap(find.text('Find matching lanes'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Change weight'));
      await expectNoOverflowToTheEnd(tester, 'an empty match');
    });

    testWidgets(
        'Book before a price, with a price, the confirm sheet and too heavy',
        (tester) async {
      useDoubleTextSize(tester);
      final server = await showShipperApp(tester, searchedBook, height: 800);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answer('/shipments/quote', {
        'quote': {'grossPaise': 264000}
      });
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Book before a price');

      await tester.tap(find.text('Get price'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Book with a price');

      await tester.tap(find.text('Pay ₹2,640 and book'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'the confirm sheet',
          list: find
              .descendant(
                  of: find.byType(NvSheet), matching: find.byType(Scrollable))
              .first);
      await tester.ensureVisible(find.text('Go back'));
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();

      // At 200% in the test font the list above the action bar is 16 dp tall, less than this
      // button, so a tap at its centre lands on the bar; the button's own action runs instead.
      await scrollTo(tester, find.text('Change weight, pickup or drop'));
      tester
          .widget<NvButton>(
              find.widgetWithText(NvButton, 'Change weight, pickup or drop'))
          .onPressed!();
      await tester.pumpAndSettle();
      await scrollTo(tester, field('Weight'));
      await tester.enterText(field('Weight'), '150');
      await tester.tap(find.text('Get price'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Choose another lane'));
      await expectNoOverflowToTheEnd(tester, 'Book too heavy');
    });
  });
}
