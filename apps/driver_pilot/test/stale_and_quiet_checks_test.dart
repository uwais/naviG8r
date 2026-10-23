// The screens' 15 s checks run quietly and never undo a newer answer: a check that answers after
// the driver has confirmed delivery must not bring Confirm delivery back, and the Refresh button
// neither spins nor locks while a timed check runs.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_refresh_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

/// Answers from [answer], except that the next request to [heldPath], once [holdNext] is set, is
/// answered only when its completer is completed. The answer is made when the request arrives, so
/// it holds the server as it was then.
class _HoldingServer {
  _HoldingServer(this.heldPath, this.answer) {
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      requests.add(request);
      final response = answer(request);
      if (!holdNext || request.uri.path != heldPath) return response;
      holdNext = false;
      final release = Completer<void>();
      held.add(release);
      await release.future;
      return response;
    });
  }

  final String heldPath;
  final ResponseBody Function(RequestOptions) answer;
  final requests = <RequestOptions>[];
  final held = <Completer<void>>[];
  bool holdNext = false;

  int countOf(String path) =>
      requests.where((request) => request.uri.path == path).length;
}

const _carrierList = '/v1/pilot/carrier/shipments';

/// Starts the screen's next timed check and holds its answer.
Future<void> _holdTheNextTimedCheck(
    WidgetTester tester, _HoldingServer server) async {
  server.holdNext = true;
  await tester.pump(const Duration(seconds: 15));
  await tester.pump(const Duration(milliseconds: 100));
  expect(server.held, hasLength(1), reason: 'the timed check is waiting');
}

bool _refreshSpins(WidgetTester tester) =>
    tester.widget<NvRefreshButton>(find.byType(NvRefreshButton).first).loading;

void main() {
  tearDown(DriverSession.clearCarrierCache);

  group('A timed check that answers after Confirm delivery', () {
    CarrierServer signInAsDriver() => signInToCarrierApp(CarrierServer(
          allowed: driverAllowed,
          subrole: 'DRIVER',
          trips: [carrierTrip('trip-moving', status: 'IN_PROGRESS')],
          bookings: [
            carrierBooking('trip-moving', 'booked',
                shipper: 'Mehta Hardware',
                drop: 'Guindy, Chennai',
                photoIds: ['photo-1'])
          ],
        ));

    Future<void> confirmOnThePodScreen(WidgetTester tester) async {
      await tester.pumpAndSettle();
      expect(find.text('Confirm the goods are handed over'), findsOneWidget);
      await tester.tap(find.text('Confirm delivery').last);
      await tester.pumpAndSettle();
    }

    testWidgets('on the booking screen, is dropped', (tester) async {
      final carrier = signInAsDriver();
      final server = _HoldingServer(_carrierList, carrier.answer);
      final router = await mountCarrierApp(tester, '/driver/shipment/booked',
          size: const Size(800, 3000));
      expect(find.text('Confirm delivery'), findsOneWidget);

      await _holdTheNextTimedCheck(tester, server);
      await tester.tap(find.text('Confirm delivery'));
      await confirmOnThePodScreen(tester);
      expect(find.text('Confirm delivery'), findsNothing,
          reason: 'the delivery is confirmed');

      server.held.single.complete();
      await tester.pumpAndSettle();
      expect(find.text('Confirm delivery'), findsNothing,
          reason: 'the older answer, from before the delivery, is dropped');
      router.go('/');
      await tester.pumpAndSettle();
    });

    testWidgets('on the trip screen, is dropped', (tester) async {
      final carrier = signInAsDriver();
      final server = _HoldingServer(_carrierList, carrier.answer);
      final router = await mountCarrierApp(
          tester, '/driver/trip/trip-moving/active',
          size: const Size(800, 3000));
      expect(find.text('I am here: confirm delivery'), findsOneWidget);

      await _holdTheNextTimedCheck(tester, server);
      await tester.tap(find.text('I am here: confirm delivery'));
      await confirmOnThePodScreen(tester);
      expect(find.text('I am here: confirm delivery'), findsNothing);

      server.held.single.complete();
      await tester.pumpAndSettle();
      expect(find.text('I am here: confirm delivery'), findsNothing,
          reason: 'the older answer, from before the delivery, is dropped');
      router.go('/');
      await tester.pumpAndSettle();
    });
  });

  testWidgets(
      'the carrier booking screen: Refresh stays as it is during a timed check',
      (tester) async {
    final carrier = signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-moving', status: 'IN_PROGRESS')],
      bookings: [
        carrierBooking('trip-moving', 'booked',
            shipper: 'Mehta Hardware', drop: 'Guindy, Chennai')
      ],
    ));
    final server = _HoldingServer(_carrierList, carrier.answer);
    final router = await mountCarrierApp(tester, '/driver/shipment/booked',
        size: const Size(800, 3000));
    await _holdTheNextTimedCheck(tester, server);
    expect(_refreshSpins(tester), isFalse);

    final before = server.countOf(_carrierList);
    await tester.tap(find.byTooltip('Refresh').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.countOf(_carrierList), before + 1,
        reason: 'Refresh still works while the timed check waits');
    server.held.single.complete();
    router.go('/');
    await tester.pumpAndSettle();
  });

  testWidgets(
      'the shipper shipment screen: Refresh stays as it is during a timed check',
      (tester) async {
    await showShipment(tester, booking());
    final answers = <String, Object>{
      '/shipments/shp_9f2c41': {'shipment': booking(), 'payment': heldPayment},
    };
    final server = _HoldingServer('/shipments/shp_9f2c41',
        (request) => jsonResponse(answers[request.uri.path] ?? {}));
    await _holdTheNextTimedCheck(tester, server);
    expect(_refreshSpins(tester), isFalse);

    final before = server.countOf('/shipments/shp_9f2c41');
    await tester.tap(find.byTooltip('Refresh').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.countOf('/shipments/shp_9f2c41'), before + 1,
        reason: 'Refresh still works while the timed check waits');
    server.held.single.complete();
    await tester.pumpAndSettle();
    await leave(tester);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the booking screen stops checking once the list answers without it',
      (tester) async {
    signInToCarrierApp(CarrierServer(
        allowed: driverAllowed, subrole: 'DRIVER', trips: [], bookings: []));
    final requests = <RequestOptions>[];
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      requests.add(request);
      return jsonResponse({'shipments': <Object>[]});
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DriverShipmentDetailScreen(shipmentId: 'gone'))));
    await tester.pumpAndSettle();
    final asked = requests.where((r) => r.uri.path == _carrierList).length;
    await tester.pump(const Duration(seconds: 46));
    expect(requests.where((r) => r.uri.path == _carrierList).length, asked,
        reason: 'asking again cannot bring the booking back');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
