import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipment_payment_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'shipper'};
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['pod.accept']
    };
    AuthorizationSession.organizations = [
      {'id': 'shipper-a', 'displayName': 'Shipper A'}
    ];
    api.selectOrganization('shipper-a');
  });

  Map<String, dynamic> shipment(
          {String org = 'shipper-a', bool accepted = false}) =>
      {
        'id': 'shipment-a',
        'customerOrgId': org,
        'status': 'PENDING_RELEASE',
        'podAtUtcMs': 1000,
        'podAcceptedAtUtcMs': accepted ? 2000 : null,
        'paymentReady': accepted,
        'paymentHoldUntilUtcMs': 172801000,
      };

  testWidgets(
      'accepting delivery requires confirmation and refreshes server state',
      (tester) async {
    var requests = 0;
    var accepted = false;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      expect(request.path, '/shipments/shipment-a/accept-pod');
      expect(request.method, 'POST');
      expect(request.headers['x-organization-id'], 'shipper-a');
      requests++;
      return jsonResponse({'shipment': shipment(accepted: true)});
    });
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => ShipmentPaymentStatus(
                      shipment: shipment(accepted: accepted),
                      onAccepted: () async {
                        setState(() => accepted = true);
                      },
                    )))));
    expect(find.textContaining('Payment on hold'), findsOneWidget);
    await tester.tap(find.text('Accept delivery'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.tap(find.text('Accept delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Accept delivery').last);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Delivery accepted'), findsOneWidget);
    expect(find.text('Accept delivery'), findsNothing);
  });

  testWidgets('hides acceptance for another organization or missing permission',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ShipmentPaymentStatus(shipment: shipment(org: 'shipper-b'))));
    expect(find.text('Accept delivery'), findsNothing);
    AuthorizationSession.principal!['permissions'] = [];
    await tester.pumpWidget(
        MaterialApp(home: ShipmentPaymentStatus(shipment: shipment())));
    expect(find.text('Accept delivery'), findsNothing);
  });

  testWidgets('driver cannot render payout form through a direct screen',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['load.read']
    };
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DriverPayoutSetupScreen())));
    expect(find.textContaining('Only an authorized carrier owner'),
        findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('mobile selector replaces old screen with internal workspace',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AuthorizationSession.organizations
        .add({'id': 'platform', 'displayName': 'Internal', 'kind': 'PLATFORM'});
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'user': AuthorizationSession.user,
          'organizations': AuthorizationSession.organizations,
          'principal': {
            'organizationId': 'platform',
            'roles': ['FINANCE'],
            'permissions': ['payment.capture']
          },
        }));
    await tester.pumpWidget(const MaterialApp(
        home: OrganizationAccess(
            child: Column(children: [
      OrganizationToolbar(),
      Text('Private shipment A')
    ]))));
    expect(find.text('Private shipment A'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Internal').last);
    await tester.pumpAndSettle();
    expect(find.text('Private shipment A'), findsNothing);
    expect(find.text('Internal workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
