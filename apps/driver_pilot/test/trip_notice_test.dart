// Owner, 21 Oct 2026: a driver hears of a trip given to them, booked on or not. The notice has no shipment, so the
// Updates row is named by the trip's route and opens the trip.
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

void main() {
  test('a new trip is worded for the carrier side only', () {
    expect(noticeWords('trip.assigned', forShipper: false), 'You have a new trip.');
    expect(noticeWords('trip.assigned', forShipper: true), isNull,
        reason: 'a shipper is never sent one');
  });

  testWidgets('the Updates row for a new trip names its route, marks it read and opens the trip',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    AuthorizationSession.clear();
    final sent = <String>[];
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((RequestOptions request) {
      sent.add('${request.method} ${request.path}');
      if (request.path == '/v1/notifications/shipments') {
        return jsonResponse({
          'shipments': [
            {
              'shipmentId': '',
              'tripId': 'trip-9',
              'notificationId': 'notice-1',
              'tripRoute': 'Hoskote to Kolar',
              'latestAtUtcMs': 1791392400000,
              'unreadCount': 1,
            },
          ],
          'unreadCount': 1,
          'nextBefore': null,
        });
      }
      return jsonResponse({'notification': {'id': 'notice-1'}});
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const NotificationInboxScreen()),
      GoRoute(
          path: '/driver/trip/:tripId/active',
          builder: (_, state) =>
              Scaffold(body: Text('Trip ${state.pathParameters['tripId']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Hoskote to Kolar'), findsOneWidget);
    expect(find.text('You have a new trip.'), findsOneWidget);
    await tester.tap(find.text('Hoskote to Kolar'));
    await tester.pumpAndSettle();
    expect(sent, contains('PATCH /v1/notifications/notice-1/read'));
    expect(find.text('Trip trip-9'), findsOneWidget, reason: 'opening it goes to the trip');
  });

  testWidgets('Updates pushed over the shell, as the bell opens it, closes so the trip is on top',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    AuthorizationSession.clear();
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((RequestOptions request) =>
        request.path == '/v1/notifications/shipments'
            ? jsonResponse({
                'shipments': [
                  {
                    'shipmentId': '',
                    'tripId': 'trip-9',
                    'notificationId': 'notice-1',
                    'tripRoute': 'Hoskote to Kolar',
                    'latestAtUtcMs': 1791392400000,
                    'unreadCount': 1,
                  },
                ],
                'unreadCount': 1,
                'nextBefore': null,
              })
            : jsonResponse({'notification': {'id': 'notice-1'}}));
    final router = GoRouter(initialLocation: '/driver', routes: [
      ShellRoute(
        builder: (_, __, child) => Scaffold(body: child),
        routes: [
          GoRoute(
            path: '/driver',
            builder: (context, _) => TextButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const NotificationInboxScreen())),
                child: const Text('Open Updates')),
            routes: [
              GoRoute(
                  path: 'trip/:tripId/active',
                  builder: (_, state) =>
                      Text('Trip ${state.pathParameters['tripId']}')),
            ],
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoskote to Kolar'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationInboxScreen), findsNothing,
        reason: 'review: the trip opened behind Updates');
    expect(find.text('Trip trip-9'), findsOneWidget);
  });
}
