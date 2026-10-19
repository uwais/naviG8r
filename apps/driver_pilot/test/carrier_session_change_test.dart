// What a carrier's screens do when the session changes under them: signing out of the owner's Trips (owner run,
// 18 Oct 2026: a blank screen until the app was restarted) and a driver signing in at the start screen.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

/// Bounded pumps: the app's session listener keeps scheduling frames while it refreshes.
Future<void> pumpFrames(WidgetTester tester, [int count = 40]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  test('a signed-out carrier screen opens the carrier start, not the shipper sign-in', () {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    AuthorizationSession.clear();
    for (final path in [
      '/driver/loads',
      '/driver/publish',
      '/driver/trip/t/active'
    ]) {
      expect(mobileAccessRedirect(path), '/driver',
          reason:
              '/driver shows the sign-in inside the carrier shell, so the shell is never swapped out ($path)');
    }
    expect(mobileAccessRedirect('/customer/shipments'), '/customer/login',
        reason: 'the shipper side is unchanged');
  });

  // The sign-out itself waits on push-notification platform calls that never answer under flutter test, so the
  // session is changed directly, as signOut() does once the token is gone.
  testWidgets(
      "signing out of the owner's Trips right after a publish stays in the carrier shell, which is never in the tree twice",
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    AuthorizationSession.clear();
    final server = CarrierServer(
        allowed: ownerAllowed, subrole: 'OWNER', trips: [carrierTrip('trip-a')]);
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path != '/v1/auth/me') return server.answer(request);
      if (request.headers['authorization'] == null) {
        return jsonResponse({'error': 'unauthorized'}, 401);
      }
      return jsonResponse({
        'user': {
          'id': 'owner-1',
          'fullName': 'Synthetic Owner A',
          'phone': '8000000003'
        },
        'organizations': [carrierOrganization],
        if (request.headers['x-organization-id'] != null)
          'principal': server.principal,
      });
    });
    api.selectOrganization('carrier-a');
    await tester.pumpWidget(const DriverPilotApp());
    await pumpFrames(tester);
    final router = GoRouter.of(tester.element(find.byType(DriverShell)));
    router.go('/driver/loads');
    await pumpFrames(tester);
    ScaffoldMessenger.of(tester.element(find.byType(DriverLoadsScreen)))
        .showSnackBar(tripPublishedMessage());
    final visited = <String>[];
    void record() =>
        visited.add(router.routerDelegate.currentConfiguration.uri.path);
    router.routerDelegate.addListener(record);
    addTearDown(() => router.routerDelegate.removeListener(record));

    // Signed out while Trips is still on screen. The sign-in screens then refresh access with the token that
    // is still stored, so the session flips back while the pages are still moving: the race that, with the
    // shipper sign-in in between, put the carrier shell in the tree twice.
    AuthorizationSession.clear();
    await pumpFrames(tester, 8);
    router.go('/');
    await pumpFrames(tester, 100);

    expect(tester.takeException(), isNull,
        reason: 'before: "Multiple widgets used the same GlobalKey", which a phone build does not check');
    expect(visited, isNot(contains('/customer/login')),
        reason: 'the carrier shell is never swapped for the shipper sign-in and back');
    expect(find.byType(DriverShell), findsOneWidget);
  });

  testWidgets("a driver who signs in at the start screen is headed Today, as the tab says",
      (tester) async {
    signInToCarrierApp(CarrierServer(allowed: driverAllowed, subrole: 'DRIVER'));
    final driver = AuthorizationSession.user;
    final principal = AuthorizationSession.principal;
    AuthorizationSession.clear();
    await mountCarrierApp(tester, '/driver');
    expect(find.text('Sign in with your phone'), findsOneWidget);

    AuthorizationSession.user = driver;
    AuthorizationSession.principal = principal;
    AuthorizationSession.organizations = [carrierOrganization];
    AuthorizationSession.revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsNothing,
        reason: 'owner run: the heading said Home while the tab said Today (dr-today)');
    expect(find.text('Today'), findsNWidgets(2),
        reason: 'the heading and the tab');
  });
}
