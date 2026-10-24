// Owner, 23 Oct 2026: once the trip is on the way the server refuses to remove an e-way bill, so the
// shipper's card no longer offers Remove e-way bill. Editing the bill stays.
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';

void main() {
  setUp(signInAsShipper);

  testWidgets('a bill on a trip on the way: Edit stays, Remove goes',
      (tester) async {
    await mountCard(tester,
        EwayBillCard(shipment: shipment(bill: savedBill), tripStarted: true));
    expect(find.text('Edit the bill'), findsOneWidget);
    expect(find.text('Remove e-way bill'), findsNothing);
  });

  testWidgets('a no-bill statement on a trip on the way: Change stays, Remove goes',
      (tester) async {
    await mountCard(
        tester,
        EwayBillCard(
            shipment: shipment(bill: {
              'kind': 'NOT_NEEDED',
              'notNeededReason': 'BELOW_THRESHOLD',
              'enteredAtUtcMs': 1760000000000,
            }),
            tripStarted: true));
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('Remove e-way bill'), findsNothing);
  });

  testWidgets('before the start Remove e-way bill is still offered',
      (tester) async {
    await mountCard(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    expect(find.text('Remove e-way bill'), findsOneWidget);
  });
}
