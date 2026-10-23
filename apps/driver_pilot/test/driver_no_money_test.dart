// Brief 2 and spec/screens.md's hard rule: no widget on any driver route renders a price, amount, payout,
// commission or net. The fake server here sends every amount the API has, which the real server strips for a
// driver, so the screens are tested as if that stripping ever slipped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart' show podPhotos;
import 'support/eway_bill_fixtures.dart' show finalBill;

final moneyWords =
    RegExp(r'₹|paid|commission|receive|payout|\bnet\b|your payment|releases? the payment', caseSensitive: false);

/// Every amount the API knows, on a booking in each [status].
Map<String, dynamic> bookingWithAmounts(String id, String status,
        {String tripId = 'trip-moving'}) =>
    {
      ...carrierBooking(tripId, id,
          shipper: 'Shipper $id',
          drop: 'Drop $id, Chennai',
          status: status,
          bill: {
            'kind': 'BILL',
            'billNumber': '341200987654',
            'truckNumber': 'KA01AB1234',
            'validUntilUtcMs': 1760900000000,
          }),
      'grossPaise': 264000,
      'netToCarrierPaise': 237600,
      'commissionPaise': 26400,
      'paymentReady': false,
      'paymentHoldUntilUtcMs': 1760900000000,
      'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      if (status == 'PENDING_RELEASE' || status == 'DELIVERED')
        'podAtUtcMs': 1760800000000,
    };

void main() {
  testWidgets('no driver route shows money, whatever the server sends',
      (tester) async {
    final server = signInToCarrierApp(CarrierServer(
      allowed: [...driverAllowed, 'notification.read'],
      subrole: 'DRIVER',
      trips: [
        carrierTrip('trip-moving', status: 'IN_PROGRESS'),
        carrierTrip('trip-open', from: 'Hosur', startsInDays: 1),
        carrierTrip('trip-done', from: 'Mysuru', status: 'COMPLETED'),
      ],
      bookings: [
        bookingWithAmounts('pending', 'PENDING_CARRIER_ACCEPT'),
        // Confirm delivery waits for a photo; these were sent earlier, so it can be tapped.
        {...bookingWithAmounts('booked', 'BOOKED'), 'podPhotos': podPhotos(['photo-1'])},
        {
          ...bookingWithAmounts('released', 'PENDING_RELEASE'),
          'podPhotos': podPhotos(['photo-2'])
        },
        bookingWithAmounts('delivered', 'DELIVERED'),
        // A final bill, so the start sheet opens.
        {
          ...bookingWithAmounts('open-booked', 'BOOKED', tripId: 'trip-open'),
          'ewayBill': finalBill()
        },
        bookingWithAmounts('done-delivered', 'DELIVERED', tripId: 'trip-done'),
      ],
      extraAnswers: {
        '/v1/pilot/carrier/earnings': {
          'summary': {
            'pendingAccruedPaise': 237600,
            'paidPaise': 500000,
            'kycStatus': 'APPROVED'
          }
        },
        '/v1/pilot/carrier/payout-batches': {
          'payoutBatches': [
            {
              'id': 'batch-1',
              'totalNetToCarrierPaise': 237600,
              'cutoffUtcMs': 1760800000000,
              'lineIds': ['line-1']
            }
          ]
        },
      },
    ));

    void expectNoMoney(String where) {
      final texts = textsOnScreen(tester);
      expect(texts, isNotEmpty, reason: '$where rendered');
      for (final text in texts) {
        expect(moneyWords.hasMatch(text), isFalse,
            reason: 'brief 2: a driver never sees money ($where: "$text")');
      }
    }

    // Each route with a word that shows it loaded, so a blank or failed screen cannot pass for a clean one.
    // The owner-only routes send a driver back to Home.
    const routes = {
      '/driver': 'Home',
      '/driver/loads': 'Trips',
      '/driver/trip/trip-moving/active': 'NEXT STOP',
      '/driver/trip/trip-open/active': 'Start trip',
      '/driver/trip/trip-done/active': 'All stops',
      '/driver/trip/trip-moving/eway-bills': 'E-way bills',
      '/driver/shipment/pending': 'Accept booking',
      '/driver/shipment/booked': 'Confirm delivery',
      '/driver/shipment/released': 'Delivery confirmed',
      '/driver/shipment/delivered': 'Delivered',
      '/driver/shipment/booked/pod': 'Confirm the goods are handed over',
      '/driver/profile': 'Sign out',
      '/driver/publish': 'Add trip',
      '/driver/track': 'Trip',
      '/driver/fleet': 'Home',
      '/driver/earnings': 'Home',
      '/driver/payout-setup': 'Home',
      '/driver/payout-history': 'Home',
    };
    final router = await mountCarrierApp(tester, '/driver',
        size: const Size(800, 3000));
    for (final MapEntry(key: path, value: loadedWord) in routes.entries) {
      // Through a page outside the shell, so each screen starts fresh rather than keeping the last one's state.
      await openPath(tester, router, '/');
      await openPath(tester, router, path);
      expect(find.textContaining(loadedWord), findsWidgets,
          reason: '$path loaded');
      expectNoMoney(path);
    }

    // The Trips tab's other groups, the start sheet and the screen after a confirmed delivery.
    await openPath(tester, router, '/driver/loads');
    for (final group in ['On the way', 'Done']) {
      await tester.tap(find.text(group));
      await tester.pumpAndSettle();
      expectNoMoney('Trips, $group');
    }
    await openPath(tester, router, '/driver/trip/trip-open/active');
    await tester.tap(find.widgetWithText(FilledButton, 'Start trip'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expectNoMoney('the start sheet');
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    await openPath(tester, router, '/');
    await openPath(tester, router, '/driver/trip/trip-moving/active');
    await tester.tap(find.text('I am here: confirm delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
    await tester.pumpAndSettle();
    expect(server.sent.map((request) => request.path),
        contains('/shipments/booked/driver-pod'));
    expectNoMoney('the trip after confirming a delivery');

    // The bell polls every 45 seconds; unmounting stops it before the test ends.
    router.go('/');
    await tester.pumpAndSettle();
    expect(GoRouter.of(tester.element(find.text('Start page'))), router);
  });
}
