// Load Board phase 1, the carrier side (4 Nov 2026): the office's board, adding a trip for a load with today's
// Add a trip form, and the Load alerts switch. A driver never sees any of it. Names and places are synthetic.
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/load_board/posted_load_words.dart';
import 'package:driver_pilot/load_board/trip_for_load.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_app.dart' as app;
import 'support/carrier_office_screens.dart' as office;
import 'support/mock_api.dart';

final today = todayInIndia();
String dayAhead(int days) => calendarDayText(today.add(Duration(days: days)));

/// A load as GET /v1/load-board sends it: towns, weight, size and pickup days only.
Map<String, dynamic> boardLoad({String id = 'load-1'}) => {
      'id': id,
      'fromCity': 'Bengaluru',
      'toCity': 'Chennai',
      'weightKg': 500,
      'packages': {'kind': 'TOTAL_VOLUME', 'volume': 120, 'unit': 'CUBIC_FEET'},
      'earliestPickupDate': dayAhead(1),
      'latestPickupDate': dayAhead(2),
      'postedAtUtcMs': 1793000000000,
    };

LoadForTrip loadForTrip() => LoadForTrip.fromBoard(boardLoad())!;

/// The carrier app on [server], recording every path it asks for; [loadBoard] answers the board.
List<String> signIn(app.CarrierServer server,
    {ResponseBody Function()? loadBoard}) {
  app.signInToCarrierApp(server);
  final asked = <String>[];
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    asked.add('${request.method} ${request.path}');
    if (request.path == '/v1/load-board' && loadBoard != null) {
      return loadBoard();
    }
    return server.answer(request);
  });
  return asked;
}

app.CarrierServer ownerServer({Map<String, Object> answers = const {}}) =>
    app.CarrierServer(
        allowed: app.ownerAllowed,
        subrole: 'OWNER',
        extraAnswers: {
          '/v1/load-board': {
            'loads': [boardLoad()]
          },
          '/v1/me/settings': {'loadAlerts': true},
          ...answers,
        });

String wordsOnScreen(WidgetTester tester) => app.textsOnScreen(tester).join('\n');

Future<void> tapButton(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button.first);
  await tester.pumpAndSettle();
  await tester.tap(button.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GeolocatorPlatform.instance = app.NoLocationService());
  tearDown(DriverSession.clearCarrierCache);

  group('the board', () {
    testWidgets(
        'the office Home opens the Load Board: towns, weight, size, days, and no amount or shipper',
        (tester) async {
      signIn(ownerServer());
      await app.mountCarrierApp(tester, '/driver', size: const Size(360, 2000));
      expect(find.text('Loads shippers posted. Add a trip for one.'), findsOneWidget);
      await tapButton(tester, 'Load Board');

      expect(find.text('Open loads, soonest pickup first.'), findsOneWidget);
      final words = wordsOnScreen(tester);
      expect(words, contains('Bengaluru to Chennai'));
      expect(words, contains('500 kg'));
      expect(words, contains('120 cubic feet'));
      expect(words, contains(pickupDaysWords(boardLoad())));
      expect(words, isNot(contains('₹')));
      expect(find.text('Add a trip for this load'), findsOneWidget);
    });

    testWidgets('a driver gets no Load Board card, and its address sends them Home',
        (tester) async {
      final asked = signIn(app.CarrierServer(
          allowed: app.driverAllowed,
          subrole: 'DRIVER',
          extraAnswers: {
            '/v1/load-board': {
              'loads': [boardLoad()]
            }
          }));
      await app.mountCarrierApp(tester, '/driver/load-board',
          size: const Size(360, 2000));
      expect(find.text('Open loads, soonest pickup first.'), findsNothing);
      expect(find.text('Load Board'), findsNothing);
      expect(asked, isNot(contains('GET /v1/load-board')),
          reason: 'a driver never even asks for the board');
    });

    testWidgets('a carrier not yet approved is told why', (tester) async {
      signIn(ownerServer(),
          loadBoard: () =>
              jsonResponse({'error': 'carrier_compliance_required'}, 409));
      await app.mountCarrierApp(tester, '/driver/load-board',
          size: const Size(360, 2000));
      expect(
          find.text(
              'NaviG8r must approve your company before you can see the Load Board.'),
          findsOneWidget);
    });

    testWidgets('no open loads says so', (tester) async {
      signIn(ownerServer(answers: {
        '/v1/load-board': {'loads': <Object>[]}
      }));
      await app.mountCarrierApp(tester, '/driver/load-board');
      expect(find.text('No open loads right now.'), findsOneWidget);
    });

    testWidgets('Add a trip for this load opens the trip form filled in from the load',
        (tester) async {
      signIn(ownerServer());
      await app.mountCarrierApp(tester, '/driver/load-board',
          size: const Size(360, 2000));
      await tapButton(tester, 'Add a trip for this load');

      expect(find.text('Add a trip'), findsOneWidget);
      expect(find.text('FOR A POSTED LOAD'), findsOneWidget);
      final placeTexts = [
        for (final field in tester.widgetList<TextField>(find.descendant(
            of: find.byType(LocationEndpointEditor),
            matching: find.byType(TextField))))
          field.controller!.text
      ];
      expect(placeTexts, ['Bengaluru', 'Chennai']);
      expect(find.text('Choose a date'), findsNothing,
          reason: 'both leaving days start inside the pickup days');
      expect(
          find.text(formatDate(today.add(const Duration(days: 1)), withYear: true)),
          findsOneWidget);
      final capacity = find.descendant(
          of: find.widgetWithText(Column, 'Capacity'),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(capacity.first).controller!.text, '500');
    });
  });

  group('adding the trip', () {
    Widget form() => DriverPublishTripScreen(
        forLoad: loadForTrip(),
        findPlace: (place) async =>
            GeocodeOutcome.ok(const LatLng(12.97, 77.59), '$place, Karnataka'));

    Future<void> searchBothAndChooseSize(WidgetTester tester) async {
      for (final index in [0, 1]) {
        await tester.tap(find.byTooltip('Search for place').at(index));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
      await tester.pumpAndSettle();
    }

    testWidgets("Add trip sends the load's id and towns, not the place search's words",
        (tester) async {
      final server = office.signInWith(office.Server(allowed: office.ownerAllowed));
      await office.mount(tester, form(), size: const Size(800, 3000));
      await searchBothAndChooseSize(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
      await tester.pumpAndSettle();

      final sent = server.sent.single.data as Map;
      expect(sent['postedLoadId'], 'load-1');
      expect(sent['originCity'], 'Bengaluru',
          reason: 'the server matches the towns; the search wrote "Bengaluru, Karnataka"');
      expect(sent['destCity'], 'Chennai');
      expect(sent['capacityKg'], 500);
      expect(sent['windowStart'],
          startsWith(dayAhead(1)), reason: 'leaves on the first pickup day');
      expect(sent['windowEnd'], startsWith(dayAhead(2)));
      expect(find.text('Opened /driver/loads'), findsOneWidget);
    });

    testWidgets("a capacity under the load's weight is refused before anything is sent",
        (tester) async {
      final server = office.signInWith(office.Server(allowed: office.ownerAllowed));
      await office.mount(tester, form(), size: const Size(800, 3000));
      await searchBothAndChooseSize(tester);
      final capacity = find.descendant(
          of: find.widgetWithText(Column, 'Capacity'),
          matching: find.byType(TextField));
      await tester.enterText(capacity.first, '400');
      await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
      await tester.pumpAndSettle();
      expect(find.text('The capacity must be at least 500 kg for this load.'),
          findsOneWidget);
      expect(server.sent, isEmpty);
    });

    testWidgets('a load that left the board is said in words', (tester) async {
      office.signInWith(office.Server(
          allowed: office.ownerAllowed,
          refusesWrites: true,
          refusal: const {'error': 'posted_load_not_open', 'state': 'BOOKED'}));
      await office.mount(tester, form(), size: const Size(800, 3000));
      await searchBothAndChooseSize(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This load is no longer on the Load Board. The shipper booked or withdrew it, or its pickup days passed.'),
          findsOneWidget);
    });

    testWidgets("a trip for a load leaves the carrier's own Add a trip draft alone",
        (tester) async {
      office.signInWith(office.Server(allowed: office.ownerAllowed));
      final router = await office.mount(
          tester, const DriverPublishTripScreen(key: ValueKey('own')),
          size: const Size(800, 3000));
      await tester.enterText(find.byType(TextField).first, 'Hoskote');
      router.go('/driver/loads');
      await tester.pumpAndSettle();
      await office.mount(tester, form(), size: const Size(800, 3000));
      await office.mount(
          tester, const DriverPublishTripScreen(key: ValueKey('own again')),
          size: const Size(800, 3000));
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text,
          'Hoskote');
    });
  });

  group('Load alerts', () {
    testWidgets('the office Company screen has Load alerts, on, and turning it off saves',
        (tester) async {
      final server = ownerServer();
      signIn(server);
      await app.mountCarrierApp(tester, '/driver/profile',
          size: const Size(360, 3000));
      expect(find.text('Load alerts'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue,
          reason: 'on until the person turns it off');
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final saved = server.sent.where((request) => request.path == '/v1/me/settings');
      expect(saved.single.method, 'PATCH');
      expect(saved.single.data, {'loadAlerts': false});
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    testWidgets('a driver Profile has no Load alerts', (tester) async {
      signIn(app.CarrierServer(allowed: app.driverAllowed, subrole: 'DRIVER'));
      await app.mountCarrierApp(tester, '/driver/profile',
          size: const Size(360, 3000));
      expect(find.text('Load alerts'), findsNothing);
    });
  });
}
