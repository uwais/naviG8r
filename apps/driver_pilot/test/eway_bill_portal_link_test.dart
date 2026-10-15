import 'package:driver_pilot/eway_bill_portal_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tests run without --dart-define, so the build opens the government address; the practice branch is
  // checked through the pure functions the build-time getters call.
  const practiceAddress = 'http://127.0.0.1:3139/demo/eway-portal';

  test('only the government address is called the government portal', () {
    expect(ewayBillPortalAddress, governmentPortalAddress);
    expect(ewayBillPortalName, 'government portal');
    expect(portalNameFor(governmentPortalAddress), 'government portal');
    expect(portalNameFor(practiceAddress), 'practice portal');
    expect(portalButtonLabelFor(governmentPortalAddress),
        'Open the government e-way bill portal');
    expect(portalButtonLabelFor(practiceAddress),
        'Open the practice e-way bill portal');
  });

  test('the could-not-open sentence names the address the build opens', () {
    expect(portalOpenFailedSentenceFor(governmentPortalAddress),
        'Could not open the portal from here. Its address is ewaybillgst.gov.in.');
    expect(portalOpenFailedSentenceFor(practiceAddress),
        'Could not open the portal from here. Its address is 127.0.0.1:3139.',
        reason: 'the port is part of the practice address');
  });
}
