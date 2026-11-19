// X1 from bug-hunt batch 2: signing out from Updates leaves nothing of the old account on screen.
// One file per side calls this, because sign-out waits for the alert registration to be removed, as on
// main, and push work a finished test left behind in the same isolate never ends and would hold it.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_account_sheet.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_api.dart';

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Map<String, dynamic> _signedInAs(String side) => {
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

void signOutFromUpdatesTest(String side) {
  testWidgets(
      'X1 sign out from Updates $side: the Updates list of the old account closes on sign-out',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    AuthorizationSession.clear();
    final me = _signedInAs(side);
    final orgName = (me['organizations'] as List).first['displayName'];
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      if (request.headers['authorization'] == null) {
        return jsonResponse({'error': 'unauthorized'}, 401);
      }
      if (request.uri.path == '/v1/auth/me') return jsonResponse(me);
      if (request.uri.path == '/v1/notifications/shipments') {
        return jsonResponse({
          'shipments': [
            {'shipmentId': 's1', 'unreadCount': 3, 'latestAtUtcMs': 1760000000000}
          ]
        });
      }
      if (request.uri.path == '/v1/notifications') {
        return jsonResponse({'unreadCount': 3, 'notifications': []});
      }
      return jsonResponse({});
    });
    api.selectOrganization((me['principal'] as Map)['organizationId'] as String);
    await tester.pumpWidget(const DriverPilotApp());
    await _pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.notifications_outlined).first);
    await _pumpFrames(tester);
    expect(find.text('3 new updates'), findsOneWidget);

    await tester.tap(find
        .descendant(of: find.byType(NvHeader), matching: find.text(orgName))
        .last);
    await _pumpFrames(tester);
    await tester.tap(find.descendant(
        of: find.byType(NvAccountSheet), matching: find.text('Sign out')));
    // The registration removal runs on real async, so the test gives it real time.
    for (var i = 0; i < 40 && AuthorizationSession.signedIn; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await _pumpFrames(tester);
    }

    expect(AuthorizationSession.signedIn, isFalse);
    expect(find.text('3 new updates'), findsNothing,
        reason: 'nothing from the old account stays on screen');
    expect(find.text('Updates'), findsNothing);
    expect(find.byType(NvHeader), findsNothing);
  });
}
