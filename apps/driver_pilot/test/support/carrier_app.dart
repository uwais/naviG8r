// The carrier side of the app as it runs: the real driver routes and shell, over a fake server that answers
// every read those screens make. For tests that walk through screens, as a driver or as the office.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'carrier_fixtures.dart';
import 'mock_api.dart';

/// What the server lets a DRIVER do (api/rbac.ts): no payment.read, no trip.assign, no eway_bill.add_truck.
const driverAllowed = [
  'organization.profile.read',
  'load.read',
  'trip.publish',
  'load.status_update',
  'carrier.offer_accept',
  'pod.upload',
  'kyc.status_read',
  'conversation.read',
];

/// An owner: everything the office does, payments and bank details included.
const ownerAllowed = [
  'organization.profile.read',
  'organization.member.invite',
  'load.read',
  'trip.publish',
  'load.status_update',
  'carrier.offer_accept',
  'pod.upload',
  'payment.read',
  'bank_account.create_token',
  'conversation.read',
  'eway_bill.add_truck',
  'trip.assign',
  'transporter_id.write',
];

/// 06:00 India time on the day [daysFromToday] days from today in India, as the server sends a trip's window.
String windowAt(int daysFromToday, {int hourInIndia = 6}) {
  final india = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(india.year, india.month, india.day + daysFromToday,
          hourInIndia)
      .subtract(const Duration(hours: 5, minutes: 30))
      .toIso8601String();
}

Map<String, dynamic> carrierTrip(String id,
        {String from = 'Bengaluru',
        String to = 'Chennai',
        String status = 'OPEN',
        int startsInDays = 0,
        String truck = 'KA01AB1234'}) =>
    {
      'id': id,
      'originCity': from,
      'destCity': to,
      'windowStart': windowAt(startsInDays),
      'windowEnd': windowAt(startsInDays + 1, hourInIndia: 20),
      'status': status,
      'vehicleClass': 'MEDIUM',
      'capacityKg': 1000,
      'reservedKg': 600,
      'createdAtUtcMs': 1760000000000,
      'assignedVehicleId': 'vehicle-1',
      'assignedTruckNumber': truck,
      'assignedDriverUserId': 'driver-1',
      'assignedDriverName': 'Prakash Naidu',
    };

Map<String, dynamic> carrierBooking(String tripId, String id,
        {required String shipper,
        required String drop,
        num weightKg = 80,
        String status = 'BOOKED',
        Map<String, dynamic>? bill}) =>
    {
      'id': id,
      'anchorTripId': tripId,
      'customerOrgId': 'shipper-$id',
      'customerOrgName': shipper,
      'status': status,
      'weightKg': weightKg,
      'pickupAddress': 'Peenya, Bengaluru',
      'dropAddress': drop,
      'assignedTruckNumber': 'KA01AB1234',
      'updatedAtUtcMs': 1760000000000,
      if (bill != null) 'ewayBill': bill,
    };

/// The fake server. It changes as the app writes: a confirmed delivery moves the booking on.
class CarrierServer {
  CarrierServer(
      {required this.allowed,
      required this.subrole,
      this.trips = const [],
      List<Map<String, dynamic>> bookings = const [],
      this.extraAnswers = const {}})
      : bookings = [for (final booking in bookings) {...booking}];
  final List<String> allowed;
  final String subrole;
  final List<Map<String, dynamic>> trips;
  final List<Map<String, dynamic>> bookings;

  /// More answers by path, for amounts and payouts a test wants on offer.
  final Map<String, Object> extraAnswers;
  final sent = <RequestOptions>[];

  /// 14:20 India time today, when a delivery is confirmed.
  static final deliveredAtUtcMs = DateTime.parse(windowAt(0, hourInIndia: 14))
      .add(const Duration(minutes: 20))
      .millisecondsSinceEpoch;

  Map<String, dynamic> get principal => {
        'organizationId': 'carrier-a',
        'roles': ['CARRIER'],
        'subrole': subrole,
        'permissions': allowed,
      };

  ResponseBody answer(RequestOptions request) {
    if (request.method != 'GET') {
      sent.add(request);
      final pod = RegExp(r'^/shipments/(.+)/driver-pod$')
          .firstMatch(request.path);
      if (pod != null) {
        final booking =
            bookings.firstWhere((booking) => booking['id'] == pod[1]);
        booking['status'] = 'PENDING_RELEASE';
        booking['podAtUtcMs'] = deliveredAtUtcMs;
        return jsonResponse({'shipment': booking});
      }
      return jsonResponse({'trip': trips.isEmpty ? null : trips.first});
    }
    final extra = extraAnswers[request.path];
    if (extra != null) return jsonResponse(extra);
    switch (request.path) {
      case '/v1/auth/me':
        return jsonResponse({
          'user': AuthorizationSession.user,
          'organizations': [carrierOrganization],
          'principal': principal,
        });
      case '/v1/pilot/me':
        return jsonResponse({
          'organizations': [carrierOrganization],
          'driverProfile': {'primaryVehicleId': 'vehicle-1'},
          'vehicles': [
            {
              'id': 'vehicle-1',
              'registrationNumber': 'KA01AB1234',
              'vehicleClass': 'MEDIUM',
              'capacityKg': 1000
            }
          ],
        });
      case '/v1/pilot/carrier/fleet':
        return jsonResponse({
          'vehicles': [
            {
              'id': 'vehicle-1',
              'registrationNumber': 'KA01AB1234',
              'vehicleClass': 'MEDIUM'
            }
          ],
          'drivers': [
            {'userId': 'driver-1', 'displayName': 'Prakash Naidu'}
          ],
        });
      case '/v1/pilot/anchor-trips':
        return jsonResponse({'trips': trips});
      case '/v1/pilot/carrier/shipments':
        final tripId = request.queryParameters['anchorTripId'];
        return jsonResponse({
          'shipments': [
            for (final booking in bookings)
              if (tripId == null || booking['anchorTripId'] == tripId) booking
          ]
        });
      case '/v1/notifications/shipments':
        return jsonResponse({'unreadCount': 0, 'items': <Object>[]});
    }
    final tripPath =
        RegExp(r'^/v1/pilot/anchor-trips/([^/]+)$').firstMatch(request.path);
    if (tripPath != null) {
      final found = trips.where((trip) => trip['id'] == tripPath[1]);
      if (found.isNotEmpty) return jsonResponse({'trip': found.first});
    }
    return jsonResponse({'error': 'not_found'}, 404);
  }
}

/// Signs in at the approved carrier-a with the server's answers for [server].
CarrierServer signInToCarrierApp(CarrierServer server) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  api = Api('http://test');
  AuthorizationSession.clear();
  AuthorizationSession.user = {
    'id': 'carrier-person',
    'fullName': 'Prakash Naidu',
    'phone': '9900122334',
  };
  AuthorizationSession.principal = server.principal;
  AuthorizationSession.organizations = [carrierOrganization];
  api.selectOrganization('carrier-a');
  api.dio.httpClientAdapter = MockApiAdapter(server.answer);
  return server;
}

/// A widget test has no location service: location is off for good, so nothing is shared.
class NoLocationService extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;
}

/// The app's carrier routes at [path], inside the real shell, with the same access checks as the app, on a
/// screen of [size] at [textScale] (1 is the phone's default text size).
Future<GoRouter> mountCarrierApp(WidgetTester tester, String path,
    {Size size = const Size(360, 800), double textScale = 1}) async {
  GeolocatorPlatform.instance = NoLocationService();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
      initialLocation: path,
      redirect: (_, state) => mobileAccessRedirect(state.uri.path),
      routes: [
        ...driverFlowRoutes(),
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('Start page'))),
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
  return router;
}

/// Opens [path] in the mounted app and waits for it to load.
Future<void> openPath(WidgetTester tester, GoRouter router, String path) async {
  router.go(path);
  await tester.pumpAndSettle();
}

/// Every word on screen in a Text, sheets and snack bars included.
List<String> textsOnScreen(WidgetTester tester) => [
      for (final text in tester.widgetList<Text>(find.byType(Text)))
        text.data ?? text.textSpan?.toPlainText() ?? '',
      for (final text
          in tester.widgetList<SelectableText>(find.byType(SelectableText)))
        text.data ?? text.textSpan?.toPlainText() ?? '',
    ];

/// Every announcement a screen reader would get.
List<String> listenForAnnouncements(WidgetTester tester) {
  final heard = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    if ((message as Map)['type'] == 'announce') {
      heard.add((message['data'] as Map)['message'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return heard;
}
