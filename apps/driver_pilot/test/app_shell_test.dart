// PR 3 of the redesign: the signed-out sign-in, one header with the account menu, and tabs by role
// (spec/screens.md, Navigation). Names and companies are the mockups' synthetic ones.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/shipper_scaffold.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/sign_in_screen.dart';
import 'package:driver_pilot/ui/nv_account_sheet.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

const sharma = {
  'id': 'org-sharma',
  'displayName': 'Sharma Textiles',
  'kind': 'CUSTOMER'
};
const ravi = {
  'id': 'org-ravi',
  'displayName': 'Ravi Roadways',
  'kind': 'CARRIER_FLEET',
  'kycStatus': 'APPROVED'
};

Map<String, dynamic> principalAt(String organizationId, String subrole) => {
      'organizationId': organizationId,
      'roles': [organizationId == 'org-sharma' ? 'SHIPPER' : 'CARRIER'],
      'subrole': subrole,
      'permissions': ['load.read', 'load.create'],
    };

/// Bounded pumps: the app's session listener keeps scheduling frames while it refreshes.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Launches the whole app as [person] at the company [startAt], with [subroleAt] giving their
/// role in each company. Counts the access reloads.
Future<List<int>> launchSignedIn(WidgetTester tester,
    {required String person,
    required String startAt,
    required Map<String, String> subroleAt}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  AuthorizationSession.clear();
  final accessReloads = [0];
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    if (request.uri.path != '/v1/auth/me') return jsonResponse({});
    accessReloads[0]++;
    final selected = request.headers['x-organization-id'] as String?;
    return jsonResponse({
      'user': {'id': 'person-1', 'fullName': person, 'phone': '9845012345'},
      'organizations': [
        if (subroleAt.containsKey('org-sharma')) sharma,
        if (subroleAt.containsKey('org-ravi')) ravi,
      ],
      if (selected != null)
        'principal': principalAt(selected, subroleAt[selected]!),
    });
  });
  api.selectOrganization(startAt);
  await tester.pumpWidget(const DriverPilotApp());
  await pumpFrames(tester);
  return accessReloads;
}

List<String> tabLabels(WidgetTester tester) => tester
    .widget<NavigationBar>(find.byType(NavigationBar))
    .destinations
    .map((destination) => (destination as NavigationDestination).label)
    .toList();

Finder inHeader(Finder finder) =>
    find.descendant(of: find.byType(NvHeader), matching: finder);

Finder inAccountSheet(Finder finder) =>
    find.descendant(of: find.byType(NvAccountSheet), matching: finder);

void main() {
  group('Signed out', () {
    Future<void> launchSignedOut(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      FlutterSecureStorage.setMockInitialValues({});
      api = Api('http://test');
      api.dio.httpClientAdapter = MockApiAdapter(
          (request) => jsonResponse({'error': 'unauthorized'}, 401));
      AuthorizationSession.clear();
      await tester.pumpWidget(const DriverPilotApp());
      await pumpFrames(tester);
    }

    testWidgets('a signed-out start shows the phone field straight away',
        (tester) async {
      await launchSignedOut(tester);
      expect(find.text('Mobile number'), findsOneWidget,
          reason: 'the first screen is the phone sign-in');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'one phone field, ready to type in');
      expect(find.text('Send code'), findsOneWidget);
      expect(find.text('How do you use NaviG8r?'), findsNothing,
          reason: 'no choice screen before signing in');
      expect(find.textContaining('goods'), findsNothing,
          reason: 'no ship or carry choice; the account decides');
      expect(tester.takeException(), isNull,
          reason: 'the sign-in fits 360 dp');
    });

    testWidgets('signed out shows no tabs and no account header',
        (tester) async {
      await launchSignedOut(tester);
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'screens.md: signed out has no tabs');
      expect(find.byType(NvHeader), findsNothing,
          reason:
              'cp-header: signed out there is no header, only the sign-in');
    });

    for (final (organization, subrole, tabs) in [
      (sharma, 'CUSTOMER_ADMIN', ['Home', 'Book a trip', 'Shipments']),
      (ravi, 'OWNER', ['Home', 'Bookings', 'Trips', 'Add trip', 'Profile']),
    ]) {
      testWidgets('the one sign-in lands a $subrole on their own Home',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        FlutterSecureStorage.setMockInitialValues({});
        api = Api('http://test');
        var verified = false;
        api.dio.httpClientAdapter = MockApiAdapter((request) {
          final path = request.uri.path;
          if (path == '/v1/auth/otp/start') {
            return jsonResponse({'challengeId': 'challenge-1'});
          }
          if (path == '/v1/auth/otp/verify') {
            verified = true;
            return jsonResponse({'accessToken': 'synthetic'});
          }
          if (path != '/v1/auth/me') return jsonResponse({});
          if (!verified) return jsonResponse({'error': 'unauthorized'}, 401);
          return jsonResponse({
            'user': {'id': 'person-1', 'fullName': 'Meena Rao'},
            'organizations': [organization],
            'principal': principalAt(organization['id']!, subrole),
          });
        });
        AuthorizationSession.clear();
        await tester.pumpWidget(const DriverPilotApp());
        await pumpFrames(tester);
        await tester.enterText(find.byType(TextField), '9845012345');
        await tester.tap(find.text('Send code'));
        await pumpFrames(tester);
        await tester.enterText(find.byType(TextField), '123456');
        await tester.tap(find.text('Sign in'));
        await pumpFrames(tester);
        expect(tabLabels(tester), tabs,
            reason: 'the account, not a choice, decides where sign-in lands');
      });
    }
  });

  testWidgets('the sign-in and the office shell fit 360 dp at 200% text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await launchSignedIn(tester,
        person: 'Lakshmi Venkataraman',
        startAt: 'org-ravi',
        subroleAt: {'org-ravi': 'OWNER'});
    expect(tester.takeException(), isNull,
        reason:
            'decisions.md 8: the header, title and five tabs fit at 200% text');
    await tester
        .pumpWidget(const MaterialApp(home: SignInScreen()));
    // The sign-in reloads access when it opens; let that finish before the test ends.
    await pumpFrames(tester);
    expect(tester.takeException(), isNull,
        reason: 'decisions.md 8: the sign-in fits at 200% text');
  });

  group('Header', () {
    testWidgets('shows the company and "Person · Role" for a shipper',
        (tester) async {
      await launchSignedIn(tester,
          person: 'Priya Raman',
          startAt: 'org-sharma',
          subroleAt: {'org-sharma': 'CUSTOMER_ADMIN'});
      expect(inHeader(find.text('Sharma Textiles')), findsOneWidget,
          reason: 'copy.md: the company is the header title');
      expect(inHeader(find.text('Priya Raman · Shipper')), findsOneWidget,
          reason: 'copy.md: person and role, Shipper for every shipper login');
    });

    for (final (subrole, word) in [
      ('OWNER', 'Owner'),
      ('DISPATCHER', 'Dispatcher'),
      ('DRIVER', 'Driver'),
    ]) {
      testWidgets('shows the company and "Person · $word" for a $word',
          (tester) async {
        await launchSignedIn(tester,
            person: 'Meena Rao',
            startAt: 'org-ravi',
            subroleAt: {'org-ravi': subrole});
        expect(inHeader(find.text('Ravi Roadways')), findsOneWidget,
            reason: 'copy.md: the company is the header title');
        expect(inHeader(find.text('Meena Rao · $word')), findsOneWidget,
            reason: 'copy.md: the role words are Owner, Dispatcher, Driver');
      });
    }

    testWidgets(
        'has no drop-down, refresh, sign-out or avatar; the menu lists companies and Sign out',
        (tester) async {
      await launchSignedIn(tester,
          person: 'Meena Rao',
          startAt: 'org-ravi',
          subroleAt: {
            'org-ravi': 'DISPATCHER',
            'org-sharma': 'CUSTOMER_MEMBER'
          });
      expect(find.byType(DropdownButton<String>), findsNothing,
          reason: 'screens.md: the header replaces the company drop-down');
      expect(find.byTooltip('Refresh'), findsNothing,
          reason: 'screens.md: pull to refresh replaces the refresh icon');
      expect(find.byIcon(Icons.logout), findsNothing,
          reason: 'screens.md: no sign-out icon in the header');
      expect(find.byType(CircleAvatar), findsNothing,
          reason: 'screens.md: the round avatar is gone');

      await tester.tap(inHeader(find.text('Ravi Roadways')));
      await tester.pumpAndSettle();
      expect(inAccountSheet(find.text('Meena Rao')), findsOneWidget,
          reason: 'copy.md: the menu names the person');
      expect(inAccountSheet(find.text('+91 98450 12345')), findsOneWidget,
          reason: 'copy.md: the menu shows the full phone');
      expect(inAccountSheet(find.text('Ravi Roadways')), findsOneWidget,
          reason: 'c-menu: every company is listed');
      expect(inAccountSheet(find.text('Carrier · Dispatcher')), findsOneWidget,
          reason: 'c-menu: the chosen company names the side and role');
      expect(inAccountSheet(find.text('Sharma Textiles')), findsOneWidget,
          reason: 'c-menu: every company is listed');
      expect(inAccountSheet(find.text('Sign out')), findsOneWidget,
          reason: 'copy.md: the menu is the one place to sign out');
      expect(inAccountSheet(find.text('Add a company')), findsNothing,
          reason:
              'no flow adds a company while signed in, so the row is left out');
    });

    testWidgets('choosing another company in the menu switches to it',
        (tester) async {
      await launchSignedIn(tester,
          person: 'Priya Raman',
          startAt: 'org-ravi',
          subroleAt: {
            'org-ravi': 'DISPATCHER',
            'org-sharma': 'CUSTOMER_ADMIN'
          });
      await tester.tap(inHeader(find.text('Ravi Roadways')));
      await tester.pumpAndSettle();
      await tester.tap(inAccountSheet(find.text('Sharma Textiles')));
      await pumpFrames(tester);
      expect(inHeader(find.text('Sharma Textiles')), findsOneWidget,
          reason: 'the menu switches company with the existing switch');
      expect(inHeader(find.text('Priya Raman · Shipper')), findsOneWidget,
          reason: 'the role follows the chosen company');
      expect(tabLabels(tester), ['Home', 'Book a trip', 'Shipments'],
          reason: 'the tabs follow the chosen company');
    });
  });

  group('Tabs by role', () {
    testWidgets('a shipper has exactly Home, Book a trip, Shipments',
        (tester) async {
      await launchSignedIn(tester,
          person: 'Priya Raman',
          startAt: 'org-sharma',
          subroleAt: {'org-sharma': 'CUSTOMER_MEMBER'});
      expect(tabLabels(tester), ['Home', 'Book a trip', 'Shipments'],
          reason: 'screens.md: Book is reached from a lane card, not a tab');
    });

    for (final subrole in ['OWNER', 'DISPATCHER']) {
      testWidgets(
          'the office ($subrole) has exactly Home, Bookings, Trips, Add trip, Profile',
          (tester) async {
        await launchSignedIn(tester,
            person: 'Ravi Shetty',
            startAt: 'org-ravi',
            subroleAt: {'org-ravi': subrole});
        expect(tabLabels(tester),
            ['Home', 'Bookings', 'Trips', 'Add trip', 'Profile'],
            reason: 'screens.md: the office tabs are renamed, not removed');
        expect(find.text('Home'), findsWidgets,
            reason: 'the office home is titled Home');
      });
    }

    testWidgets('a driver has exactly Today, Trips, Profile', (tester) async {
      await launchSignedIn(tester,
          person: 'Prakash Naidu',
          startAt: 'org-ravi',
          subroleAt: {'org-ravi': 'DRIVER'});
      expect(tabLabels(tester), ['Today', 'Trips', 'Profile'],
          reason: 'screens.md: drivers do not publish or manage bookings');
    });

    testWidgets('Book opens from a lane link, under Book a trip, with Back to it',
        (tester) async {
      await launchSignedIn(tester,
          person: 'Priya Raman',
          startAt: 'org-sharma',
          subroleAt: {'org-sharma': 'CUSTOMER_ADMIN'});
      GoRouter.of(tester.element(find.byType(NavigationBar)))
          .go('/customer/book?anchorTripId=lane-1');
      await pumpFrames(tester);
      expect(find.text('Book this trip'), findsOneWidget,
          reason: 'PR 4: the Book route keeps working without a tab');
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'PR 4: on Book the action bar takes the tabs\' place');
      expect(inHeader(find.text('Book a trip')), findsOneWidget,
          reason:
              'screens.md: detail screens add Back, named for where it goes');
    });
  });

  // The shell on its own: the whole app's sign-out waits on push-notification platform calls
  // that never answer under flutter test.
  group('Shell on its own', () {
    Future<List<int>> showShellWith(WidgetTester tester, Widget page) async {
      FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
      api = Api('http://test');
      AuthorizationSession.clear();
      AuthorizationSession.user = {'id': 'person-1', 'fullName': 'Ravi Shetty'};
      AuthorizationSession.organizations = [ravi];
      AuthorizationSession.principal = principalAt('org-ravi', 'OWNER');
      api.selectOrganization('org-ravi');
      final accessReloads = [0];
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.uri.path == '/v1/auth/me') accessReloads[0]++;
        return jsonResponse({
          'user': AuthorizationSession.user,
          'organizations': [ravi],
          'principal': principalAt('org-ravi', 'OWNER'),
        });
      });
      final router = GoRouter(initialLocation: '/driver', routes: [
        GoRoute(path: '/', redirect: (_, __) => '/driver'),
        ShellRoute(
          builder: (_, state, child) => DriverShell(currentPath: state.uri.path, child: child),
          routes: [GoRoute(path: '/driver', builder: (_, __) => page)],
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
          MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
      await tester.pumpAndSettle();
      return accessReloads;
    }

    testWidgets('Sign out in the menu signs out and opens the sign-in',
        (tester) async {
      await showShellWith(tester, const DriverWelcomeScreen());
      await tester.tap(inHeader(find.text('Ravi Roadways')));
      await tester.pumpAndSettle();
      await tester.tap(inAccountSheet(find.text('Sign out')));
      await tester.pumpAndSettle();
      expect(AuthorizationSession.signedIn, isFalse,
          reason: 'Sign out uses the existing sign-out');
      expect(find.text('Sign in with your phone'), findsOneWidget,
          reason: 'signed out, only the sign-in shows');
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'signed out has no tabs');
      expect(find.byType(NvHeader), findsNothing,
          reason: 'signed out has no account header');
    });

    testWidgets('pulling down reloads access, as the refresh icon did',
        (tester) async {
      final accessReloads = await showShellWith(
          tester,
          ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [Text('Body')]));
      await tester.fling(find.text('Body'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(accessReloads[0], 1,
          reason: 'screens.md: pull to refresh replaces the refresh icon');
    });

    testWidgets('a screen with its own pull keeps it, and only it runs',
        (tester) async {
      var screenReloads = 0;
      final accessReloads = await showShellWith(
          tester,
          RefreshIndicator(
              onRefresh: () async => screenReloads++,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [Text('Body')])));
      await tester.fling(find.text('Body'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(screenReloads, 1, reason: 'the screen\'s own reload still runs');
      expect(accessReloads[0], 0,
          reason: 'two spinners for one pull would be confusing');
    });
  });

  testWidgets('a shipper detail screen has Back to its tab', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'person-1', 'fullName': 'Priya Raman'};
    AuthorizationSession.organizations = [sharma];
    AuthorizationSession.principal =
        principalAt('org-sharma', 'CUSTOMER_ADMIN');
    api.selectOrganization('org-sharma');
    final router = GoRouter(initialLocation: '/customer/shipments/s1', routes: [
      GoRoute(
          path: '/customer/shipments',
          builder: (_, __) => CustomerScaffold(
              title: 'My shipments',
              currentPath: '/customer/shipments',
              bodyBuilder: (_) => const Text('List'))),
      GoRoute(
          path: '/customer/shipments/:id',
          builder: (_, __) => CustomerScaffold(
              title: 'Shipment',
              currentPath: '/customer/shipments/s1',
              bodyBuilder: (_) => const Text('Detail'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(inHeader(find.text('Shipments')));
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget,
        reason: 'screens.md: Back on a detail screen returns to its tab');
    expect(inHeader(find.text('Shipments')), findsNothing,
        reason: 'a tab screen has no Back');
  });
}
