// Rishabh, 20 Oct 2026: when one party changes something, the other had no way to see it without
// leaving the screen; on a desktop browser a mouse cannot pull down to refresh. Each screen the
// other party changes has a Refresh button, and the carrier's booking screen checks every 15 s.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_office_bookings.dart';
import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

int _countOf(FakeServer server, String path) =>
    server.requests.where((request) => request.uri.path == path).length;

void main() {
  group('Shipper', () {
    testWidgets('the shipment screen has Refresh, and it loads the shipment again',
        (tester) async {
      final server = await showShipment(tester, booking());
      final before = _countOf(server, '/shipments/shp_9f2c41');
      expect(find.byTooltip('Refresh'), findsOneWidget,
          reason: 'a mouse cannot pull to refresh on the web');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(_countOf(server, '/shipments/shp_9f2c41'), before + 1);
      await leave(tester);
    });

    testWidgets('the Shipments list has Refresh, and it loads the list again',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/shipments');
      server.answers['/shipments'] = {
        'shipments': [booking()]
      };
      await tester.pumpAndSettle();
      final before = _countOf(server, '/shipments');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(_countOf(server, '/shipments'), before + 1);
    });
  });

  group('Carrier booking screen', () {
    late List<Map<String, dynamic>> bookings;
    late int listRequests;
    late bool serverDown;

    Future<void> mountWithCounting(WidgetTester tester) async {
      signInAsOwner();
      listRequests = 0;
      serverDown = false;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.path.startsWith('/v1/pilot/anchor-trips/')) {
          return jsonResponse({'trip': trip()});
        }
        if (request.path == '/v1/pilot/carrier/shipments') listRequests++;
        if (serverDown) return jsonResponse({'error': 'internal'}, 500);
        return jsonResponse({'shipments': bookings});
      });
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(
              body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
      await tester.pumpAndSettle();
    }

    testWidgets('Refresh loads the booking again', (tester) async {
      bookings = [pending()];
      await mountWithCounting(tester);
      final before = listRequests;
      expect(find.byTooltip('Refresh'), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(listRequests, before + 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'every 15 s it shows the shipper\'s change, keeps the last booking when a check fails, and stops once paid out',
        (tester) async {
      bookings = [pending()];
      await mountWithCounting(tester);
      expect(find.text('Waiting for you to accept'), findsOneWidget);

      bookings = [shipmentOnTripAWithTruck()];
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for you to accept'), findsNothing,
          reason: 'the change shows without a pull or a tap');

      serverDown = true;
      final beforeFailure = listRequests;
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(listRequests, beforeFailure + 1, reason: 'it did check');
      expect(find.text('BOOKING'), findsOneWidget,
          reason: 'a failed check keeps what was shown');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a background check says nothing when it fails');

      serverDown = false;
      bookings = [
        {...delivered(), 'status': 'DELIVERED'}
      ];
      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      final afterFinal = listRequests;
      await tester.pump(const Duration(seconds: 45));
      await tester.pumpAndSettle();
      expect(listRequests, afterFinal,
          reason: 'a paid-out booking does not change, so the checks stop');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

/// Accepted with a truck: no longer waiting for the office.
Map<String, dynamic> shipmentOnTripAWithTruck() =>
    {...pending(), 'status': 'BOOKED', 'assignedTruckNumber': 'KA01AB1234'};
