// Rishabh, 20 Oct 2026: "from any screen a notification is visible when an action is taken by any
// party". The bell sits in the header of every signed-in screen, one 30 s check serves the whole
// app, and a new notice shows a short banner.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/notification_bell.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/app_lifecycle.dart';
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
    await _pumpUntilShown(tester, find.text('The carrier accepted your shipment.'));
    await tester.pumpAndSettle();
    expect(find.text('The carrier accepted your shipment.'), findsOneWidget);
    expect(find.byTooltip('Updates, 1 new'), findsOneWidget);
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

  testWidgets('two bells on screen share one check every 30 s', (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Column(children: [NotificationBell(), NotificationBell()]))));
    await tester.pumpAndSettle();
    final before = _countOf(server, '/v1/notifications');
    await tester.pump(const Duration(seconds: 15));
    expect(_countOf(server, '/v1/notifications'), before,
        reason: 'every 30 s, not 15');
    await tester.pump(const Duration(seconds: 15));
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

  testWidgets(
      'View still opens the shipment after the screen that showed the banner has gone',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    server.answers['/shipments/shp_other'] = {
      'shipment': booking(id: 'shp_other')
    };
    server.answers['/v1/notifications'] = _notices(0);
    await tester.pumpAndSettle();
    server.answers['/v1/notifications'] =
        _notices(1, 'trip.started', 'shp_other');
    await _pumpUntilShown(tester, find.text('Your goods are on the way.'));
    await tester.pumpAndSettle();

    GoRouter.of(tester.element(find.byType(NvHeader).first))
        .go('/customer/shipments');
    await tester.pumpAndSettle();
    expect(find.text('Your goods are on the way.'), findsOneWidget,
        reason: 'the banner outlives the screen that showed it');
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_countOf(server, '/shipments/shp_other'), greaterThan(0),
        reason: 'View opens that shipment from the screen now showing');
    await leave(tester);
  });

  testWidgets('when the last bell goes, so do its banner and the count',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    server.answers['/v1/notifications'] = _notices(0);
    await tester.pumpAndSettle();
    final bellShown = ValueNotifier(true);
    addTearDown(bellShown.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            appBar: AppBar(actions: [
              ValueListenableBuilder<bool>(
                  valueListenable: bellShown,
                  builder: (_, shown, __) => shown
                      ? const NotificationBell()
                      : const SizedBox.shrink())
            ]),
            body: const SizedBox.shrink())));
    await tester.pumpAndSettle();
    server.answers['/v1/notifications'] =
        _notices(1, 'trip.started', 'shp_9f2c41');
    await _pumpUntilShown(tester, find.text('Your goods are on the way.'));
    await tester.pumpAndSettle();
    expect(NotificationWatch.unread.value, 1);

    bellShown.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing,
        reason: 'signed out, the last notice must not stay on screen');
    expect(NotificationWatch.unread.value, 0);
    await leave(tester);
  });

  testWidgets('an answer older than the newest check is dropped',
      (tester) async {
    await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    await tester.pumpAndSettle();
    await leave(tester);
    final waiting = <Completer<ResponseBody>>[];
    api.dio.httpClientAdapter = MockApiAdapter((_) {
      final answer = Completer<ResponseBody>();
      waiting.add(answer);
      return answer.future;
    });
    NotificationWatch.check();
    await tester.pump(const Duration(milliseconds: 100));
    NotificationWatch.check();
    await tester.pump(const Duration(milliseconds: 100));
    expect(waiting, hasLength(2));

    waiting[1].complete(jsonResponse(_notices(5)));
    await tester.pump(const Duration(milliseconds: 100));
    waiting[0].complete(jsonResponse(_notices(1)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(NotificationWatch.unread.value, 5,
        reason: 'the first check answered last, and is older');
  });

  for (final (who, subrole, owner) in [
    ('a dispatcher', 'DISPATCHER', false),
    ('an owner', 'OWNER', true),
  ]) {
    testWidgets(
        '$who ${owner ? 'is' : 'is not'} shown a payment notice, as on Earnings',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
      server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
      server.answers['/v1/notifications'] = _notices(0);
      final permissions = [
        for (final permission
            in AuthorizationSession.principal!['permissions'] as List)
          if (permission != 'bank_account.create_token') permission,
        'payment.read',
        if (owner) 'bank_account.create_token',
      ];
      AuthorizationSession.principal = {
        ...AuthorizationSession.principal!,
        'roles': ['CARRIER'],
        'subrole': subrole,
        'permissions': permissions,
      };
      await tester.pumpAndSettle();
      server.answers['/v1/notifications'] =
          _notices(1, 'payment.status_changed', 'shp_9f2c41');
      await _pumpUntilShown(tester, find.text('A payment was updated.'));
      expect(find.text('A payment was updated.'),
          owner ? findsOneWidget : findsNothing);
      await leave(tester);
    });
  }

  testWidgets(
      'the bell does not check while the app is in the background, and checks once on return',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    await tester.pumpAndSettle();
    final before = _countOf(server, '/v1/notifications');

    await sendAppToBackground(tester);
    await tester.pump(NotificationWatch.interval * 3);
    expect(_countOf(server, '/v1/notifications'), before,
        reason: 'a phone in a pocket makes no checks');

    await bringAppBack(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_countOf(server, '/v1/notifications'), before + 1,
        reason: 'one check on return, not one per missed turn');
    await leave(tester);
  });

  testWidgets("Home's Updates row shows the bell's count, with no check of its own",
      (tester) async {
    final server = await showShipperApp(tester, '/customer');
    server.answers['/v1/notifications'] = _notices(3);
    server.answers['/v1/notifications/shipments'] = {
      'shipments': [],
      'unreadCount': 2
    };
    await tester.pumpAndSettle();
    expect(find.text('3 new'), findsOneWidget);
    expect(_countOf(server, '/v1/notifications/shipments'), 0,
        reason: 'one check for the bell and the row');
    await leave(tester);
  });
}
