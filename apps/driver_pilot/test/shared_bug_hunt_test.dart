import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/plain_error_sentence.dart';
import 'package:driver_pilot/push_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

// Bug-hunt batch 2, the fixes shared by the shipper and carrier screens. Each test failed before its fix.

Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> signedInAs(String side) => {
      'user': {'id': 'p1', 'fullName': 'Priya', 'phone': '9845012345'},
      'organizations': [
        {
          'id': side == 'shipper' ? 'org-sharma' : 'org-ravi',
          'displayName': side == 'shipper' ? 'Sharma Textiles' : 'Ravi Roadways',
          'kind': side == 'shipper' ? 'CUSTOMER' : 'CARRIER_FLEET',
          'kycStatus': 'APPROVED'
        }
      ],
      'principal': {
        'organizationId': side == 'shipper' ? 'org-sharma' : 'org-ravi',
        'roles': [side == 'shipper' ? 'SHIPPER' : 'CARRIER'],
        'subrole': side == 'shipper' ? 'CUSTOMER_ADMIN' : 'OWNER',
        'permissions': ['load.read', 'notification.read', 'conversation.read'],
      }
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  x7SignOutRemovesAlertRegistration();
  x10AppTitle();
  x9NotReadyForDelivery();
  x6UpdatesKeepEarlierRows();
  o2TripNotStarted();
  // X1, sign out from Updates, is in sign_out_from_updates_*_test.dart, one isolate per side.
}

void x7SignOutRemovesAlertRegistration() {
  test('X7 sign-out removes the alert registration with the old sign-in before it ends',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'old-token',
      'push_device_owner': 'p1',
      'push_device_id': 'device-1',
      'push_device_generation': '7',
    });
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.bind();
    final removalSent = Completer<String?>();
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      if (request.uri.path == '/v1/auth/me') {
        return request.headers['authorization'] == null
            ? jsonResponse({'error': 'unauthorized'}, 401)
            : jsonResponse(signedInAs('carrier'));
      }
      if (request.method == 'DELETE') {
        if (!removalSent.isCompleted) {
          removalSent.complete(request.headers['authorization'] as String?);
        }
        return jsonResponse({});
      }
      return jsonResponse({});
    });
    await AuthorizationSession.refresh();
    expect(AuthorizationSession.signedIn, isTrue);

    await AuthorizationSession.signOut()
        .timeout(const Duration(seconds: 2));

    expect(removalSent.isCompleted, isTrue,
        reason: 'sign-out waits for the registration to be removed, as on main');
    expect(await removalSent.future, 'Bearer old-token');
    expect(AuthorizationSession.signedIn, isFalse);
    expect(
        await const FlutterSecureStorage().read(key: 'access_token'), isNull);
    PushNotifications.instance.onCredentialChanged();
  });
}

void x10AppTitle() {
  testWidgets('X10 the app title is NaviG8r, not Customer or Driver',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    AuthorizationSession.clear();
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unauthorized'}, 401));
    await tester.pumpWidget(const DriverPilotApp());
    await pumpFrames(tester);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'NaviG8r');
  });
}

DioException refusalOf(String code, [String? detail]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 409,
          data: {'error': code, if (detail != null) 'detail': detail}),
    );

void x9NotReadyForDelivery() {
  group('X9 a booking not ready for delivery', () {
    for (final (subrole, sentence) in [
      ('OWNER_DRIVER', 'This booking is not ready for delivery yet.'),
      ('DRIVER', 'This booking is not ready for delivery yet. Ask your office.'),
    ]) {
      test('$subrole reads: $sentence', () {
        AuthorizationSession.principal = {
          'organizationId': 'org-ravi',
          'roles': ['CARRIER'],
          'subrole': subrole,
          'permissions': ['pod.upload'],
        };
        expect(
            formatApiError(refusalOf('checkout_not_completed_for_pod',
                'This booking is not ready for delivery yet.')),
            sentence);
      });
    }
  });
}

void x6UpdatesKeepEarlierRows() {
  testWidgets('X6 the 30-second check keeps the earlier updates the reader loaded',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    final me = signedInAs('carrier');
    AuthorizationSession.user = me['user'] as Map<String, dynamic>;
    AuthorizationSession.organizations =
        (me['organizations'] as List).cast<Map<String, dynamic>>();
    AuthorizationSession.principal = me['principal'] as Map<String, dynamic>;
    api.selectOrganization('org-ravi');
    var newest = [
      {'shipmentId': 's1', 'unreadCount': 3, 'latestAtUtcMs': 1760000000000}
    ];
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      if (request.uri.path == '/v1/notifications/shipments') {
        final older = request.uri.queryParameters['before'] != null;
        return jsonResponse({
          'shipments': older
              ? [
                  {
                    'shipmentId': 's0',
                    'unreadCount': 2,
                    'latestAtUtcMs': 1750000000000
                  }
                ]
              : newest,
          'nextBefore': older ? null : 'cursor-1',
        });
      }
      return jsonResponse({'unreadCount': 0, 'notifications': []});
    });
    await tester.pumpWidget(
        const MaterialApp(home: NotificationInboxScreen()));
    await pumpFrames(tester);
    await tester.tap(find.text('Show earlier updates'));
    await pumpFrames(tester);
    expect(find.text('2 new updates'), findsOneWidget);

    newest = [
      {'shipmentId': 's2', 'unreadCount': 1, 'latestAtUtcMs': 1770000000000},
      {'shipmentId': 's1', 'unreadCount': 3, 'latestAtUtcMs': 1760000000000},
    ];
    await tester.pump(const Duration(seconds: 31));
    await pumpFrames(tester);
    expect(find.text('2 new updates'), findsOneWidget,
        reason: 'the earlier row the reader loaded stays');
    expect(find.text('New update'), findsOneWidget,
        reason: 'the new row is added');
    expect(find.text('3 new updates'), findsOneWidget,
        reason: 'a row in both pages shows once');
    expect(find.text('Show earlier updates'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

void o2TripNotStarted() {
  test('O2 delivery or a photo before the start reads: Start the trip first.',
      () {
    expect(
        plainErrorSentence(
            refusalOf('trip_not_started', 'Start the trip first.')),
        'Start the trip first.');
  });
}
