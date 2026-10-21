// Rishabh, 20 Oct 2026: "from any screen a notification is visible when an action is taken by any
// party". The bell sits in the header of every signed-in screen, one 15 s check serves the whole
// app, and a new notice shows a short banner.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

Finder _bellInHeader() => find.descendant(
    of: find.byType(NvHeader), matching: find.byType(NotificationBell));

int _countOf(FakeServer server, String path) =>
    server.requests.where((request) => request.uri.path == path).length;

/// A second at a time until [finder] shows, at most one check interval: one long pump would also
/// run the banner's own few seconds and hide it again.
Future<void> _pumpUntilShown(WidgetTester tester, Finder finder) async {
  for (var waited = 0;
      waited <= NotificationWatch.interval.inSeconds && finder.evaluate().isEmpty;
      waited++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Map<String, dynamic> _notices(int unread, [String? eventKey, String? id]) => {
      'unreadCount': unread,
      'notifications': [
        if (eventKey != null) {'eventKey': eventKey, 'shipmentId': id},
      ],
    };

void main() {
  testWidgets('the bell is in the header of the shipper shipment screen',
      (tester) async {
    await showShipment(tester, booking());
    expect(_bellInHeader(), findsOneWidget);
    await leave(tester);
  });

  testWidgets('the bell is in the header of the carrier booking screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    AuthorizationSession.clear();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path != '/v1/auth/me') return jsonResponse({});
      return jsonResponse({
        'user': {'id': 'owner-1', 'fullName': 'Ravi', 'phone': '9845012345'},
        'organizations': [
          {
            'id': 'org-ravi',
            'displayName': 'Ravi Roadways',
            'kind': 'CARRIER_FLEET',
            'kycStatus': 'APPROVED'
          }
        ],
        'principal': {
          'organizationId': 'org-ravi',
          'roles': ['CARRIER'],
          'subrole': 'OWNER',
          'permissions': ['load.read', 'notification.read'],
        },
      });
    });
    api.selectOrganization('org-ravi');
    await tester.pumpWidget(const DriverPilotApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    GoRouter.of(tester.element(find.byType(NvHeader)))
        .go('/driver/shipment/shipment-a');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_bellInHeader(), findsOneWidget,
        reason: 'the booking screen has no title row, so the bell must be in the header');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a new notice shows a banner with the badge, which hides after a few seconds, and View opens the shipment',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    server.answers['/v1/notifications'] = _notices(0);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing,
        reason: 'notices already there when the screen opens raise no banner');

    server.answers['/v1/notifications'] =
        _notices(1, 'shipment.carrier_accepted', 'shp_9f2c41');
    await _pumpUntilShown(tester, find.text('The carrier accepted your booking.'));
    await tester.pumpAndSettle();
    expect(find.text('The carrier accepted your booking.'), findsOneWidget);
    expect(find.byTooltip('Notifications, 1 unread'), findsOneWidget);
    await tester.pump(NotificationWatch.bannerTime);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing,
        reason: 'it hides after a few seconds');

    server.answers['/shipments/shp_other'] = {
      'shipment': booking(id: 'shp_other')
    };
    server.answers['/v1/notifications'] =
        _notices(2, 'trip.started', 'shp_other');
    await _pumpUntilShown(tester, find.text('Your goods are on the way.'));
    await tester.pumpAndSettle();
    expect(find.text('Your goods are on the way.'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(_countOf(server, '/shipments/shp_other'), greaterThan(0),
        reason: 'View opens that shipment');
    await leave(tester);
  });

  testWidgets('two bells on screen share one check every 15 s', (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Column(children: [NotificationBell(), NotificationBell()]))));
    await tester.pumpAndSettle();
    final before = _countOf(server, '/v1/notifications');
    await tester.pump(NotificationWatch.interval);
    await tester.pumpAndSettle();
    expect(_countOf(server, '/v1/notifications'), before + 1,
        reason: 'one timer for the app, not one per bell');
    await leave(tester);
  });

  testWidgets('a driver is never shown a payment notice', (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    server.answers['/v1/notifications'] = _notices(0);
    AuthorizationSession.principal = {
      ...AuthorizationSession.principal!,
      'roles': ['CARRIER'],
      'subrole': 'DRIVER',
    };
    await tester.pumpAndSettle();
    server.answers['/v1/notifications'] =
        _notices(1, 'payment.status_changed', 'shp_9f2c41');
    await tester.pump(NotificationWatch.interval);
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    await leave(tester);
  });
}
