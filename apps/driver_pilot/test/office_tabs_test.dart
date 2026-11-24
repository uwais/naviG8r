// The office tabs (owner decision, 5 Nov 2026): Home, Bookings, Trips, Load Board, Profile. Add trip is a
// button on Home and Trips, not a tab, and its form sits under Trips. A driver keeps Home, Trips, Profile and
// never sees the Load Board. Names and places are synthetic.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/load_board/posted_load_words.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

List<String> tabLabels(WidgetTester tester) => tester
    .widget<NavigationBar>(find.byType(NavigationBar))
    .destinations
    .map((destination) => (destination as NavigationDestination).label)
    .toList();

String selectedTab(WidgetTester tester) {
  final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
  return (bar.destinations[bar.selectedIndex] as NavigationDestination).label;
}

Finder inTabs(Finder finder) =>
    find.descendant(of: find.byType(NavigationBar), matching: finder);

/// The page on top. A pushed page leaves the router's address as it was, so the address cannot say.
String? topPage(GoRouter router) =>
    router.routerDelegate.currentConfiguration.lastOrNull?.matchedLocation;

/// The office, recording every path the app reads; [loadBoard] answers the board.
List<String> signInAsOffice(String subrole,
    {Map<String, Object> answers = const {},
    ResponseBody Function()? loadBoard}) {
  final server = CarrierServer(
      allowed: ownerAllowed,
      subrole: subrole,
      extraAnswers: {
        '/v1/load-board': {'loads': <Object>[]},
        ...answers,
      });
  signInToCarrierApp(server);
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

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocationService());
  tearDown(DriverSession.clearCarrierCache);

  for (final subrole in ['OWNER', 'DISPATCHER']) {
    testWidgets('the office ($subrole) tabs are Home, Bookings, Trips, Load Board, Profile',
        (tester) async {
      signInAsOffice(subrole);
      await mountCarrierApp(tester, '/driver');
      expect(tabLabels(tester),
          ['Home', 'Bookings', 'Trips', 'Load Board', 'Profile']);
      expect(inTabs(find.text('Add trip')), findsNothing,
          reason: 'Add trip is an action, not a place');
    });
  }

  testWidgets('a driver keeps Home, Trips, Profile, with no Add trip on Trips',
      (tester) async {
    signInToCarrierApp(
        CarrierServer(allowed: driverAllowed, subrole: 'DRIVER'));
    await mountCarrierApp(tester, '/driver/loads');
    expect(tabLabels(tester), ['Home', 'Trips', 'Profile']);
    expect(find.text('Load Board'), findsNothing);
    expect(find.text('Add trip'), findsNothing,
        reason: 'a driver adds a trip from Profile, as before');
  });

  testWidgets('the Load Board tab opens the board, and the board and its trip form keep the tab',
      (tester) async {
    final pickupDay = calendarDayText(todayInIndia().add(const Duration(days: 1)));
    signInAsOffice('OWNER', answers: {
      '/v1/load-board': {
        'loads': [
          {
            'id': 'load-1',
            'fromCity': 'Bengaluru',
            'toCity': 'Chennai',
            'weightKg': 500,
            'earliestPickupDate': pickupDay,
            'latestPickupDate': pickupDay,
          }
        ]
      },
    });
    final router = await mountCarrierApp(tester, '/driver');
    expect(find.text('Loads shippers posted. Add a trip for one.'),
        findsNothing,
        reason: 'the tab replaces the Home card');
    await tester.tap(inTabs(find.text('Load Board')));
    await tester.pumpAndSettle();
    expect(topPage(router), '/driver/load-board');
    expect(find.text('Open loads, soonest pickup first.'), findsOneWidget);
    expect(selectedTab(tester), 'Load Board');
    expect(find.text('Back'), findsNothing,
        reason: 'the board is a tab now, not a page under Home');

    await tester.tap(find.text('Add a trip for this load'));
    await tester.pumpAndSettle();
    expect(topPage(router), '/driver/load-board/trip');
    expect(selectedTab(tester), 'Load Board');
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('a carrier not yet approved still gets the tab, and the board says why',
      (tester) async {
    final pending = {...carrierOrganization, 'kycStatus': 'SUBMITTED'};
    signInAsOffice('OWNER',
        answers: {
          '/v1/auth/me': {
            'user': {'id': 'carrier-person', 'fullName': 'Prakash Naidu'},
            'organizations': [pending],
            'principal': {
              'organizationId': 'carrier-a',
              'roles': ['CARRIER'],
              'subrole': 'OWNER',
              'permissions': ownerAllowed,
            },
          },
        },
        loadBoard: () =>
            jsonResponse({'error': 'carrier_compliance_required'}, 409));
    AuthorizationSession.organizations = [pending];
    await mountCarrierApp(tester, '/driver');
    expect(DriverSession.complianceApproved, isFalse);
    expect(tabLabels(tester),
        ['Home', 'Bookings', 'Trips', 'Load Board', 'Profile']);
    await tester.tap(inTabs(find.text('Load Board')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'NaviG8r must approve your company before you can see the Load Board.'),
        findsOneWidget);
  });

  testWidgets('Add trip on Trips opens the Add a trip form under Trips, and Trips loads again after',
      (tester) async {
    final asked = signInAsOffice('OWNER');
    final router = await mountCarrierApp(tester, '/driver/loads');
    final tripLoads = asked.where((path) => path == 'GET /v1/pilot/anchor-trips');
    final loadsBefore = tripLoads.length;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add trip'));
    await tester.pumpAndSettle();
    expect(topPage(router),
        '/driver/publish');
    expect(find.text('Add a trip'), findsOneWidget, reason: 'the form title');
    expect(selectedTab(tester), 'Trips');
    expect(find.text('Back'), findsOneWidget);

    // What the form does once the trip is added.
    router.go('/driver/loads');
    await tester.pumpAndSettle();
    expect(tripLoads.length, greaterThan(loadsBefore),
        reason: 'the new trip shows without a pull to refresh');
  });

  testWidgets('Add trip on the office Home opens the Add a trip form', (tester) async {
    signInAsOffice('DISPATCHER');
    final router = await mountCarrierApp(tester, '/driver');
    expect(find.text('Add trip'), findsOneWidget, reason: 'one button, not two');
    await tester.tap(find.text('Add trip'));
    await tester.pumpAndSettle();
    expect(topPage(router),
        '/driver/publish');
    expect(find.text('Add a trip'), findsOneWidget);
    expect(selectedTab(tester), 'Trips');
  });

  testWidgets('a Load Board alert opens the board under its tab', (tester) async {
    signInAsOffice('OWNER');
    final router = await mountCarrierApp(tester, '/driver/loads');
    await openPostedLoadNotice(tester.element(find.byType(NavigationBar)),
        notificationId: '', forShipper: false);
    await tester.pumpAndSettle();
    expect(topPage(router),
        '/driver/load-board');
    expect(selectedTab(tester), 'Load Board');
  });
}
