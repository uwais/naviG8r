import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Testers saw two sign-out icons at the top right of the shipper's screens: the app bar's own and the
// organization bar's just below it.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.user = {
      'id': 'shipper',
      'fullName': 'Synthetic Shipper A',
      'phone': '8000000001'
    };
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': <String>[]
    };
    AuthorizationSession.organizations = [
      {'id': 'shipper-a', 'displayName': 'Synthetic Shipper A'}
    ];
    api.selectOrganization('shipper-a');
  });

  testWidgets("a signed-in shipper's top bar has one sign-out",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CustomerScaffold(
            title: 'My shipments',
            currentPath: '/customer/shipments',
            bodyBuilder: (_) => const Text('Body'))));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.byTooltip('Sign out of all organizations'), findsNothing);
    // The organization bar itself is still there, picker and refresh included.
    expect(find.byTooltip('Refresh access'), findsOneWidget);
  });

  testWidgets('the organization bar keeps its sign-out unless told not to',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrganizationToolbar())));
    expect(find.byTooltip('Sign out of all organizations'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: OrganizationToolbar(showSignOut: false))));
    expect(find.byIcon(Icons.logout), findsNothing);
    expect(find.byTooltip('Refresh access'), findsOneWidget);
  });
}
