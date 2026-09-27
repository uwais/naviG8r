import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  // Nested under /driver like driverFlowRoutes(), so Home is always underneath.
  Future<GoRouter> showShell(WidgetTester tester, String at) async {
    AuthorizationSession.clear();
    Widget page(String path) => Text('Page $path');
    final router = GoRouter(initialLocation: at, routes: [
      ShellRoute(
        builder: (_, state, child) => DriverShell(
            title: 'Test', currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/driver',
            builder: (_, __) => page('/driver'),
            routes: [
              for (final path in [
                'loads',
                'profile',
                'payout-setup',
                'trip/t1/active'
              ])
                GoRoute(path: path, builder: (_, __) => page('/driver/$path')),
            ],
          ),
        ],
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  final backArrow = find.byIcon(Icons.arrow_back);

  testWidgets('tab roots have no back arrow', (tester) async {
    for (final at in ['/driver', '/driver/loads', '/driver/profile']) {
      await showShell(tester, at);
      expect(find.text('Page $at'), findsOneWidget, reason: at);
      expect(backArrow, findsNothing, reason: at);
    }
  });

  testWidgets(
      'a page opened on top of a tab has a back arrow that returns to it',
      (tester) async {
    final router = await showShell(tester, '/driver/loads');
    router.push('/driver/payout-setup');
    await tester.pumpAndSettle();
    expect(find.text('Page /driver/payout-setup'), findsOneWidget);
    expect(backArrow, findsOneWidget);

    await tester.tap(backArrow);
    await tester.pumpAndSettle();
    expect(find.text('Page /driver/loads'), findsOneWidget);
    expect(backArrow, findsNothing);
  });

  testWidgets('a page opened directly backs out to Home', (tester) async {
    await showShell(tester, '/driver/payout-setup');
    expect(backArrow, findsOneWidget);

    await tester.tap(backArrow);
    await tester.pumpAndSettle();
    expect(find.text('Page /driver'), findsOneWidget);
  });

  testWidgets('the live trip page has no back arrow', (tester) async {
    final router = await showShell(tester, '/driver/loads');
    router.push('/driver/trip/t1/active');
    await tester.pumpAndSettle();
    expect(find.text('Page /driver/trip/t1/active'), findsOneWidget);
    expect(backArrow, findsNothing);
  });
}
