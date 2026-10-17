import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholders stay the open items from decisions.md, word for word', () {
    expect(PendingCopy.changeOrCancelContact, '[NaviG8r contact]',
        reason:
            'open item: the contact for change or cancel is not decided yet');
    expect(PendingCopy.whenEwayBillIsNeeded,
        '[One line from the team on when an e-way bill is needed.]',
        reason: 'open item: the team has not written this line yet');
    expect(PendingCopy.truckSizeGuide, '[Size guide from the team]',
        reason: 'open item: the truck size guide is not written yet');
  });
}
