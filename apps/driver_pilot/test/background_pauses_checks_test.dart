// A phone in a pocket sends no timed checks: the screens' 15 s checks skip their turn while the
// app is in the background, and each checks once when it is shown again.
import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/app_lifecycle.dart';
import 'support/carrier_app.dart' show NoLocationService;
import 'support/carrier_fixtures.dart';
import 'support/carrier_office_bookings.dart';
import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

/// Sends the screen to the background for three turns of its check, then brings it back, and
/// returns how many [path] requests went out while away and on the way back.
Future<(int, int)> _requestsAwayAndBack(
    WidgetTester tester, List<RequestOptions> requests, String path) async {
  int count() => requests.where((request) => request.uri.path == path).length;
  final before = count();
  await sendAppToBackground(tester);
  await tester.pump(const Duration(seconds: 46));
  final away = count() - before;
  await bringAppBack(tester);
  await tester.pump(const Duration(milliseconds: 100));
  return (away, count() - before - away);
}

Future<void> _mountCarrierScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

/// Answers as [answer] does, and keeps every request.
List<RequestOptions> _keepRequests(
    {required List<Map<String, dynamic>> bookings,
    required List<Map<String, dynamic>> trips}) {
  answer(bookings: bookings, trips: trips);
  final answering = api.dio.httpClientAdapter as MockApiAdapter;
  final requests = <RequestOptions>[];
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    requests.add(request);
    return answering.handle(request);
  });
  return requests;
}

void main() {
  tearDown(DriverSession.clearCarrierCache);

  testWidgets('the shipper shipment screen', (tester) async {
    final server = await showShipment(tester, booking());
    final (away, back) = await _requestsAwayAndBack(
        tester, server.requests, '/shipments/shp_9f2c41');
    expect(away, 0, reason: 'no check while in the background');
    expect(back, 1, reason: 'one check on return');
    await leave(tester);
  });

  testWidgets('the carrier booking screen', (tester) async {
    signInAsOwner();
    final requests = _keepRequests(
        bookings: [
          {...shipmentOnTripA(), 'id': 'shipment-a'}
        ], trips: [trip()]);
    await _mountCarrierScreen(
        tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
    final (away, back) = await _requestsAwayAndBack(
        tester, requests, '/v1/pilot/carrier/shipments');
    expect(away, 0, reason: 'no check while in the background');
    expect(back, 1, reason: 'one check on return');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the carrier trip screen', (tester) async {
    GeolocatorPlatform.instance = NoLocationService();
    signInAsOwner();
    final requests = _keepRequests(
        bookings: [
          {...shipmentOnTripA(), 'id': 'shipment-a'}
        ], trips: [trip()]);
    await _mountCarrierScreen(
        tester, const DriverActiveTripScreen(tripId: 'trip-a'));
    final (away, back) = await _requestsAwayAndBack(
        tester, requests, '/v1/pilot/carrier/shipments');
    expect(away, 0, reason: 'no check while in the background');
    expect(back, 1, reason: 'one check on return');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
