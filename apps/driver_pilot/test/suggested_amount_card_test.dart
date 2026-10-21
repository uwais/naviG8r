// Owner hard rule, 21 Oct 2026: each side sees only its own amount, and a driver sees no pay at all.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

/// The publish screen with the rate estimate the server sent for this login.
Future<void> mountPublishScreen(
    WidgetTester tester, List<Map<String, dynamic>> samples) async {
  api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse(
      {'laneKm': 236.7, 'modelVersion': 'freight-v1', 'samples': samples}));
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(body: PublishTripScreen())));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the office sees what it would receive on the lane',
      (tester) async {
    signInAsCarrierLogin(office: true);
    await mountPublishScreen(tester, [
      {'weightKg': 100, 'netToCarrierPaise': 4500}
    ]);
    expect(
        find.text('Suggested amount to you (lane reference)'), findsOneWidget);
    expect(find.text('≈ ₹45 to your company at 100 kg'), findsOneWidget);
  });

  testWidgets('a driver sees no suggested amount card at all', (tester) async {
    signInAsCarrierLogin(office: false);
    await mountPublishScreen(tester, [
      {'weightKg': 100}
    ]);
    expect(find.textContaining('Suggested amount'), findsNothing);
    expect(find.textContaining('receive'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('the office sees no card when no sample has an amount',
      (tester) async {
    signInAsCarrierLogin(office: true);
    await mountPublishScreen(tester, [
      {'weightKg': 100}
    ]);
    expect(find.textContaining('Suggested amount'), findsNothing);
  });
}
