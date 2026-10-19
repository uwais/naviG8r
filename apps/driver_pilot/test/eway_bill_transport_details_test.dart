// The transport details in the shipper's e-way bill step: what is shown before and after the
// carrier accepts, that the rows stay until the truck is on the bill, what Copy all puts on the
// clipboard, and that the words name billing software as well as the e-way bill site.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_transport_details.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';
import 'support/shipper_screen_checks.dart';

List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

Map<String, dynamic> carriedBy(Map<String, dynamic> shipment,
        [Map<String, dynamic> extra = const {}]) =>
    {...shipment, 'carrierDisplayName': 'Ravi Roadways', ...extra};

const softwareOrSite = 'your billing software or on the e-way bill site';

void main() {
  setUp(signInAsShipper);

  testWidgets(
      'before acceptance: the transporter name is ready, the ID and truck wait for the carrier',
      (tester) async {
    var requests = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      requests++;
      return jsonResponse({});
    });
    final copied = watchClipboard(tester);
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(status: 'PENDING_CARRIER_ACCEPT'))));
    expect(find.text('Transporter name'), findsOneWidget);
    expect(find.text('Ravi Roadways'), findsOneWidget,
        reason: "the carrier's name is known at booking");
    expect(find.text("Carrier's transporter ID"), findsOneWidget);
    expect(find.text('Truck number'), findsOneWidget);
    expect(find.text('After Ravi Roadways accepts'), findsNWidgets(2),
        reason: 'the server sends the ID and truck only once accepted');
    expect(requests, 0, reason: 'nothing is asked of the server early');
    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(copied, ['Transporter name: Ravi Roadways\nMode: Road'],
        reason: 'only the details known so far');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'a bill saved without the truck keeps every row, the transporter ID included',
      (tester) async {
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(bill: savedBill),
                {'carrierTransporterId': '29ABCDE1234F1Z5'})));
    expect(find.text('Bill 1234 5678 9012 saved. The truck is not on it yet.'),
        findsOneWidget);
    expect(find.text('Ravi Roadways'), findsOneWidget,
        reason: 'the transporter name stays');
    expect(find.text('29ABCDE1234F1Z5'), findsOneWidget,
        reason:
            'the transporter ID no longer disappears once the bill is saved');
    expect(find.text('Not chosen yet'), findsOneWidget,
        reason: 'the truck row stays, waiting for the carrier');
    expect(find.text('Copy all'), findsOneWidget);
  });

  testWidgets(
      'a bill saved without the truck shows the trip truck where Part B is updated',
      (tester) async {
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(bill: savedBill),
                {'assignedTruckNumber': 'KA01AB1234'})));
    expect(find.text('KA01AB1234'), findsOneWidget);
    expect(find.text('Portal: Update Part B, Vehicle No.'), findsOneWidget);
    expect(find.text('Ravi Roadways has not added one.'), findsOneWidget,
        reason: 'no transporter ID: the row says so instead of vanishing');
  });

  testWidgets(
      'once the truck is on the bill the rows give way to the saved bill',
      (tester) async {
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(bill: withTruck(savedBill)), {
          'assignedTruckNumber': 'KA01AB1234',
          'carrierTransporterId': '29ABCDE1234F1Z5',
        })));
    expect(find.text('Transporter name'), findsNothing);
    expect(find.text('Copy all'), findsNothing);
  });

  testWidgets(
      'Copy all puts one labelled block on the clipboard and announces it',
      (tester) async {
    final copied = watchClipboard(tester);
    final announced = watchAnnouncements(tester);
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(), {
          'assignedTruckNumber': 'KA 01 AB 1234',
          'carrierTransporterId': '29ABCDE1234F1Z5',
        })));
    await tester.tap(find.text('Copy all'));
    await tester.pump();
    expect(copied, [
      'Transporter name: Ravi Roadways\n'
          'Transporter ID: 29ABCDE1234F1Z5\n'
          'Mode: Road\n'
          'Vehicle number: KA01AB1234'
    ]);
    expect(announced, contains('Transport details copied.'),
        reason: 'accessibility.md: a copy is announced, like each row');
    expect(find.text('Copied'), findsOneWidget,
        reason: 'the button says it worked');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy all'), findsOneWidget,
        reason: 'and returns to Copy all after three seconds');
  });

  testWidgets(
      'the words name billing software and the e-way bill site, and the portal button stays',
      (tester) async {
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment()), portalButtonInPanel: true));
    expect(
        find.text(
            'Make the bill in your billing software or on the e-way bill site. Copy these in:'),
        findsOneWidget);
    expect(
        find.text(
            'NaviG8r never makes or changes an e-way bill. You make it in $softwareOrSite.'),
        findsOneWidget,
        reason: 'the footnote no longer says the portal is the only place');
    expect(find.text('Open the e-way bill portal'), findsOneWidget,
        reason: 'the site is still one way to make it');
    expect(find.textContaining('You make it on the portal'), findsNothing);
  });

  testWidgets('adding the truck says it can be added in billing software too',
      (tester) async {
    signInAsShipper(permissions: ['eway_bill.write', 'eway_bill.add_truck']);
    await mountCard(
        tester, EwayBillCard(shipment: carriedBy(shipment(bill: savedBill))));
    expect(
        find.text(
            'Add the truck in $softwareOrSite before the goods move, then enter it here.'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add truck'));
    await tester.pump();
    expect(
        find.text(
            'Add the truck to the bill in $softwareOrSite first, then copy the truck number and the valid-until time from it.'),
        findsOneWidget);
  });

  testWidgets('the rows fit 360 dp wide at 200% text', (tester) async {
    useDoubleTextSize(tester);
    tester.view.physicalSize = const Size(360, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: ListView(children: [
          EwayBillCard(
              shipment: carriedBy(shipment(), {
            'assignedTruckNumber': 'KA01AB1234',
            'carrierTransporterId': '29ABCDE1234F1Z5',
          })),
        ]))));
    expect(tester.takeException(), isNull, reason: 'no overflow');
    expect(tester.getSize(find.text('Copy all')).width, lessThanOrEqualTo(360));
    final copyAll = find.ancestor(
        of: find.text('Copy all'), matching: find.byType(OutlinedButton));
    expect(tester.getSize(copyAll).height, greaterThanOrEqualTo(48),
        reason: '48 dp target');
  });

  testWidgets('a screen reader hears what Copy all copies', (tester) async {
    final semantics = tester.ensureSemantics();
    final copied = watchClipboard(tester);
    await mountCard(
        tester,
        EwayBillCard(
            shipment: carriedBy(shipment(status: 'PENDING_CARRIER_ACCEPT'))));
    final copyAll = find.bySemanticsLabel('Copy all transport details');
    expect(copyAll, findsOneWidget);
    expect(tester.getSemantics(copyAll).hasFlag(SemanticsFlag.isButton), isTrue,
        reason: 'it is still announced as a button');
    await tester.tap(copyAll);
    await tester.pump();
    expect(copied, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    semantics.dispose();
  });

  testWidgets('Copy all is hidden when no detail is known yet', (tester) async {
    await mountCard(
        tester,
        const EwayBillTransportDetails(
            carrierName: null, carrierAccepted: false));
    expect(find.text('Transporter name'), findsOneWidget);
    expect(find.text('Copy all'), findsNothing,
        reason: 'it would copy only "Mode: Road"');
  });
}
