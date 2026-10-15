// Over 500 lines on purpose: both e-way bill cards share the shipment fixture, the mount helper and
// the launcher fake, and splitting by card would copy all three. The truck form has its own file.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_carrier_card.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/mock_api.dart';

class _RecordingLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final opened = <String>[];
  bool opens = true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return opens;
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'shipper'};
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write']
    };
    AuthorizationSession.organizations = [
      {'id': 'shipper-a', 'displayName': 'Shipper A'}
    ];
    api.selectOrganization('shipper-a');
  });

  Map<String, dynamic> shipment(
          {Map<String, dynamic>? bill, String status = 'BOOKED'}) =>
      {
        'id': 'shipment-a',
        'customerOrgId': 'shipper-a',
        'customerOrgName': 'Synthetic Shipper A',
        'status': status,
        if (bill != null) 'ewayBill': bill,
      };

  const savedBill = {
    'kind': 'BILL',
    'billNumber': '123456789012',
    'billDate': '2026-10-01',
    'makerGstin': '29ABCDE1234F1Z5',
    'invoiceNumber': 'INV/1',
  };

  Future<void> mount(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(body: ListView(children: [card]))));
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('with nothing added, two equal buttons and no choice made',
      (tester) async {
    await mount(tester, EwayBillCard(shipment: shipment()));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'the empty state says nothing is added');
    expect(
        find.widgetWithText(OutlinedButton, 'Add e-way bill'), findsOneWidget,
        reason: 'first equal choice');
    expect(find.widgetWithText(OutlinedButton, 'No e-way bill needed'),
        findsOneWidget,
        reason: 'second equal choice');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'link-out to the portal');
    await tester.tap(find.text('No e-way bill needed'));
    await tester.pump();
    expect(find.text('Why is no e-way bill needed?'), findsOneWidget,
        reason: 'the statement form opens');
    final choices = tester
        .widgetList<RadioListTile<String>>(find.byType(RadioListTile<String>));
    expect(choices.length, 3, reason: 'three reasons');
    expect(choices.every((choice) => choice.groupValue == null), isTrue,
        reason: 'no reason is preselected');
  });

  testWidgets(
      'adding a bill sends the four details, then shows the number in groups of four and the unchecked state',
      (tester) async {
    Map? sent;
    final now = DateTime.now();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      expect(request.path, '/shipments/shipment-a/eway-bill');
      sent = request.data as Map;
      return jsonResponse({'shipment': shipment(bill: savedBill)});
    });
    await mount(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    expect(find.textContaining('All four are needed to save'), findsOneWidget,
        reason: 'says all four are required');
    expect(
        find.text('Used only by naviG8r ops to find the bill on the portal.'),
        findsNWidgets(2),
        reason: 'says why GSTIN and invoice number are asked');
    await tester.tap(find.text('Save e-way bill'));
    await tester.pump();
    expect(find.text('Fill in all four details to save.'), findsOneWidget,
        reason: 'nothing is sent until all four are filled');
    expect(sent, isNull, reason: 'no request for an incomplete form');
    await tester.enterText(
        field('E-way bill number (12 digits)'), '1234 5678 9012');
    await tester.enterText(
        field('GSTIN of whoever made the bill'), '29ABCDE1234F1Z5');
    await tester.enterText(field('Invoice number'), 'INV/1');
    await tester.tap(find.text('Bill date: choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    expect(sent, {
      'kind': 'BILL',
      'billNumber': '1234 5678 9012',
      'billDate': '${now.year}-$month-$day',
      'makerGstin': '29ABCDE1234F1Z5',
      'invoiceNumber': 'INV/1',
    });
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'number in groups of four');
    expect(find.text('Entered by you. Not checked yet.'), findsOneWidget,
        reason: 'a saved bill starts unchecked');
    expect(find.text('Remove e-way bill'), findsOneWidget,
        reason: 'removing is as easy as adding');
  });

  testWidgets("a refusal shows the server's sentence, never HTTP 400",
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'error': 'invalid_eway_bill',
          'detail': 'The e-way bill number is 12 digits.',
          'field': 'billNumber'
        }, 400));
    await mount(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.enterText(field('E-way bill number (12 digits)'), '1');
    await tester.enterText(field('GSTIN of whoever made the bill'), 'X');
    await tester.enterText(field('Invoice number'), 'Y');
    await tester.tap(find.text('Bill date: choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    expect(find.text('The e-way bill number is 12 digits.'), findsOneWidget,
        reason: 'the server sentence is shown');
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw status text');
    expect(find.text('Save e-way bill'), findsOneWidget,
        reason: 'the form stays open with what was typed');
  });

  testWidgets('saying no bill is needed needs a reason, and Other needs words',
      (tester) async {
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      sent = request.data as Map;
      return jsonResponse({
        'shipment': shipment(bill: {
          'kind': 'NOT_NEEDED',
          'notNeededReason': 'OTHER',
          'notNeededNote': 'Sample goods'
        })
      });
    });
    await mount(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('No e-way bill needed'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Choose why no e-way bill is needed.'), findsOneWidget,
        reason: 'no reason, no save');
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.enterText(field('Write the reason'), 'Sample goods');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sent,
        {'kind': 'NOT_NEEDED', 'reason': 'OTHER', 'note': 'Sample goods'});
    expect(find.text('You said no e-way bill is needed: Sample goods.'),
        findsOneWidget,
        reason: 'the statement is shown back');
    expect(find.text('Change'), findsOneWidget,
        reason: 'the statement can be changed');
  });

  testWidgets(
      'ops findings are worded as what ops saw and when, never as a guarantee',
      (tester) async {
    final found = {
      ...savedBill,
      'check': {'result': 'FOUND', 'checkedAtUtcMs': 1792000000000}
    };
    await mount(tester, EwayBillCard(shipment: shipment(bill: found)));
    expect(
        find.text(
            'Ops saw this bill on the government portal on 14 Oct 2026. It may have changed since.'),
        findsOneWidget,
        reason: 'a date and a caveat');
    expect(find.textContaining('verified'), findsNothing,
        reason: 'the app never says verified');
    final problem = {
      ...savedBill,
      'check': {
        'result': 'PROBLEM',
        'problemReason': 'NOT_FOUND',
        'checkedAtUtcMs': 1792000000000
      }
    };
    await mount(tester,
        EwayBillCard(key: UniqueKey(), shipment: shipment(bill: problem)));
    expect(
        find.text(
            'Ops could not find this bill on the portal on 14 Oct 2026. Check the details here and on the portal.'),
        findsOneWidget,
        reason: 'the shipper is told what to do next');
  });

  testWidgets('the 15 second refresh never wipes what is half typed',
      (tester) async {
    final current = ValueNotifier(shipment());
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: current,
                builder: (context, value, _) => ListView(children: [
                      EwayBillCard(key: const ValueKey('card'), shipment: value)
                    ])))));
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.enterText(field('Invoice number'), 'HALF-TYPED');
    current.value = {...shipment(), 'status': 'BOOKED', 'extra': 1};
    await tester.pump();
    expect(find.text('HALF-TYPED'), findsOneWidget,
        reason: 'typed text survives a refresh');
  });

  testWidgets('without permission, or after delivery, the card only reads',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': <String>[]
    };
    await mount(tester, EwayBillCard(shipment: shipment()));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'still readable');
    expect(find.text('Add e-way bill'), findsNothing,
        reason: 'no write button without permission');
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write']
    };
    await mount(
        tester,
        EwayBillCard(
            key: UniqueKey(),
            shipment: shipment(bill: savedBill, status: 'DELIVERED')));
    expect(find.text('Edit'), findsNothing, reason: 'locked once delivered');
    expect(find.text('Remove e-way bill'), findsNothing,
        reason: 'locked once delivered');
  });

  testWidgets('removing sends the remove request and returns to nothing added',
      (tester) async {
    String? path;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      return jsonResponse({'shipment': shipment()});
    });
    await mount(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Remove e-way bill'));
    await tester.pumpAndSettle();
    expect(path, '/shipments/shipment-a/eway-bill/remove');
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'back to nothing added');
  });

  testWidgets('the portal link opens the government address', (tester) async {
    final launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    await mount(tester, EwayBillCard(shipment: shipment()));
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(launcher.opened, ['https://ewaybillgst.gov.in'],
        reason: 'one fixed address');
    launcher.opens = false;
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(
        find.text(
            'Could not open the portal from here. Its address is ewaybillgst.gov.in.'),
        findsOneWidget,
        reason: 'the address shown is the one this build opens');
  });

  testWidgets('the carrier card shows each state read only, with no buttons',
      (tester) async {
    await mount(tester, EwayBillCarrierCard(shipment: shipment()));
    expect(
        find.text(
            'Synthetic Shipper A has not added an e-way bill or said none is needed.'),
        findsOneWidget,
        reason: 'neutral, no pressure');
    await mount(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(bill: {
              'kind': 'NOT_NEEDED',
              'notNeededReason': 'GOODS_EXEMPT'
            })));
    expect(
        find.textContaining(
            "This is the shipper's statement. naviG8r has not checked it."),
        findsOneWidget,
        reason: 'the statement is the shipper\'s');
    await mount(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(bill: {
              'kind': 'BILL',
              'billNumber': '123456789012',
              'check': {
                'result': 'PROBLEM',
                'problemReason': 'CANCELLED',
                'checkedAtUtcMs': 1792000000000
              }
            })));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'number in groups of four');
    expect(
        find.text(
            'Ops saw on the portal that this bill was cancelled on 14 Oct 2026. The shipper can see this on their shipment.'),
        findsOneWidget,
        reason: 'the carrier is not told to act');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'says what is not checked');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
  });

  // 23:59 on 16 Oct 2026 in India.
  final sixteenthOctoberLastMinuteUtcMs =
      DateTime.utc(2026, 10, 16, 18, 29).millisecondsSinceEpoch;

  Map<String, dynamic> withTruck(Map<String, dynamic> bill) => {
        ...bill,
        'truckNumber': 'KA01AB1234',
        'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs,
      };

  void signInAsCarrier({required bool canAddTruck}) {
    AuthorizationSession.user = {'id': 'carrier-person'};
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': [
        'load.read',
        'carrier.offer_accept',
        'pod.upload',
        'conversation.read',
        if (canAddTruck) 'eway_bill.add_truck'
      ]
    };
  }

  Future<void> chooseTodayAtLastMinute(WidgetTester tester) async {
    await tester.tap(find.text('Valid until, date in India: choose the date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time in India: choose the time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('the shipper adds a truck and sees it on the bill',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write', 'eway_bill.add_truck']
    };
    String? path;
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      sent = request.data as Map;
      return jsonResponse({
        'shipment': {
          ...shipment(bill: withTruck(savedBill)),
          'updatedAtUtcMs': 10
        }
      });
    });
    await mount(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    expect(
        find.text(
            'Truck not added yet. You or your carrier can add it after the truck is on the bill on the portal.'),
        findsOneWidget,
        reason: 'says who can add the truck, and when');
    expect(find.widgetWithText(OutlinedButton, 'Add truck'), findsOneWidget,
        reason: 'a shipper with eway_bill.add_truck can add it');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Add truck'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Truck number'), findsOneWidget,
        reason: 'the truck form opens');
    expect(find.text('Changing these details clears the check.'), findsNothing,
        reason: 'the bill has no check to clear');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'the portal is one tap from the form');
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'KA01AB1234');
    await chooseTodayAtLastMinute(tester);
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    final india =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    expect(path, '/shipments/shipment-a/eway-bill/truck');
    expect(sent, {
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs':
          DateTime.utc(india.year, india.month, india.day, 23, 59)
              .subtract(const Duration(hours: 5, minutes: 30))
              .millisecondsSinceEpoch
    });
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the returned bill shows the truck');
    expect(find.text('Valid until: 16 Oct 2026, 23:59 (India time)'),
        findsOneWidget,
        reason: 'and its valid-until time in India');
    expect(find.widgetWithText(OutlinedButton, 'Change truck'), findsOneWidget,
        reason: 'a saved truck can be changed');
    expect(find.text('Save truck'), findsNothing, reason: 'the form closed');
  });

  testWidgets('a shipper truck refusal shows the server sentence',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write', 'eway_bill.add_truck']
    };
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'error': 'invalid_eway_truck',
          'detail':
              'The valid-until time is more than 30 days away. Check it against the portal.',
          'field': 'validUntilUtcMs'
        }, 400));
    await mount(
        tester,
        EwayBillCard(
            shipment: shipment(bill: {
          ...withTruck(savedBill),
          'check': {'result': 'FOUND', 'checkedAtUtcMs': 1792000000000}
        })));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change truck'));
    await tester.pump();
    expect(find.text('KA01AB1234'), findsOneWidget,
        reason: 'the saved truck is filled in');
    expect(
        find.text('Changing these details clears the check.'), findsOneWidget,
        reason: 'the bill was checked, and a change clears it');
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The valid-until time is more than 30 days away. Check it against the portal.'),
        findsOneWidget,
        reason: 'the server sentence is shown');
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw status text');
  });

  testWidgets('a shipper without the truck permission gets no truck button',
      (tester) async {
    await mount(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    expect(find.textContaining('Truck not added yet.'), findsOneWidget,
        reason: 'the missing truck is still said');
    expect(find.text('Add truck'), findsNothing,
        reason: 'no eway_bill.add_truck, no button');
    expect(find.text('Edit'), findsOneWidget,
        reason: 'the bill itself can still be edited');
  });

  testWidgets('the 15 second refresh never wipes a half typed truck',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'shipper-a',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write', 'eway_bill.add_truck']
    };
    final current = ValueNotifier(shipment(bill: savedBill));
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: current,
                builder: (context, value, _) => ListView(children: [
                      EwayBillCard(key: const ValueKey('card'), shipment: value)
                    ])))));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'HALF-TYPED');
    current.value = {...shipment(bill: savedBill), 'extra': 1};
    await tester.pump();
    expect(find.text('HALF-TYPED'), findsOneWidget,
        reason: 'typed text survives a refresh');
  });

  testWidgets(
      'a carrier owner sees the truck buttons and the portal, and saves on the carrier path',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    final launcher = _RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    String? path;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      return jsonResponse({
        'shipment': shipment(
            bill: withTruck({'kind': 'BILL', 'billNumber': '123456789012'}))
      });
    });
    await mount(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(
        find.text(
            'Truck not on this bill yet. Add your truck to the bill on the portal, then enter it here.'),
        findsOneWidget,
        reason: 'the carrier is told its part');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsOneWidget,
        reason: 'no truck yet, so the original caveat stays');
    expect(find.widgetWithText(OutlinedButton, 'Add truck'), findsOneWidget,
        reason: 'owners and dispatchers can add the truck');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'the owner gets the portal link');
    await tester.tap(find.text('Open the government e-way bill portal'));
    await tester.pump();
    expect(launcher.opened, ['https://ewaybillgst.gov.in'],
        reason: 'the portal link opens the portal address');
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'KA01AB1234');
    await chooseTodayAtLastMinute(tester);
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(path, '/v1/pilot/carrier/shipments/shipment-a/eway-bill/truck');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the saved truck shows');
    expect(
        find.text(
            'Shown as entered in naviG8r. naviG8r has not made or changed this bill, and has not checked it against the portal.'),
        findsOneWidget,
        reason: 'with a truck, the caveat names the portal');
    expect(find.textContaining('has not checked the truck or the expiry'),
        findsNothing,
        reason: 'the old caveat no longer fits');
    expect(find.widgetWithText(OutlinedButton, 'Change truck'), findsOneWidget,
        reason: 'the truck can be changed');
  });

  testWidgets('the 15 second refresh never wipes a carrier half typed truck',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    final bill = {'kind': 'BILL', 'billNumber': '123456789012'};
    final current = ValueNotifier(shipment(bill: bill));
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: current,
                builder: (context, value, _) => ListView(children: [
                      EwayBillCarrierCard(
                          key: const ValueKey('card'), shipment: value)
                    ])))));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'HALF-TYPED');
    current.value = {...shipment(bill: bill), 'extra': 1};
    await tester.pump();
    expect(find.text('HALF-TYPED'), findsOneWidget,
        reason: 'typed text survives a refresh');
  });

  testWidgets('a carrier owner gets no truck buttons once delivered',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    await mount(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                status: 'DELIVERED',
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(find.text('Add truck'), findsNothing,
        reason: 'locked once delivered');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'nothing to do on the portal once delivered');
  });

  testWidgets('a driver sees the truck lines but no buttons and no portal link',
      (tester) async {
    signInAsCarrier(canAddTruck: false);
    await mount(
        tester,
        EwayBillCarrierCard(
            shipment: shipment(
                bill: withTruck(
                    {'kind': 'BILL', 'billNumber': '123456789012'}))));
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the number to quote at a check-post');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the truck on the bill');
    expect(find.text('Valid until: 16 Oct 2026, 23:59 (India time)'),
        findsOneWidget,
        reason: 'the valid-until time in India');
    expect(find.textContaining('has not checked it against the portal'),
        findsOneWidget,
        reason: 'the caveat for a bill with a truck');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'read only');
    expect(find.byType(FilledButton), findsNothing, reason: 'read only');
    expect(find.text('Open the government e-way bill portal'), findsNothing,
        reason: 'a driver has nothing to do on the portal');
    await mount(
        tester,
        EwayBillCarrierCard(
            key: UniqueKey(),
            shipment: shipment(
                bill: {'kind': 'BILL', 'billNumber': '123456789012'})));
    expect(find.text('Truck not added yet.'), findsOneWidget,
        reason: 'a driver is not told to add it');
  });

  testWidgets(
      'the carrier detail screen fits a 360 by 640 phone with the card on it',
      (tester) async {
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': [
        'load.read',
        'carrier.offer_accept',
        'pod.upload',
        'conversation.read'
      ]
    };
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'shipments': [
            {
              ...shipment(status: 'PENDING_CARRIER_ACCEPT'),
              'pickupAddress': 'Synthetic pickup address, Bengaluru',
              'dropAddress': 'Synthetic drop address, Chennai',
              'netToCarrierPaise': 250000,
              'ewayBill': {
                'kind': 'BILL',
                'billNumber': '123456789012',
                'truckNumber': 'KA01AB1234',
                'validUntilUtcMs': 1792000000000,
                'check': {
                  'result': 'PROBLEM',
                  'problemReason': 'DETAILS_DO_NOT_MATCH',
                  'checkedAtUtcMs': 1792000000000
                }
              }
            }
          ]
        }));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pumpAndSettle();
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the bill shows on the detail screen');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the driver sees the truck');
    expect(
        find.text('The valid-until time entered has passed. Check the portal.'),
        findsOneWidget,
        reason: 'a past valid-until time is reported as typed, not as expired');
    expect(find.text('Change truck'), findsNothing,
        reason: 'a driver cannot change the truck');
    expect(find.text('Accept booking'), findsOneWidget,
        reason: 'the accept button is still on screen');
    expect(tester.takeException(), isNull,
        reason: 'no overflow on a small phone');
  });

  testWidgets(
      'the carrier detail screen fits a 360 by 640 phone for an owner with a truck on the bill',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'shipments': [
            {
              ...shipment(status: 'PENDING_CARRIER_ACCEPT'),
              'customerOrgName':
                  'Synthetic Shipper With A Very Long Registered Business Name Private Limited',
              'pickupAddress': 'Synthetic pickup address, Bengaluru',
              'dropAddress': 'Synthetic drop address, Chennai',
              'netToCarrierPaise': 250000,
              'ewayBill': {
                'kind': 'BILL',
                'billNumber': '123456789012',
                'truckNumber': 'KA01AB1234',
                // Inside the last 12 hours, so the countdown line shows too.
                'validUntilUtcMs': DateTime.now()
                    .add(const Duration(hours: 11))
                    .millisecondsSinceEpoch,
                'check': {
                  'result': 'PROBLEM',
                  'problemReason': 'DETAILS_DO_NOT_MATCH',
                  'checkedAtUtcMs': 1792000000000
                }
              }
            }
          ]
        }));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pumpAndSettle();
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'the bill shows on the detail screen');
    expect(find.text('Truck: KA01AB1234'), findsOneWidget,
        reason: 'the truck shows');
    expect(find.textContaining('Expires in'), findsOneWidget,
        reason: 'the countdown shows inside the last 12 hours');
    expect(find.textContaining('The details here did not match the portal'),
        findsOneWidget,
        reason: 'the longest check line');
    expect(find.text('Change truck'), findsOneWidget,
        reason: 'the owner can change the truck');
    expect(find.text('Open the government e-way bill portal'), findsOneWidget,
        reason: 'the owner has the portal link');
    expect(find.text('Accept booking'), findsOneWidget,
        reason: 'the accept button is still on screen');
    expect(tester.takeException(), isNull,
        reason: 'no overflow on a small phone');
  });

  testWidgets('a different shipment in the same place starts clean',
      (tester) async {
    await mount(tester, EwayBillCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Edit'));
    await tester.pump();
    await tester.enterText(field('Invoice number'), 'TYPED-FOR-A');
    await mount(
        tester, EwayBillCard(shipment: {...shipment(), 'id': 'shipment-b'}));
    expect(find.text('No e-way bill added yet.'), findsOneWidget,
        reason: 'the new shipment\'s own state, form closed');
    await tester.tap(find.text('Add e-way bill'));
    await tester.pump();
    expect(find.text('TYPED-FOR-A'), findsNothing,
        reason: 'nothing typed for the old shipment carries over');

    signInAsCarrier(canAddTruck: true);
    await mount(
        tester, EwayBillCarrierCard(shipment: shipment(bill: savedBill)));
    await tester.tap(find.text('Add truck'));
    await tester.pump();
    expect(find.text('Save truck'), findsOneWidget, reason: 'form open');
    await mount(
        tester,
        EwayBillCarrierCard(shipment: {
          ...shipment(bill: {'kind': 'BILL', 'billNumber': '999988887777'}),
          'id': 'shipment-b'
        }));
    expect(find.text('Save truck'), findsNothing,
        reason: 'the old shipment\'s truck form closed');
    expect(find.text('9999 8888 7777'), findsOneWidget,
        reason: 'the new shipment\'s bill shows');
  });
}
