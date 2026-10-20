// Taking back a trip on the office's trip screen (owner decision, 19 Oct 2026): an empty trip is cancelled after
// a question in the page; a trip with bookings is asked about, with a reason, and the request can be withdrawn.
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_fixtures.dart';
import 'support/carrier_office_screens.dart';
import 'support/mock_api.dart';

const _requested =
    'You asked NaviG8r to cancel this trip. Shippers cannot book it now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled.';
const _cancelled = 'Trip cancelled. Shippers can no longer see or book it.';

/// One trip and its bookings; the cancel routes change the trip as the server would.
class _TripServer {
  _TripServer(
      {required this.trip,
      this.bookings = const [],
      this.allowed = ownerAllowed,
      this.refuseForBookings = false,
      this.refuseForNoBookings = false});
  Map<String, dynamic> trip;
  List<Map<String, dynamic>> bookings;
  final List<String> allowed;
  final bool refuseForBookings;

  /// Every booking left after the screen loaded: the request is refused and the bookings are gone on a reload.
  final bool refuseForNoBookings;
  final sent = <RequestOptions>[];
  int bookingLoads = 0;

  /// An office login: only the office view has the cancel buttons.
  _TripServer signIn() {
    signInAsCarrierLogin(office: true, alsoAllowed: allowed);
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.method != 'GET') {
        sent.add(request);
        final path = request.path;
        if (path.endsWith('/cancel') && refuseForBookings) {
          return jsonResponse({
            'error': 'trip_has_bookings',
            'detail': 'This trip has bookings, so it cannot be cancelled here.'
          }, 409);
        }
        if (path.endsWith('/cancel-request') && refuseForNoBookings) {
          bookings = [];
          return jsonResponse({
            'error': 'trip_has_no_bookings',
            'detail':
                'This trip has no bookings, so you can cancel it yourself.'
          }, 409);
        }
        final status = path.endsWith('/cancel')
            ? 'CANCELLED'
            : path.endsWith('/cancel-request')
                ? 'CANCEL_REQUESTED'
                : 'OPEN';
        trip = {...trip, 'status': status};
        return jsonResponse({'trip': trip});
      }
      switch (request.path) {
        case '/v1/auth/me':
          return jsonResponse({
            'user': {'id': 'carrier-person', 'fullName': 'Synthetic Person'},
            'organizations': [carrierOrganization],
            'principal': carrierPrincipal(office: true, alsoAllowed: allowed),
          });
        case '/v1/pilot/carrier/fleet':
          return jsonResponse(fleet);
        case '/v1/pilot/anchor-trips':
          return jsonResponse({
            'trips': [trip]
          });
        case '/v1/pilot/carrier/shipments':
          bookingLoads++;
          return jsonResponse({'shipments': bookings});
      }
      if (request.path.startsWith('/v1/pilot/anchor-trips/')) {
        return jsonResponse({'trip': trip});
      }
      return jsonResponse({'error': 'not_found'}, 404);
    });
    return this;
  }

  List<String> get paths => [for (final request in sent) request.path];
}

final _booked =
    bookingOn('trip-a', 'sharma', shipper: 'Sharma Textiles', weightKg: 80);

Future<void> _openTrip(WidgetTester tester,
        {Size size = const Size(360, 2000), double textScale = 1}) =>
    mount(tester, const DriverActiveTripScreen(tripId: 'trip-a'),
        size: size, textScale: textScale);

Future<void> _tapText(WidgetTester tester, String words) async {
  // The trip screen's list builds only what is near the screen, so a short phone scrolls to it first.
  if (find.text(words).evaluate().isEmpty) {
    await tester.dragUntilVisible(
        find.text(words), find.byType(ListView).first, const Offset(0, -200));
  }
  await tester.ensureVisible(find.text(words).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(words).last);
  await tester.pumpAndSettle();
}

bool _hasFocus(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label))).hasPrimaryFocus;

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Cancel this trip (no bookings)', () {
    testWidgets(
        'asks in the page with Keep trip focused; Keep trip sends nothing; Cancel trip cancels and says so',
        (tester) async {
      final server =
          _TripServer(trip: tripAt('trip-a', reservedKg: 0)).signIn();
      await _openTrip(tester);
      expect(find.text('Ask NaviG8r to cancel'), findsNothing);
      final open = find.widgetWithText(OutlinedButton, 'Cancel this trip');
      expect(open, findsOneWidget,
          reason: 'the destructive style is an outlined button');

      await _tapText(tester, 'Cancel this trip');
      expect(find.text('Cancel this trip?'), findsOneWidget);
      expect(
          find.text(
              'Shippers will no longer see or book it. You can publish a new trip any time. This cannot be undone.'),
          findsOneWidget);
      expect(find.byType(Dialog), findsNothing,
          reason: 'in the page, never a dialog');
      expect(find.byType(BottomSheet), findsNothing);
      expect(_hasFocus(tester, 'Keep trip'), isTrue,
          reason:
              'the safe answer has the focus, so a stray Enter keeps the trip');

      await _tapText(tester, 'Keep trip');
      expect(server.sent, isEmpty, reason: 'Keep trip changes nothing');
      expect(find.text('Cancel this trip?'), findsNothing);
      expect(open, findsOneWidget);

      await _tapText(tester, 'Cancel this trip');
      await _tapText(tester, 'Cancel trip');
      expect(server.paths, ['/v1/pilot/anchor-trips/trip-a/cancel']);
      expect(find.text(_cancelled), findsOneWidget, reason: 'the result line');
      expect(find.text('Cancelled'), findsOneWidget, reason: 'the status word');
      expect(find.text('Cancel this trip'), findsNothing);
      expect(find.text('Assign driver'), findsNothing,
          reason: 'a cancelled trip can no longer be assigned');
    });

    testWidgets(
        'a refusal because a booking arrived says so and offers asking NaviG8r instead',
        (tester) async {
      _TripServer(
              trip: tripAt('trip-a', reservedKg: 0), refuseForBookings: true)
          .signIn();
      await _openTrip(tester);
      await _tapText(tester, 'Cancel this trip');
      await _tapText(tester, 'Cancel trip');
      expect(
          find.text('This trip has bookings, so it cannot be cancelled here.'),
          findsOneWidget);
      expect(find.text('Ask NaviG8r to cancel'), findsOneWidget);
      expect(find.text('Cancel this trip'), findsNothing);
    });
  });

  group('Ask NaviG8r to cancel (bookings)', () {
    testWidgets(
        'the sheet needs one of the four reasons, the note is optional, and Keep trip sends nothing',
        (tester) async {
      final server =
          _TripServer(trip: tripAt('trip-a'), bookings: [_booked]).signIn();
      await _openTrip(tester);
      expect(find.text('Cancel this trip'), findsNothing,
          reason: 'a trip with bookings is never cancelled from the app');
      expect(find.widgetWithText(OutlinedButton, 'Ask NaviG8r to cancel'),
          findsOneWidget,
          reason: 'a plain button');

      await _tapText(tester, 'Ask NaviG8r to cancel');
      expect(inSheet(find.text('Why do you want to cancel this trip?')),
          findsOneWidget);
      expect(
          inSheet(find.text(
              'Shippers cannot book the trip now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled.')),
          findsOneWidget,
          reason: 'no promise that NaviG8r contacts anyone');
      for (final reason in [
        'Truck not available',
        'Driver not available',
        'Route changed',
        'Other reason'
      ]) {
        expect(inSheet(find.text(reason)), findsOneWidget, reason: reason);
      }
      expect(inSheet(find.text('Note (optional)', findRichText: true)),
          findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Send request'))
              .onPressed,
          isNull,
          reason: 'nothing is chosen for the person');
      expect(inSheet(find.text('Choose a reason first.')), findsOneWidget);

      await tester.tap(inSheet(find.text('Keep trip')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(server.sent, isEmpty);

      await _tapText(tester, 'Ask NaviG8r to cancel');
      await tester.tap(inSheet(find.text('Route changed')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();
      expect(server.paths, ['/v1/pilot/anchor-trips/trip-a/cancel-request']);
      expect(server.sent.single.data, {'reasonCode': 'ROUTE_CHANGED'},
          reason: 'no note is sent when none was typed');
      expect(find.text(_requested), findsOneWidget);
      expect(find.text('Cancel requested'), findsOneWidget);
    });

    testWidgets(
        'when every booking left meanwhile, the sheet closes and the card offers Cancel this trip, after a reload',
        (tester) async {
      final server = _TripServer(
              trip: tripAt('trip-a'),
              bookings: [_booked],
              refuseForNoBookings: true)
          .signIn();
      await _openTrip(tester);
      final loadsBefore = server.bookingLoads;
      await _tapText(tester, 'Ask NaviG8r to cancel');
      await tester.tap(inSheet(find.text('Route changed')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(server.bookingLoads, greaterThan(loadsBefore),
          reason: 'the trip and its bookings are loaded again');
      expect(find.text('Ask NaviG8r to cancel'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cancel this trip'),
          findsOneWidget);
    });

    testWidgets('a typed note is sent without its spaces', (tester) async {
      final server =
          _TripServer(trip: tripAt('trip-a'), bookings: [_booked]).signIn();
      await _openTrip(tester);
      await _tapText(tester, 'Ask NaviG8r to cancel');
      await tester.tap(inSheet(find.text('Truck not available')));
      await tester.enterText(
          inSheet(find.byType(TextField)), '  Gearbox failed ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();
      expect(server.sent.single.data,
          {'reasonCode': 'TRUCK_UNAVAILABLE', 'note': 'Gearbox failed'});
    });

    testWidgets(
        'a requested trip says what happens next and offers Withdraw request behind a question',
        (tester) async {
      final server = _TripServer(
          trip: tripAt('trip-a', status: 'CANCEL_REQUESTED'),
          bookings: [_booked]).signIn();
      await _openTrip(tester);
      expect(find.text(_requested), findsOneWidget);
      expect(find.text('Ask NaviG8r to cancel'), findsNothing);
      expect(find.text('Start trip'), findsNothing,
          reason: 'a trip waiting to be cancelled is not started');

      await _tapText(tester, 'Withdraw request');
      expect(find.text('Withdraw your request?'), findsOneWidget);
      expect(find.text('Shippers can book this trip again while it has room.'),
          findsOneWidget);
      expect(_hasFocus(tester, 'Keep request'), isTrue);
      await _tapText(tester, 'Keep request');
      expect(server.sent, isEmpty);

      await _tapText(tester, 'Withdraw request');
      await _tapText(tester, 'Withdraw request');
      expect(server.paths,
          ['/v1/pilot/anchor-trips/trip-a/cancel-request/withdraw']);
      expect(
          find.text(
              'Request withdrawn. Shippers can book this trip again while it has room.'),
          findsOneWidget);
      expect(find.text('Ask NaviG8r to cancel'), findsOneWidget);
    });
  });

  group('Who sees the buttons', () {
    for (final status in ['IN_PROGRESS', 'COMPLETED']) {
      testWidgets('none on a trip $status', (tester) async {
        _TripServer(
            trip: tripAt('trip-a', status: status, assigned: truckAndDriver),
            bookings: [_booked]).signIn();
        await _openTrip(tester);
        expect(find.text('Cancel this trip'), findsNothing);
        expect(find.text('Ask NaviG8r to cancel'), findsNothing);
      });
    }

    testWidgets(
        'an office login that may not assign trips only reads the request',
        (tester) async {
      _TripServer(
          trip: tripAt('trip-a', status: 'CANCEL_REQUESTED'),
          allowed: const ['load.status_update']).signIn();
      await _openTrip(tester);
      expect(find.text(_requested), findsOneWidget);
      expect(find.text('Withdraw request'), findsNothing);
    });

    testWidgets(
        'an office login that may not assign trips gets no cancel button',
        (tester) async {
      _TripServer(
          trip: tripAt('trip-a', reservedKg: 0),
          allowed: const ['load.status_update']).signIn();
      await _openTrip(tester);
      expect(find.text('Cancel this trip'), findsNothing);
    });
  });

  group('Trips list', () {
    testWidgets(
        'a requested trip is Open with "Cancel requested"; a cancelled one is Done with "Cancelled"',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed, trips: [
        tripAt('trip-asked', status: 'CANCEL_REQUESTED'),
        tripAt('trip-gone', status: 'CANCELLED', reservedKg: 0, startDay: 20),
      ]));
      await mount(tester, const DriverLoadsScreen());
      expect(find.text('Cancel requested'), findsOneWidget,
          reason: 'under Open, where the list starts');
      expect(find.text('Cancelled'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel requested'), findsNothing);
      expect(find.textContaining('CANCEL'), findsNothing,
          reason: 'never the code');
    });

    test('the shipper-side status words have both new states', () {
      expect(tripStatusLabel('CANCEL_REQUESTED'), 'Cancel requested');
      expect(tripStatusLabel('CANCELLED'), 'Cancelled');
    });
  });

  group('200% text at 360 x 800', () {
    testWidgets('the question, the sheet and the requested state fit',
        (tester) async {
      _TripServer(trip: tripAt('trip-a', reservedKg: 0)).signIn();
      await _openTrip(tester, size: const Size(360, 800), textScale: 2);
      await _tapText(tester, 'Cancel this trip');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel trip'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ask sheet and the requested state fit', (tester) async {
      _TripServer(trip: tripAt('trip-a'), bookings: [_booked]).signIn();
      await _openTrip(tester, size: const Size(360, 800), textScale: 2);
      await _tapText(tester, 'Ask NaviG8r to cancel');
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(inSheet(find.text('Other reason')));
      await tester.pumpAndSettle();
      await tester.tap(inSheet(find.text('Other reason')));
      await tester.pumpAndSettle();
      await tester
          .ensureVisible(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Withdraw request'));
      await tester.pumpAndSettle();
      expect(find.text(_requested), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
