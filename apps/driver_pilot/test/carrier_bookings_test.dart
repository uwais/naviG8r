// PR 6 of the redesign: the office Home (ca-home), the Bookings list (ca-bookings) and the booking screen
// (ca-booking-new, -truck, -deliver, -owner, -dispatcher).
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/plain_error_sentence.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

/// 06:00 India time on 18 Oct of this year, and 20:00 on 19 Oct, as the server sends a trip's window.
final _thisYear = DateTime.now().year;
final _windowStart = DateTime.utc(_thisYear, 10, 18, 0, 30).toIso8601String();
final _windowEnd = DateTime.utc(_thisYear, 10, 19, 14, 30).toIso8601String();

Map<String, dynamic> trip(
        {String id = 'trip-a',
        String from = 'Bengaluru',
        String to = 'Chennai',
        String status = 'OPEN',
        num capacityKg = 1000,
        num reservedKg = 975,
        String? truck,
        String? driverName}) =>
    {
      'id': id,
      'originCity': from,
      'destCity': to,
      'windowStart': _windowStart,
      'windowEnd': _windowEnd,
      'status': status,
      'capacityKg': capacityKg,
      'reservedKg': reservedKg,
      if (truck != null) 'assignedTruckNumber': truck,
      if (driverName != null) ...{
        'assignedDriverUserId': 'driver-1',
        'assignedDriverName': driverName,
      },
    };

const officeWork = [
  'carrier.offer_accept',
  'trip.assign',
  'pod.upload',
];

void signInAsOwner() => signInAsCarrierOwner(alsoAllowed: officeWork);

/// A dispatcher holds payment.read and is sent the amount, but is not the owner (no bank_account.create_token).
void signInAsDispatcher() {
  signInAsCarrierLogin(office: true, alsoAllowed: officeWork);
  AuthorizationSession.principal = {
    ...AuthorizationSession.principal!,
    'subrole': 'DISPATCHER',
  };
}

/// Answers the carrier shipment list with [bookings], the trip list with [trips], and each trip by id.
void answer(
    {required List<Map<String, dynamic>> bookings,
    List<Map<String, dynamic>> trips = const []}) {
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    if (request.path == '/v1/pilot/anchor-trips') {
      return jsonResponse({'trips': trips});
    }
    if (request.path.startsWith('/v1/pilot/anchor-trips/')) {
      final id = request.path.split('/').last;
      final found = trips.where((trip) => trip['id'] == id);
      return found.isEmpty
          ? jsonResponse({'error': 'not_found'}, 404)
          : jsonResponse({'trip': found.first});
    }
    return jsonResponse({'shipments': bookings});
  });
}

/// The screen under a router, so opening a card or a task can be seen as a page change.
Future<void> mountRouted(WidgetTester tester, Widget screen,
    {Size size = const Size(800, 3000), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/driver', routes: [
    GoRoute(
        path: '/driver',
        builder: (_, __) => Scaffold(body: screen),
        routes: [
          GoRoute(
              path: 'shipment/:id',
              builder: (_, state) =>
                  Text('Booking page ${state.pathParameters['id']}')),
          GoRoute(
              path: 'trip/:id/active',
              builder: (_, state) =>
                  Text('Trip page ${state.pathParameters['id']}')),
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(
      theme: DriverTheme.theme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!)));
  await tester.pumpAndSettle();
}

Future<void> mountBooking(WidgetTester tester,
    {Size size = const Size(800, 3000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A 72 dp bar and 80 dp of tabs stand in for the shell's header and bottom tabs.
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(
          appBar: PreferredSize(
              preferredSize: Size.fromHeight(72), child: SizedBox()),
          body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'),
          bottomNavigationBar: SizedBox(height: 80))));
  await tester.pumpAndSettle();
}

/// Every word the screen shows right now.
String screenWords(WidgetTester tester) => [
      ...tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? ''),
      ...tester
          .widgetList<RichText>(find.byType(RichText))
          .map((text) => text.text.toPlainText()),
    ].join('\n');

Map<String, dynamic> pending() =>
    shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT');

/// Accepted, and the shipper made the bill without the truck.
Map<String, dynamic> truckMissing() => {
      ...shipmentOnTripA(),
      'id': 'shipment-b',
      'customerOrgName': 'Lakshmi Foods',
      'anchorTripId': 'trip-b',
      'assignedTruckNumber': 'KA01AB1234',
      'ewayBill': {'kind': 'BILL', 'billNumber': '271844021196'},
    };

Map<String, dynamic> delivered({int? netToCarrierPaise}) => {
      ...shipmentOnTripA(netToCarrierPaise: netToCarrierPaise),
      'status': 'PENDING_RELEASE',
      'assignedTruckNumber': 'KA01AB1234',
      'podAtUtcMs':
          DateTime.utc(_thisYear, 10, 19, 8, 50).millisecondsSinceEpoch,
    };

void main() {
  test('an unpaid booking is refused in words, never "Something went wrong"',
      () {
    api = Api('http://test');
    DioException refusal(String code) => DioException(
          requestOptions: RequestOptions(path: '/v1/pilot/carrier/shipments'),
          response: Response(
            requestOptions: RequestOptions(path: '/v1/pilot/carrier/shipments'),
            statusCode: 400,
            data: {'error': code},
          ),
        );
    expect(plainErrorSentence(refusal('checkout_not_completed_for_accept')),
        'The shipper has not finished paying for this booking yet. You can accept it once they do.',
        reason:
            'an unpaid booking shows as waiting for the office; trying again cannot work until the shipper pays');
    expect(plainErrorSentence(refusal('checkout_not_completed_for_pod')),
        'This booking is not ready for delivery yet. Ask your office.',
        reason: 'a driver can meet this, so it says nothing about payment');
  });

  group('The office Home', () {
    testWidgets(
        'puts the first task first, with its button, then the others and the trips on the road',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        pending(),
        truckMissing(),
      ], trips: [
        trip(),
        trip(id: 'trip-b', from: 'Hosur', to: 'Coimbatore', reservedKg: 400),
        trip(
            id: 'trip-c',
            from: 'Bengaluru',
            to: 'Mysuru',
            status: 'IN_PROGRESS',
            truck: 'KA 01 AB 5678',
            driverName: 'Suresh Kumar'),
      ]);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('NEEDS YOU'), findsOneWidget,
          reason: 'ca-home: the first task is a NEEDS YOU card');
      expect(find.text('Accept a booking'), findsOneWidget,
          reason: 'accepting blocks everything after it, so it comes first');
      expect(
          find.text(
              'Synthetic Shipper A, 120 kg, on your Bengaluru to Chennai trip, 18 Oct.'),
          findsOneWidget,
          reason:
              'copy.md: [Shipper], [weight], on your [route] trip, [date].');
      expect(
          find.widgetWithText(FilledButton, 'Review booking'), findsOneWidget,
          reason: 'the first task has the one primary button');
      expect(find.text('Add the truck to an e-way bill'), findsNothing,
          reason:
              'owner decision 18 Oct 2026: the shipper adds the truck, so it is never the carrier\'s task');
      expect(find.text('Hosur to Coimbatore · Lakshmi Foods'), findsNothing,
          reason: 'no task row for the missing truck');
      expect(find.text('Assign a driver'), findsNWidgets(2),
          reason: 'both booked trips wait for a driver');
      expect(find.text('Today'), findsOneWidget,
          reason: 'ca-home: the trips on the road');
      expect(find.text('Bengaluru to Mysuru'), findsOneWidget);
      expect(find.text('In transit'), findsOneWidget);
      expect(
          find.text('KA01AB5678 · Suresh Kumar · 0 bookings'), findsOneWidget,
          reason:
              'truck in the portal form, the driver, and the bookings on it');
      for (final link in [
        'Sign in with phone',
        'Register as new carrier',
        'Developer lab',
        'Sign out',
      ]) {
        expect(find.text(link), findsNothing,
            reason:
                'copy.md: the signed-in home has no sign-in, register, developer or sign-out links ($link)');
      }
      await tester.tap(find.text('Review booking'));
      await tester.pumpAndSettle();
      expect(find.text('Booking page shipment-a'), findsOneWidget,
          reason: 'the task opens the booking');
    });

    testWidgets(
        'asks to start a trip whose day has come, once a booking is accepted and the driver and truck are set',
        (tester) async {
      final now = DateTime.now().toUtc();
      final today = now.toIso8601String();
      final tomorrow = now.add(const Duration(days: 1)).toIso8601String();
      Map<String, dynamic> readyTrip(String id, String to, String start) => {
            ...trip(
                id: id,
                to: to,
                truck: 'KA01AB1234',
                driverName: 'Prakash Naidu'),
            'windowStart': start,
          };
      final bookings = [
        {...shipmentOnTripA(), 'anchorTripId': 'trip-today'},
        {...shipmentOnTripA(), 'id': 'shipment-t', 'anchorTripId': 'trip-later'},
        {
          ...shipmentOnTripA(status: 'PENDING_CARRIER_ACCEPT'),
          'id': 'shipment-p',
          'anchorTripId': 'trip-unaccepted'
        },
      ];
      final trips = [
        readyTrip('trip-today', 'Chennai', today),
        readyTrip('trip-later', 'Mysuru', tomorrow),
        readyTrip('trip-unaccepted', 'Hosur', today),
      ];

      signInAsCarrierOwner(alsoAllowed: ['load.status_update']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('Nothing needs you right now.'), findsNothing,
          reason: 'owner run: Home said this while a trip was ready to start');
      expect(find.text('Start a trip'), findsOneWidget,
          reason: 'only the trip whose day has come and has an accepted booking');
      expect(
          find.text(
              'Bengaluru to Chennai · ${formatDate(DateTime.parse(today))}'),
          findsOneWidget,
          reason: 'names the trip and its date');
      await tester.tap(find.widgetWithText(FilledButton, 'Open trip'));
      await tester.pumpAndSettle();
      expect(find.text('Trip page trip-today'), findsOneWidget,
          reason: 'Start is on the trip screen, behind its confirm sheet');

      signInAsCarrierOwner(
          alsoAllowed: ['load.status_update', 'carrier.offer_accept']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(2)));
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('NEEDS YOU'), matching: find.byType(Column)),
              matching: find.text('Accept a booking')),
          findsOneWidget,
          reason: 'accepting comes first; starting comes after');
      expect(find.text('Start a trip'), findsOneWidget);

      signInAsCarrierOwner();
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(3)));
      expect(find.text('Start a trip'), findsNothing,
          reason: 'no task for a login that may not start trips');

      signInAsCarrierOwner(alsoAllowed: ['load.status_update']);
      answer(bookings: bookings, trips: trips);
      await mountRouted(tester, const DriverWelcomeScreen(key: ValueKey(4)),
          size: const Size(360, 800), textScale: 2);
      expect(find.text('Start a trip'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'spec: works at 360 dp and 200% text');
    });

    testWidgets('says when nothing needs the office', (tester) async {
      signInAsOwner();
      answer(bookings: []);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('Nothing needs you right now.'), findsOneWidget,
          reason: 'an empty Home says so instead of showing nothing');
      expect(find.text('NEEDS YOU'), findsNothing);
    });

    testWidgets('a driver keeps their own home', (tester) async {
      signInAsCarrierLogin(office: false);
      answer(bookings: [pending()]);
      await mountRouted(tester, const DriverWelcomeScreen());
      expect(find.text('NEEDS YOU'), findsNothing,
          reason:
              'drivers do not accept bookings from Home; their Today is PR 8');
    });
  });

  group('The Bookings list', () {
    final active = {
      ...shipmentOnTripA(),
      'id': 'shipment-c',
      'customerOrgName': 'Active Shipper',
      'ewayBill': {
        'kind': 'BILL',
        'billNumber': '341200987654',
        'truckNumber': 'KA01AB1234'
      },
    };

    testWidgets(
        'groups bookings under Needs you, Active and Done, with no Accept on any card',
        (tester) async {
      signInAsOwner();
      answer(
          bookings: [pending(), truckMissing(), active, delivered()],
          trips: [trip()]);
      await mountRouted(tester, const DriverShipmentsScreen());
      expect(find.text('Needs you (1)'), findsOneWidget,
          reason:
              'copy.md: Needs you ([n]); a missing truck is the shipper\'s to add, so it is not counted');
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Synthetic Shipper A'), findsOneWidget);
      expect(find.text('Waiting for you'), findsOneWidget,
          reason: 'ca-bookings: status word, never PENDING_CARRIER_ACCEPT');
      expect(find.text('Peenya, Bengaluru to Hosur'), findsOneWidget,
          reason: '[pickup] to [drop]');
      expect(find.text('18 Oct · 120 kg'), findsOneWidget,
          reason:
              'the trip date and the weight; no e-way bill answer is stored yet');
      final nextLines = screenWords(tester);
      expect(nextLines, contains('Next: accept and choose the truck.'));
      expect(find.byType(FilledButton), findsNothing,
          reason:
              'ca-bookings: the whole card opens; Accept is on the booking');
      expect(find.text('Active Shipper'), findsNothing,
          reason: 'only Needs you shows at first');

      await tester.tap(find.text('Active'));
      await tester.pumpAndSettle();
      expect(find.text('Active Shipper'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Synthetic Shipper A'), findsNothing);
      expect(find.text('Lakshmi Foods'), findsOneWidget,
          reason: 'a booking whose bill lacks the truck is active, not waiting on the carrier');
      expect(find.text('Truck not on bill'), findsOneWidget,
          reason: 'the carrier pays check-post fines, so it still sees the state');
      expect(find.text('120 kg'), findsOneWidget,
          reason:
              'the status and Next: already say the truck is missing, so the card adds no bill words');
      expect(find.text('18 Oct · 120 kg · Truck on the e-way bill'),
          findsOneWidget,
          reason: "the booking's own step words for a bill with the truck");
      expect(find.textContaining('E-way bill: needed'), findsNothing,
          reason: 'owner run: a saved bill is not "needed"');
      final activeNextLines = screenWords(tester);
      expect(activeNextLines,
          contains('Next: Lakshmi Foods adds the truck to the e-way bill.'),
          reason: 'the carrier is told who acts, not asked to');
      expect(activeNextLines,
          isNot(contains('Next: add the truck to the e-way bill.')));

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Awaiting payment release'), findsOneWidget,
          reason: 'the owner reads the payment status');

      await tester.tap(find.text('Synthetic Shipper A'));
      await tester.pumpAndSettle();
      expect(find.text('Booking page shipment-a'), findsOneWidget,
          reason: 'the card opens its booking');
    });
  });

  testWidgets(
      "a Done card says the shipper's bill and truck are on it, never \"needed\"",
      (tester) async {
    signInAsOwner();
    answer(bookings: [
      {
        ...delivered(),
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987654',
          'truckNumber': 'KA01AB1234',
          'check': {'result': 'FOUND'},
        },
      },
      {
        ...delivered(),
        'id': 'shipment-d',
        'customerOrgName': 'Mehta Hardware',
        'status': 'DELIVERED',
        'ewayBill': {
          'kind': 'BILL',
          'billNumber': '341200987655',
          'truckNumber': 'KA01AB1234',
        },
      },
    ], trips: [
      trip()
    ]);
    await mountRouted(tester, const DriverShipmentsScreen());
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('18 Oct · 120 kg · E-way bill checked'), findsOneWidget,
        reason: "owner run: the booking's own steps say the bill was checked");
    expect(find.text('18 Oct · 120 kg · Truck on the e-way bill'),
        findsOneWidget,
        reason: 'a bill with the truck, not checked yet');
    expect(find.textContaining('E-way bill: needed'), findsNothing,
        reason: 'owner run: a delivered booking with a saved bill read "needed"');

    await mountRouted(tester, const DriverShipmentsScreen(key: ValueKey(2)),
        size: const Size(360, 800), textScale: 2);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'spec: works at 360 dp and 200% text');
  });

  group('The booking screen', () {
    test('its title is never "Proof of delivery" before delivery', () {
      expect(driverShellTitle('/driver/shipment/shipment-a'),
          isNot('Proof of delivery'),
          reason:
              'PR 6: the booking screen was titled "Proof of delivery" from the start');
    });

    for (final (state, booking) in [
      ('awaiting acceptance', pending()),
      ('accepted', truckMissing()),
      ('in transit', shipmentOnTripA()),
    ]) {
      testWidgets('says BOOKING and the shipper, $state', (tester) async {
        signInAsOwner();
        answer(bookings: [
          {...booking, 'id': 'shipment-a'}
        ], trips: [
          trip(status: state == 'in transit' ? 'IN_PROGRESS' : 'OPEN'),
          trip(id: 'trip-b')
        ]);
        await mountBooking(tester);
        expect(find.text('BOOKING'), findsOneWidget,
            reason: 'copy.md: BOOKING · [Shipper]');
        expect(find.text(booking['customerOrgName'] as String), findsWidgets);
        expect(find.textContaining('Proof of delivery'), findsNothing,
            reason: 'PR 6: never "Proof of delivery" before delivery');
      });
    }

    testWidgets(
        'before acceptance shows the facts, the room left and Accept without scrolling at 360 x 800',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        {
          ...pending(),
          'ewayBill': {'kind': 'NOT_NEEDED', 'notNeededReason': 'GOODS_EXEMPT'}
        }
      ], trips: [
        trip()
      ]);
      await mountBooking(tester, size: const Size(360, 800));
      expect(find.text('Waiting for you to accept'), findsOneWidget);
      for (final fact in ['Pickup', 'Drop', 'Weight', 'E-way bill']) {
        expect(find.text(fact), findsOneWidget,
            reason: 'ca-booking-new fact: $fact');
      }
      expect(find.text('Not needed (shipper said so).'), findsOneWidget,
          reason: "ca-booking-new shows the shipper's e-way bill answer");
      expect(
          find.text(
              'On your trip Bengaluru to Chennai, 18 – 19 Oct. After this, 25 kg of room is left.'),
          findsOneWidget,
          reason: 'copy.md accept panel, from the trip the booking is on');
      final accept = find.widgetWithText(FilledButton, 'Accept');
      expect(accept, findsOneWidget);
      final screen = Offset.zero & tester.view.physicalSize;
      final acceptBox = tester.getRect(accept);
      expect(screen.contains(acceptBox.topLeft) && acceptBox.bottom <= 800 - 80,
          isTrue,
          reason:
              'success criterion: the primary action is visible without scrolling ($acceptBox)');
      expect(find.text('Decline'), findsNothing,
          reason: 'no decline endpoint exists, so no Decline button');
      expect(tester.takeException(), isNull, reason: 'no overflow at 360 dp');
    });

    testWidgets('Accept says why it is disabled for a carrier not yet approved',
        (tester) async {
      signInAsOwner();
      AuthorizationSession.organizations = [
        {...carrierOrganization, 'kycStatus': 'SUBMITTED'}
      ];
      answer(bookings: [pending()], trips: [trip()]);
      await mountBooking(tester);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Accept'))
              .onPressed,
          isNull);
      expect(find.text('You can accept once NaviG8r approves your company.'),
          findsOneWidget,
          reason: 'a disabled button always says why');
    });

    testWidgets(
        'a bill without the truck is the shipper\'s to fix: the office reads it, with no form or copy rows',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        {...truckMissing(), 'id': 'shipment-a'}
      ], trips: [
        trip(id: 'trip-b')
      ]);
      await mountBooking(tester);
      expect(find.text('Accepted with KA01AB1234'), findsOneWidget,
          reason: 'ca-booking-truck: the done accept step names the truck');
      expect(find.text('Lakshmi Foods'), findsWidgets,
          reason: 'the step names the shipper as who acts');
      expect(find.text('You · Lakshmi Foods made the bill without it'),
          findsNothing,
          reason: 'the carrier is not asked to add the truck');
      expect(find.text('Lakshmi Foods has not added the truck to the bill yet.'),
          findsOneWidget,
          reason: 'the state in words');
      expect(find.text('2718 4402 1196'), findsOneWidget,
          reason: 'in groups of four, in the mono face');
      for (final words in [
        'E-way bill number',
        'Truck number',
        'Portal field: Vehicle No.',
        'Add truck',
        'Open the government e-way bill portal',
      ]) {
        expect(find.text(words), findsNothing, reason: 'read only: "$words"');
      }
    });

    testWidgets(
        'in transit offers today\'s Confirm delivery, with no photo requirement',
        (tester) async {
      signInAsOwner();
      answer(
          bookings: [shipmentOnTripA()],
          trips: [trip(status: 'IN_PROGRESS', driverName: 'Suresh Kumar')]);
      await mountBooking(tester);
      expect(find.text('In transit'), findsOneWidget);
      expect(find.text('You or Suresh Kumar'), findsOneWidget,
          reason: 'ca-booking-deliver: who confirms');
      final confirm = find.widgetWithText(FilledButton, 'Confirm delivery');
      expect(confirm, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull,
          reason:
              'no photo capture exists, so confirming is not held behind one');
      expect(find.text('Add the proof of delivery first.'), findsNothing);
    });

    testWidgets('before the trip starts, the trip step opens the trip instead',
        (tester) async {
      signInAsOwner();
      answer(bookings: [shipmentOnTripA()], trips: [trip()]);
      await mountBooking(tester);
      expect(find.widgetWithText(OutlinedButton, 'Open trip'), findsOneWidget,
          reason: 'assigning and starting happen on the trip screen');
      expect(
          find.widgetWithText(FilledButton, 'Confirm delivery'), findsNothing,
          reason:
              'ca-booking-deliver: confirming comes once the trip is on the road');
    });

    testWidgets(
        'after delivery the owner sees the amount the carrier API sends, together',
        (tester) async {
      signInAsOwner();
      answer(bookings: [delivered(netToCarrierPaise: 237600)], trips: [trip()]);
      await mountBooking(tester);
      expect(find.text('Awaiting payment release'), findsOneWidget);
      expect(find.text('Delivery confirmed'), findsOneWidget,
          reason: 'the delivery step is done');
      expect(
          find.textContaining(' IST · Proof of delivery added'), findsOneWidget,
          reason: 'when it was confirmed, in India time');
      expect(find.text('You receive'), findsOneWidget,
          reason: 'ca-booking-owner: the amount block');
      expect(find.text('₹2,376'), findsOneWidget,
          reason: 'Indian grouping, no paise');
      expect(
          find.text(
              'Only owners see payment amounts. Dispatchers and drivers do not.'),
          findsOneWidget);
      for (final missing in ['Shipper paid', 'NaviG8r commission']) {
        expect(find.text(missing), findsNothing,
            reason:
                'RECON gaps 20-21: $missing is not sent to carriers, so it is left out, never made up');
      }
    });

    testWidgets(
        'after delivery a dispatcher sees "Delivery confirmed" and no amount, though the server sent it',
        (tester) async {
      signInAsDispatcher();
      answer(bookings: [delivered(netToCarrierPaise: 237600)], trips: [trip()]);
      await mountBooking(tester);
      expect(find.text('Delivery confirmed'), findsNWidgets(2),
          reason: 'ca-booking-dispatcher: the status and the done step');
      expect(find.text('Nothing more for you to do on this booking.'),
          findsOneWidget);
      expect(
          find.text(
              'NaviG8r operations check the proof of delivery. The owner sees the payment.'),
          findsOneWidget);
      expect(screenWords(tester), isNot(contains('₹')),
          reason: 'PR 6: no amount anywhere in a dispatcher\'s tree');
      expect(find.text('You receive'), findsNothing);
      expect(find.text('Awaiting payment release'), findsNothing);
    });
  });

  group('At 360 dp wide and 200% text nothing overflows', () {
    final bookings = [
      {
        ...pending(),
        'customerOrgName':
            'Synthetic Shipper With A Very Long Registered Business Name Private Limited',
        'ewayBill': {'kind': 'NOT_NEEDED', 'notNeededReason': 'GOODS_EXEMPT'},
      },
      truckMissing(),
      delivered(netToCarrierPaise: 237600),
    ];
    final trips = [
      trip(),
      trip(id: 'trip-b', from: 'Hosur', to: 'Coimbatore'),
      trip(
          id: 'trip-c',
          status: 'IN_PROGRESS',
          truck: 'KA01AB5678',
          driverName: 'Suresh Kumar'),
    ];
    for (final (name, screen) in [
      ('Home', const DriverWelcomeScreen()),
      ('Bookings', const DriverShipmentsScreen()),
      (
        'a booking awaiting acceptance',
        const DriverShipmentDetailScreen(shipmentId: 'shipment-a')
      ),
      (
        'a booking missing its truck',
        const DriverShipmentDetailScreen(shipmentId: 'shipment-b')
      ),
    ]) {
      testWidgets(name, (tester) async {
        signInAsOwner();
        answer(bookings: bookings, trips: trips);
        await mountRouted(tester, screen,
            size: const Size(360, 800), textScale: 2);
        expect(tester.takeException(), isNull,
            reason: 'spec: works at 360 dp and 200% text ($name)');
      });
    }
  });
}
