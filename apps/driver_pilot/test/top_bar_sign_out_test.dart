import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/shipper_scaffold.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Testers once saw two sign-out icons at the top right of the shipper's screens. The redesign
// keeps sign-out in one place on app screens, the header's account menu.
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

  testWidgets("a signed-in shipper's top bar has no icons; sign-out is in the menu",
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CustomerScaffold(
            title: 'My shipments',
            currentPath: '/customer/shipments',
            bodyBuilder: (_) => const Text('Body'))));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsNothing,
        reason: 'spec/screens.md: the header has no sign-out icon');
    expect(find.byTooltip('Refresh access'), findsNothing,
        reason: 'spec/screens.md: pull to refresh replaces the refresh icon');
    expect(find.byType(DropdownButton<String>), findsNothing,
        reason: 'spec/screens.md: the header replaces the company drop-down');

    await tester.tap(find.text('Synthetic Shipper A').first);
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget,
        reason: 'copy.md: the account menu is the one place to sign out');
  });

  testWidgets('the access gate keeps its company picker, refresh and sign-out',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OrganizationToolbar())));
    expect(find.byTooltip('Sign out of all organizations'), findsOneWidget,
        reason: 'with no company chosen there is no header, so the gate signs out');
    expect(find.byTooltip('Refresh access'), findsOneWidget,
        reason: 'the gate still reloads access');
  });
}
