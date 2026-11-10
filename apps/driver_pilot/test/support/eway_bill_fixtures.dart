import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the browser: records each address it is asked to open, and opens or refuses.
class RecordingLauncher extends Fake
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

/// A fresh API client and a shipper of shipper-a, by default allowed to write the bill but not the truck.
void signInAsShipper({List<String> permissions = const ['eway_bill.write']}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  api = Api('http://test');
  AuthorizationSession.clear();
  AuthorizationSession.user = {'id': 'shipper'};
  AuthorizationSession.principal = {
    'organizationId': 'shipper-a',
    'roles': ['SHIPPER'],
    'permissions': permissions
  };
  AuthorizationSession.organizations = [
    {'id': 'shipper-a', 'displayName': 'Shipper A'}
  ];
  api.selectOrganization('shipper-a');
}

/// A carrier login: the office (owner or dispatcher) names the trip's truck and driver, a driver
/// cannot. Neither adds the truck to the e-way bill; only the shipper does.
void signInAsCarrier({required bool office}) {
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal = {
    'organizationId': 'carrier-a',
    'roles': ['CARRIER'],
    'permissions': [
      'load.read',
      'carrier.offer_accept',
      'pod.upload',
      'conversation.read',
      if (office) 'trip.assign'
    ]
  };
}

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

/// 23:59 on 16 Oct 2026 in India is 18:29 that day in UTC.
final sixteenthOctoberLastMinuteUtcMs =
    DateTime.utc(2026, 10, 16, 18, 29).millisecondsSinceEpoch;

Map<String, dynamic> withTruck(Map<String, dynamic> bill) => {
      ...bill,
      'truckNumber': 'KA01AB1234',
      'validUntilUtcMs': sixteenthOctoberLastMinuteUtcMs,
    };

/// Puts one card on a tall screen, so nothing needs scrolling.
Future<void> mountCard(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: Scaffold(body: ListView(children: [card]))));
}

/// Mounts a card that rebuilds each time [current] changes, the way the 15 second refresh does.
Future<void> mountRefreshingCard(
    WidgetTester tester,
    ValueNotifier<Map<String, dynamic>> current,
    Widget Function(Map<String, dynamic> shipment) card) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: Scaffold(
          body: ValueListenableBuilder(
              valueListenable: current,
              builder: (context, value, _) =>
                  ListView(children: [card(value)])))));
}

Finder field(String label) => find.widgetWithText(TextField, label);

/// Today in India on the date picker, and the picker's own 23:59 on the time picker.
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

/// A final e-way bill, so a trip can start (owner, 23 Oct 2026): the trip's truck and a valid-until time three
/// days from now. Tests about the start rule itself write their own bills.
Map<String, dynamic> finalBill(
        {String billNumber = '123456789012', String truck = 'KA01AB1234'}) =>
    {
      'kind': 'BILL',
      'billNumber': billNumber,
      'truckNumber': truck,
      'validUntilUtcMs':
          DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
    };
