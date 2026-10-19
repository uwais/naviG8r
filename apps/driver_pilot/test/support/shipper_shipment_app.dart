// The shipper app on a fake server, as the shipment screen, shipments list and Home tests open it
// (PRs 5a and 5b of the redesign): a booking in each state, its lane and its e-way bill. Names, places
// and amounts are the mockups' synthetic ones.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/shipment_screen.dart';
import 'package:driver_pilot/shipper/shipments_list.dart';
import 'package:driver_pilot/shipper/shipper_home.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/format.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'mock_api.dart';

final bookedAt = DateTime.utc(2026, 10, 17, 3, 30);
final laneStart = DateTime.utc(2026, 10, 18, 3, 30);

/// The lane's dates as every screen shows them: the days the truck can leave.
final laneLeaves =
    'Leaves ${formatDateRange(laneStart, DateTime.parse('2026-10-19T12:00:00.000Z'))}';
final leftAt = DateTime.utc(2026, 10, 18, 0, 40);
final deliveredAt = DateTime.utc(2026, 10, 19, 8, 50);

/// A booking as GET /shipments returns it to the shipper. The ID starts the way real ones do.
Map<String, dynamic> booking(
        {String id = 'shp_9f2c41',
        String status = 'BOOKED',
        Map<String, dynamic>? ewayBill,
        String carrier = 'Ravi Roadways',
        Map<String, dynamic> extra = const {}}) =>
    {
      'id': id,
      'anchorTripId': 'lane-1',
      'customerOrgId': 'org-sharma',
      'carrierDisplayName': carrier,
      'status': status,
      'weightKg': 80,
      'grossPaise': 264000,
      'createdAtUtcMs': bookedAt.millisecondsSinceEpoch,
      'updatedAtUtcMs': 1,
      'pickupAddress': 'Bommasandra, Bengaluru',
      'dropAddress': 'Guindy, Chennai',
      if (ewayBill != null) 'ewayBill': ewayBill,
      ...extra,
    };

Map<String, dynamic> lane({String status = 'OPEN', DateTime? started}) => {
      'id': 'lane-1',
      'originCity': 'Bengaluru',
      'destCity': 'Chennai',
      'carrierDisplayName': 'Ravi Roadways',
      'windowStart': laneStart.toIso8601String(),
      'windowEnd': '2026-10-19T12:00:00.000Z',
      'status': status,
      if (started != null) 'startedAtUtcMs': started.millisecondsSinceEpoch,
    };

const billNoTruck = {
  'kind': 'BILL',
  'billNumber': '341200987654',
  'billDate': '2026-10-18',
  'makerGstin': '33AAACS7781L1ZQ',
  'invoiceNumber': 'ST/2026/0418',
};

/// 23:59 on 19 Oct 2026 in India.
final validUntil = DateTime.utc(2026, 10, 19, 18, 29);

Map<String, dynamic> get billWithTruck => {
      ...billNoTruck,
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': validUntil.millisecondsSinceEpoch,
    };

const notNeededBill = {
  'kind': 'NOT_NEEDED',
  'notNeededReason': 'GOODS_EXEMPT',
};

/// A shipment waiting on the shipper's e-way bill: the carrier accepted and named the truck.
Map<String, dynamic> get needsBill => booking(extra: {
      'assignedTruckNumber': 'KA01AB1234',
      'carrierTransporterId': '29ABCDE1234F1Z5',
    });

class FakeServer {
  final requests = <RequestOptions>[];
  final answers = <String, Object>{};
}

/// A phone 360 dp wide, or [width] for the desktop layout, signed in as a Sharma Textiles shipper
/// who may write the bill and add the truck. [height] is 800 for "visible without scrolling"
/// checks; taller elsewhere, because the test font draws every letter a full square wide.
Future<FakeServer> showShipperApp(WidgetTester tester, String start,
    {double height = 3000, double width = 360}) async {
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
  AuthorizationSession.principal!['permissions'] = [
    ...AuthorizationSession.principal!['permissions'] as List,
    'eway_bill.write',
    'eway_bill.add_truck',
    'notification.read',
    'conversation.read',
  ];
  api.selectOrganization('org-sharma');
  final server = FakeServer();
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    server.requests.add(request);
    final answer = server.answers[request.uri.path];
    // A refusal is given as its own jsonResponse with a status code.
    return answer is ResponseBody ? answer : jsonResponse(answer ?? {});
  });
  final router = GoRouter(initialLocation: start, routes: [
    GoRoute(
        path: '/customer',
        builder: (_, __) => const CustomerHomeScreen(),
        routes: [
          GoRoute(
              path: 'trips', builder: (_, __) => const Text('Lanes screen')),
          GoRoute(
              path: 'shipments',
              builder: (_, __) => const CustomerShipmentsScreen()),
          GoRoute(
              path: 'shipments/:id',
              builder: (_, state) => CustomerShipmentDetailScreen(
                  shipmentId: state.pathParameters['id']!)),
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  return server;
}

/// A paid booking's payment: checkout finished, the money held until delivery.
const heldPayment = {'status': 'AUTHORIZED', 'amountPaise': 264000};

/// Opens [shipment]'s screen with the trip the tracking call returns, and [heldPayment] unless
/// [payment] says otherwise.
Future<FakeServer> showShipment(
    WidgetTester tester, Map<String, dynamic> shipment,
    {Map<String, dynamic>? trip,
    Map<String, dynamic>? payment,
    double height = 3000,
    double width = 360}) async {
  final server = await showShipperApp(
      tester, '/customer/shipments/${shipment['id']}',
      height: height, width: width);
  server.answers['/shipments/${shipment['id']}'] = {
    'shipment': shipment,
    'payment': payment ?? heldPayment,
  };
  server.answers['/shipments/${shipment['id']}/tracking'] = {
    if (trip != null) 'trip': trip
  };
  await tester.pumpAndSettle();
  return server;
}

/// Leaves the screen, so its 15 second refresh stops before the test ends.
Future<void> leave(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Finder entry(String label) => find.descendant(
    of: find.widgetWithText(NvField, label), matching: find.byType(TextField));
