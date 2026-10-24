// R4, bug-hunt batch 2: Home loads again when it is shown again, through its route listener, and also when the
// account changes. The hunt read that sign-in and a company switch could load it twice. Here the route listener
// runs first and the account listener then skips, so each loads Home once; these tests keep it that way.
import 'dart:async';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

Future<void> pumpFrames(WidgetTester tester, [int count = 40]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Map<String, dynamic> organization(String id, String name) =>
    {'id': id, 'displayName': name, 'kind': 'CUSTOMER'};

void main() {
  late int homeLoads;

  setUp(() {
    homeLoads = 0;
    api = Api('http://test');
    AuthorizationSession.clear();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/me') {
        if (request.headers['authorization'] == null) {
          return jsonResponse({'error': 'unauthorized'}, 401);
        }
        final selected =
            request.headers['x-organization-id'] as String? ?? 'org-sharma';
        return jsonResponse({
          'user': {'id': 'p1', 'fullName': 'Priya', 'phone': '9845012345'},
          'organizations': [
            organization('org-sharma', 'Sharma Textiles'),
            organization('org-mehta', 'Mehta Hardware'),
          ],
          'principal': {
            'organizationId': selected,
            'roles': ['SHIPPER'],
            'subrole': 'CUSTOMER_ADMIN',
            'permissions': ['load.read'],
          }
        });
      }
      if (request.uri.path == '/shipments') {
        homeLoads++;
        return jsonResponse({'shipments': []});
      }
      return jsonResponse({});
    });
  });

  testWidgets('R4 signing in loads Home once', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const DriverPilotApp());
    await pumpFrames(tester);
    final router = GoRouter.of(tester.element(find.byType(Navigator).last));
    router.go('/customer/login');
    await pumpFrames(tester);

    // What the sign-in screen does once the code is right.
    unawaited(() async {
      await api.setToken('synthetic');
      await CustomerSession.refresh();
      router.go(AuthorizationSession.home);
    }());
    await pumpFrames(tester, 80);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/customer');
    expect(homeLoads, 1);
  });

  testWidgets('R4 switching company loads Home once', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api.selectOrganization('org-sharma');
    await tester.pumpWidget(const DriverPilotApp());
    await pumpFrames(tester);
    final router = GoRouter.of(tester.element(find.byType(NvHeader).first));
    router.go('/customer/shipments');
    await pumpFrames(tester);
    homeLoads = 0;

    unawaited(AuthorizationSession.selectOrganization('org-mehta'));
    await pumpFrames(tester, 80);

    expect(AuthorizationSession.organizationId, 'org-mehta');
    expect(homeLoads, 1);
  });
}
