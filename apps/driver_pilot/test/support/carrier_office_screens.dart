// The office's Trips, trip, Publish and Profile screens on a fake server, as their tests open them (PR 7
// of the redesign): trips, bookings on them, the fleet, and the requests the screens sent.
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'carrier_fixtures.dart';
import 'mock_api.dart';

const ownerAllowed = [
  'trip.assign',
  'trip.publish',
  'load.status_update',
  'organization.member.invite',
  'transporter_id.write',
  'bank_account.create_token',
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
      this.refusal = const {'error': 'trip_not_startable'},
      this.fleetFails = false,
      this.emptyFleet = false,
      this.reminderAnswer = const {'sent': true}});
  final List<String> allowed;
  final bool office;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> bookings;
  final bool ownTruck;

  /// Every write is answered with a 409 and [refusal], by default a code the app has no sentence for.
  final bool refusesWrites;
  final Map<String, dynamic> refusal;

  /// The fleet request is answered with a 500, as when the server is down.
  final bool fleetFails;

  /// The fleet loads with no trucks and no drivers.
  final bool emptyFleet;

  /// The answer to Remind [Shipper] when writes are not refused: {sent: false} when a reminder is already unread.
  final Map<String, dynamic> reminderAnswer;
  final sent = <RequestOptions>[];

  void answer() {
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.method != 'GET') {
        sent.add(request);
        if (refusesWrites) {
          return jsonResponse(refusal, 409);
        }
        if (request.path.endsWith('/eway-bill-reminder')) {
          return jsonResponse(reminderAnswer);
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

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

/// A widget test has no location service. Starting a trip asks for one; this one says it is off for good.
class NoLocation extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;
}
