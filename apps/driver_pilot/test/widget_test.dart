import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'support/mock_api.dart';

void main() {
  testWidgets(
      'Signed-out mobile app offers driver login without protected data',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unauthorized'}, 401));
    AuthorizationSession.clear();
    await tester.pumpWidget(const DriverPilotApp());
    await tester.pumpAndSettle();
    expect(find.text('Sign in with phone'), findsOneWidget);
    expect(find.text('Driver & carrier'), findsOneWidget);
    expect(find.text('Manage payout method'), findsNothing);
  });
  testWidgets(
      'App-root organization picker switches shipper and internal workspaces',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    AuthorizationSession.clear();
    const organizations = [
      {'id': 'shipper-a', 'displayName': 'Shipper A', 'kind': 'CUSTOMER'},
      {'id': 'platform', 'displayName': 'Internal', 'kind': 'PLATFORM'},
    ];
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      final selected = request.headers['x-organization-id'];
      return jsonResponse({
        'user': {'id': 'dual', 'phone': '8000000008'},
        'organizations': organizations,
        if (selected != null)
          'principal': {
            'organizationId': selected,
            'roles': [selected == 'shipper-a' ? 'SHIPPER' : 'FINANCE'],
            'permissions': selected == 'shipper-a'
                ? ['load.read', 'load.create']
                : ['payment.capture'],
          },
      });
    });
    await tester.pumpWidget(const DriverPilotApp());
    await tester.pumpAndSettle();
    expect(
        find.text('Choose an organization above to continue.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipper A').last);
    await tester.pumpAndSettle();
    expect(find.text('Book freight'), findsOneWidget);
    await tester.tap(find.text('Shipper A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal').last);
    await tester.pumpAndSettle();
    expect(find.text('Internal workspace'), findsOneWidget);
    expect(find.text('Book freight'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
