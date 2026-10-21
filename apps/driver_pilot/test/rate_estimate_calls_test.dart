// Each rate estimate counts against an hourly limit, so the publish screen asks only when the values change.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

void main() {
  testWidgets(
      'the estimate is asked for again only when the vehicle class changes to a different value',
      (tester) async {
    signInAsCarrierLogin(office: true);
    final vehicleClassesAsked = <String>[];
    api.dio.httpClientAdapter = MockApiAdapter((options) {
      if (options.path == '/v1/pilot/rates/estimate') {
        vehicleClassesAsked
            .add((options.data as Map)['vehicleClass'].toString());
      }
      return jsonResponse({
        'laneKm': 236.7,
        'modelVersion': 'freight-v1',
        'samples': [
          {'weightKg': 100, 'netToCarrierPaise': 4500}
        ]
      });
    });
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> openPublish() async {
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(body: PublishTripScreen())));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    final vehicleClass =
        find.widgetWithText(TextField, 'vehicleClass (SMALL|MEDIUM|LARGE)');
    Future<void> typeVehicleClass(String text) async {
      await tester.enterText(vehicleClass, text);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }

    await openPublish();
    expect(vehicleClassesAsked, ['MEDIUM']);

    await typeVehicleClass('MEDIU');
    await typeVehicleClass('MEDIUM');
    expect(vehicleClassesAsked, ['MEDIUM'], reason: 'same value as before');

    await tester.pumpWidget(const SizedBox());
    await openPublish();
    expect(vehicleClassesAsked, ['MEDIUM'], reason: 'reopening the screen');
    expect(find.text('≈ ₹45 to your company at 100 kg'), findsOneWidget,
        reason: 'the reopened screen still shows the estimate');

    await typeVehicleClass('LARGE');
    expect(vehicleClassesAsked, ['MEDIUM', 'LARGE']);
  });

  testWidgets(
      'reopening the screen while the estimate is on its way waits for that answer instead of asking again',
      (tester) async {
    signInAsCarrierLogin(office: true);
    var estimatesAsked = 0;
    final answer = Completer<ResponseBody>();
    api.dio.httpClientAdapter = MockApiAdapter((options) {
      if (options.path == '/v1/pilot/rates/estimate') estimatesAsked += 1;
      return answer.future;
    });
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> openPublish() async {
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(body: PublishTripScreen())));
      await tester.pump(const Duration(seconds: 1));
    }

    await openPublish();
    expect(estimatesAsked, 1);
    await tester.pumpWidget(const SizedBox());
    await openPublish();
    expect(estimatesAsked, 1, reason: 'same login, pins and vehicle class');

    answer.complete(jsonResponse({
      'laneKm': 236.7,
      'modelVersion': 'freight-v1',
      'samples': [
        {'weightKg': 100, 'netToCarrierPaise': 4500}
      ]
    }));
    await tester.pumpAndSettle();
    expect(find.text('≈ ₹45 to your company at 100 kg'), findsOneWidget,
        reason: 'the reopened screen shows the answer it waited for');
    expect(estimatesAsked, 1);
  });
}
