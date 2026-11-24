// Load Board notices (4 Nov 2026): a new load tells the carrier office, a trip added for a load tells its shipper.
// Neither belongs to a shipment, so the Updates row is named by the load's towns and opens My loads or the board.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/notice_words.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

/// Updates with one unread Load Board row, signed in with [roles]; returns the requests sent.
Future<List<String>> showUpdatesWithLoadNotice(WidgetTester tester,
    {required List<String> roles}) async {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  AuthorizationSession.clear();
  AuthorizationSession.principal = {
    'organizationId': 'org-1',
    'roles': roles,
    'permissions': ['notification.read'],
  };
  final sent = <String>[];
  api = Api('http://test');
  api.dio.httpClientAdapter = MockApiAdapter((RequestOptions request) {
    sent.add('${request.method} ${request.path}');
    if (request.path == '/v1/notifications/shipments') {
      return jsonResponse({
        'shipments': [
          {
            'shipmentId': '',
            'postedLoadId': 'load-1',
            'notificationId': 'notice-1',
            'loadRoute': 'Pune to Mumbai',
            'latestAtUtcMs': 1793000000000,
            'unreadCount': 1,
          },
          {
            'shipmentId': '',
            'postedLoadId': 'load-1',
            'notificationId': 'notice-2',
            'loadRoute': 'Pune to Mumbai',
            'latestAtUtcMs': 1792990000000,
            'unreadCount': 0,
          },
        ],
        'unreadCount': 1,
        'nextBefore': null,
      });
    }
    return jsonResponse({});
  });
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const NotificationInboxScreen()),
    GoRoute(
        path: '/customer/loads',
        builder: (_, __) => const Scaffold(body: Text('My loads screen'))),
    GoRoute(
        path: '/driver/load-board',
        builder: (_, __) => const Scaffold(body: Text('Load Board screen'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return sent;
}

void main() {
  test('each Load Board notice is worded for its own side only', () {
    expect(noticeWords('posted_load.new', forShipper: false),
        'New load on the Load Board.');
    expect(noticeWords('posted_load.new', forShipper: true), isNull,
        reason: 'a shipper is never sent one');
    expect(noticeWords('posted_load.route_made', forShipper: true),
        'A carrier added a trip for your load.');
    expect(noticeWords('posted_load.route_made', forShipper: false), isNull);
  });

  testWidgets('a shipper row names the load, marks it read and opens My loads',
      (tester) async {
    final sent = await showUpdatesWithLoadNotice(tester, roles: ['SHIPPER']);
    expect(find.text('Pune to Mumbai'), findsNWidgets(2),
        reason: 'two notices on one load are two rows, not one');
    expect(find.text('A carrier added a trip for your load.'), findsOneWidget);
    await tester.tap(find.text('A carrier added a trip for your load.'));
    await tester.pumpAndSettle();
    expect(sent, contains('PATCH /v1/notifications/notice-1/read'));
    expect(find.text('My loads screen'), findsOneWidget);
  });

  testWidgets('a carrier office row opens the Load Board', (tester) async {
    await showUpdatesWithLoadNotice(tester, roles: ['CARRIER']);
    expect(find.text('New load on the Load Board.'), findsOneWidget);
    await tester.tap(find.text('New load on the Load Board.'));
    await tester.pumpAndSettle();
    expect(find.text('Load Board screen'), findsOneWidget);
  });
}
