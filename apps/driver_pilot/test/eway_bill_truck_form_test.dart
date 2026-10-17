import 'dart:async';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_card.dart';
import 'package:driver_pilot/eway_bill_truck_form.dart';
import 'package:driver_pilot/eway_bill_words.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'carrier-owner'};
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['eway_bill.add_truck']
    };
  });

  final savedShipments = <Map<String, dynamic>>[];
  var cancelled = 0;

  Future<void> mountTruckForm(WidgetTester tester,
      {bool clearsCheck = false, Map<String, dynamic>? current}) async {
    savedShipments.clear();
    cancelled = 0;
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: ListView(children: [
          EwayBillTruckForm(
              path: '/v1/pilot/carrier/shipments/shipment-a/eway-bill/truck',
              clearsCheck: clearsCheck,
              current: current,
              onSaved: savedShipments.add,
              onCancel: () => cancelled++),
        ]))));
  }

  Finder truckField() => find.widgetWithText(TextField, 'Truck number');

  test('a date and time typed as India time become the right moment', () {
    expect(
        validUntilUtcMsFromIndiaTime(
            DateTime(2026, 10, 16), const TimeOfDay(hour: 23, minute: 59)),
        sixteenthOctoberLastMinuteUtcMs,
        reason: 'India is five and a half hours ahead of UTC');
    expect(
        validUntilUtcMsFromIndiaTime(
            DateTime(2026, 10, 16), const TimeOfDay(hour: 2, minute: 0)),
        DateTime.utc(2026, 10, 15, 20, 30).millisecondsSinceEpoch,
        reason: 'early morning in India is the evening before in UTC');
  });

  test(
      'the countdown shows only in the last 12 hours, and past says the typed time has passed',
      () {
    final validUntil = DateTime.utc(2026, 10, 16, 18, 29);
    Map<String, dynamic> bill() => {
          'kind': 'BILL',
          'truckNumber': 'KA01AB1234',
          'validUntilUtcMs': validUntil.millisecondsSinceEpoch
        };
    List<String> linesAt(Duration before) =>
        ewayBillTruckLines(bill(), now: validUntil.subtract(before));
    expect(linesAt(const Duration(days: 1)),
        ['Truck: KA01AB1234', 'Valid until: 16 Oct 2026, 23:59 (India time)'],
        reason: 'a day out: truck and time, no countdown');
    expect(linesAt(const Duration(hours: 12)),
        ['Truck: KA01AB1234', 'Valid until: 16 Oct 2026, 23:59 (India time)'],
        reason: 'exactly 12 hours out: still no countdown');
    expect(linesAt(const Duration(hours: 11, minutes: 59)).last,
        'Expires in 11 hours',
        reason: 'under 12 hours the countdown appears');
    expect(linesAt(const Duration(minutes: 90)).last, 'Expires in 1 hour',
        reason: 'one hour, singular');
    expect(linesAt(const Duration(minutes: 30)).last,
        'Expires in less than an hour',
        reason: 'never "Expires in 0 hours"');
    expect(linesAt(Duration.zero).last,
        'The valid-until time entered has passed. Check the portal.',
        reason: 'at the valid-until time; naviG8r cannot see the portal');
    expect(linesAt(const Duration(hours: -3)).last,
        'The valid-until time entered has passed. Check the portal.',
        reason: 'past the valid-until time');
    expect(ewayBillTruckLines({'kind': 'BILL', 'billNumber': '123456789012'}),
        isEmpty,
        reason: 'no truck, no lines');
  });

  testWidgets('nothing is sent until truck, date and time are all chosen',
      (tester) async {
    var requests = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      requests++;
      return jsonResponse({'shipment': <String, dynamic>{}});
    });
    await mountTruckForm(tester);
    expect(
        find.text(
            'Add the truck to the bill on the government portal first, then copy the truck number and the valid-until time from it.'),
        findsOneWidget,
        reason: 'says where the details come from');
    expect(truckField(), findsOneWidget, reason: 'truck number field');
    expect(find.text('Valid until, date in India: choose the date'),
        findsOneWidget,
        reason: 'date button, nothing chosen');
    expect(find.text('Time in India: choose the time'), findsOneWidget,
        reason: 'time button, nothing chosen');
    expect(find.text('Changing these details clears the check.'), findsNothing,
        reason: 'no check to clear');
    expect(find.widgetWithText(FilledButton, 'Save truck'), findsOneWidget,
        reason: 'save is the filled button');
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget,
        reason: 'cancel is a text button');
    await tester.enterText(truckField(), 'KA01AB1234');
    await tester.tap(find.text('Save truck'));
    await tester.pump();
    expect(
        find.text('Fill in the truck number, the date and the time to save.'),
        findsOneWidget,
        reason: 'the date and time are still missing');
    expect(requests, 0, reason: 'no request for an incomplete form');
    await tester.tap(find.text('Cancel'));
    expect(cancelled, 1, reason: 'cancel hands back to the card');
  });

  testWidgets(
      'saving sends the truck as typed and the chosen India time as a moment',
      (tester) async {
    String? path;
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      path = request.path;
      sent = request.data as Map;
      return jsonResponse({
        'shipment': {'id': 'shipment-a', 'updatedAtUtcMs': 5}
      });
    });
    await mountTruckForm(tester, clearsCheck: true);
    expect(
        find.text('Changing these details clears the check.'), findsOneWidget,
        reason: 'the bill had a check');
    await tester.enterText(truckField(), 'ka 01 ab 1234');
    await tester.tap(find.text('Valid until, date in India: choose the date'));
    await tester.pumpAndSettle();
    // The picker opens on today in India, which can differ from today where the test runs.
    final india =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.lastDate, DateTime(india.year, india.month, india.day + 29),
        reason:
            'the last day is 29 ahead, so even 23:59 on it is inside the 30 days');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Time in India: choose the time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final expected = DateTime.utc(india.year, india.month, india.day, 23, 59)
        .subtract(const Duration(hours: 5, minutes: 30))
        .millisecondsSinceEpoch;
    expect(find.text('Time in India: 23:59'), findsOneWidget,
        reason: 'the chosen time, 24-hour');
    expect(find.textContaining(', 23:59'), findsOneWidget,
        reason: 'the date button shows date and time together');
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(path, '/v1/pilot/carrier/shipments/shipment-a/eway-bill/truck');
    expect(sent, {'truckNumber': 'ka 01 ab 1234', 'validUntilUtcMs': expected},
        reason: 'the server tidies the number; the time is India time');
    expect(
        savedShipments,
        [
          {'id': 'shipment-a', 'updatedAtUtcMs': 5}
        ],
        reason: 'the returned shipment goes back to the card');
  });

  testWidgets('changing a truck shows the saved one back in India time',
      (tester) async {
    Map? sent;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      sent = request.data as Map;
      return jsonResponse({'shipment': <String, dynamic>{}});
    });
    await mountTruckForm(tester, current: {
      'kind': 'BILL',
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs
    });
    expect(find.text('KA01AB1234'), findsOneWidget,
        reason: 'the saved truck number is filled in');
    expect(find.text('Valid until, date in India: 16 Oct 2026, 23:59'),
        findsOneWidget,
        reason: 'the saved date, read in India');
    expect(find.text('Time in India: 23:59'), findsOneWidget,
        reason: 'the saved time, read in India');
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(
        sent,
        {
          'truckNumber': 'KA01AB1234',
          'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs
        },
        reason: 'an unchanged form sends back the same moment');
  });

  testWidgets("a refusal shows the server's sentence, never HTTP 400",
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
          'error': 'invalid_eway_truck',
          'detail':
              'The truck number is 6 to 12 letters and digits, for example KA01AB1234.',
          'field': 'truckNumber'
        }, 400));
    await mountTruckForm(tester, current: {
      'truckNumber': 'X',
      'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs
    });
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'The truck number is 6 to 12 letters and digits, for example KA01AB1234.'),
        findsOneWidget,
        reason: 'the server sentence is shown');
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw status text');
    expect(savedShipments, isEmpty, reason: 'nothing saved');
    expect(find.text('Save truck'), findsOneWidget,
        reason: 'the form stays open with what was typed');
  });

  testWidgets('an answer that arrives after switching organization is dropped',
      (tester) async {
    final answer = Completer<ResponseBody>();
    var requests = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      requests++;
      return answer.future;
    });
    await mountTruckForm(tester, current: {
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs
    });
    await tester.tap(find.text('Save truck'));
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget,
        reason: 'busy while the request is out');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Saving...'))
            .onPressed,
        isNull,
        reason: 'a second tap while saving does nothing');
    AuthorizationSession.principal = {
      'organizationId': 'carrier-b',
      'roles': ['CARRIER'],
      'permissions': ['eway_bill.add_truck']
    };
    answer.complete(jsonResponse({'shipment': <String, dynamic>{}}));
    await tester.pumpAndSettle();
    expect(requests, 1, reason: 'the save did go out, once');
    expect(savedShipments, isEmpty,
        reason: 'the other organization never sees this answer');
  });

  group('the shipper adds the truck from the card', () {
    setUp(() => signInAsShipper(
        permissions: ['eway_bill.write', 'eway_bill.add_truck']));

    testWidgets('the shipper adds a truck and sees it on the bill',
        (tester) async {
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
      await mountCard(
          tester, EwayBillCard(shipment: shipment(bill: savedBill)));
      expect(
          find.text('Bill 1234 5678 9012 saved. The truck is not on it yet.'),
          findsOneWidget,
          reason: 'copy.md step 3: the bill is saved, the truck is not on it');
      expect(
          find.text(
              'Add the truck on the portal before the goods move, then enter it here.'),
          findsOneWidget,
          reason: 'copy.md step 3: what to do, and when');
      expect(find.widgetWithText(FilledButton, 'Add truck'), findsOneWidget,
          reason: 'sh-ewb-truck: Add truck is the step\'s primary');
      await tester.tap(find.widgetWithText(FilledButton, 'Add truck'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Truck number'), findsOneWidget,
          reason: 'the truck form opens');
      expect(
          find.text('Changing these details clears the check.'), findsNothing,
          reason: 'the bill has no check to clear');
      expect(find.text('Open the e-way bill portal'), findsOneWidget,
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
      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'the returned bill shows the truck');
      expect(find.textContaining(RegExp(r'^16 Oct( 2026)?, 23:59 IST$')),
          findsOneWidget,
          reason: 'and its valid-until time in India');
      expect(find.widgetWithText(TextButton, 'Change truck'), findsOneWidget,
          reason: 'a saved truck can be changed');
      expect(find.text('Save truck'), findsNothing, reason: 'the form closed');
    });

    testWidgets('a shipper truck refusal shows the server sentence',
        (tester) async {
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'error': 'invalid_eway_truck',
            'detail':
                'The valid-until time is more than 30 days away. Check it against the portal.',
            'field': 'validUntilUtcMs'
          }, 400));
      await mountCard(
          tester,
          EwayBillCard(
              shipment: shipment(bill: {
            ...withTruck(savedBill),
            'check': {'result': 'FOUND', 'checkedAtUtcMs': 1792000000000}
          })));
      await tester.tap(find.widgetWithText(TextButton, 'Change truck'));
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
      signInAsShipper();
      await mountCard(
          tester, EwayBillCard(shipment: shipment(bill: savedBill)));
      expect(find.textContaining('The truck is not on it yet.'), findsOneWidget,
          reason: 'the missing truck is still said');
      expect(find.text('Add truck'), findsNothing,
          reason: 'no eway_bill.add_truck, no button');
      expect(find.text('Edit'), findsOneWidget,
          reason: 'the bill itself can still be edited');
    });

    testWidgets('the 15 second refresh never wipes a half typed truck',
        (tester) async {
      final current = ValueNotifier(shipment(bill: savedBill));
      await mountRefreshingCard(
          tester,
          current,
          (value) =>
              EwayBillCard(key: const ValueKey('card'), shipment: value));
      await tester.tap(find.text('Add truck'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Truck number'), 'HALF-TYPED');
      current.value = {...shipment(bill: savedBill), 'extra': 1};
      await tester.pump();
      expect(find.text('HALF-TYPED'), findsOneWidget,
          reason: 'typed text survives a refresh');
    });
  });
}
