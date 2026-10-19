// The office's bookings on a fake server, as the Home, Bookings list and booking screen tests open them
// (PR 6 of the redesign).
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'carrier_fixtures.dart';
import 'mock_api.dart';

/// 06:00 India time on 18 Oct of this year, and 20:00 on 19 Oct, as the server sends a trip's window.
final _thisYear = DateTime.now().year;
final _windowStart = DateTime.utc(_thisYear, 10, 18, 0, 30).toIso8601String();
final tripWindowEnd = DateTime.utc(_thisYear, 10, 19, 14, 30).toIso8601String();

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
      'windowEnd': tripWindowEnd,
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
