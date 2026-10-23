// A driver's booking on a trip their office asked NaviG8r to cancel: the server refuses Accept and Confirm
// delivery, and the driver did not ask and cannot withdraw, so both are off with words that ask nothing of them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';

const _officeAsked = 'Your office asked NaviG8r to cancel this trip.';

CarrierServer _driverOn(String tripStatus) => signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-a', status: tripStatus)],
      bookings: [
        carrierBooking('trip-a', 'pending',
            shipper: 'Lakshmi Foods',
            drop: 'Guindy, Chennai',
            status: 'PENDING_CARRIER_ACCEPT'),
        carrierBooking('trip-a', 'booked',
            shipper: 'Sharma Textiles', drop: 'Ambattur, Chennai'),
      ],
    ));

void main() {
  for (final (path, label) in [
    ('/driver/shipment/pending', 'Accept booking'),
    ('/driver/shipment/booked', 'Confirm delivery'),
  ]) {
    testWidgets('$label is off on a requested trip, and says the office asked',
        (tester) async {
      final server = _driverOn('CANCEL_REQUESTED');
      await mountCarrierApp(tester, path, size: const Size(800, 3000));
      final button = find.widgetWithText(FilledButton, label);
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull,
          reason: 'the server refuses it');
      expect(find.text(_officeAsked), findsOneWidget,
          reason: 'a disabled button always says why');
      expect(find.textContaining('Withdraw'), findsNothing,
          reason: 'a driver cannot withdraw the request');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(server.sent, isEmpty, reason: 'nothing is sent');
    });

    testWidgets('$label still works on an open trip', (tester) async {
      _driverOn('OPEN');
      await mountCarrierApp(tester, path, size: const Size(800, 3000));
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, label))
              .onPressed,
          isNotNull);
      expect(find.text(_officeAsked), findsNothing);
    });
  }
}
