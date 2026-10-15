// Owner decision, 15 Oct 2026: a driver never sees carrier earnings. The server leaves the amounts out for a
// driver and refuses the earnings routes; these check the app shows no made-up zero and no way in.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

const carrierOrganization = {
  'id': 'carrier-a',
  'kind': 'CARRIER_FLEET',
  'displayName': 'Synthetic Carrier A',
  'kycStatus': 'APPROVED',
};

/// A driver holds no payment.read; the carrier office does.
Map<String, dynamic> carrierPrincipal({required bool office}) => {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'subrole': office ? 'OWNER' : 'DRIVER',
      'permissions': [
        'organization.profile.read',
        'load.read',
        if (office) 'payment.read',
      ],
    };

void signInAsCarrierLogin({required bool office}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  api = Api('http://test');
  AuthorizationSession.clear();
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal = carrierPrincipal(office: office);
  AuthorizationSession.organizations = [carrierOrganization];
  api.selectOrganization('carrier-a');
}

Map<String, dynamic> bookedShipment({int? netToCarrierPaise}) => {
      ...shipment(),
      'anchorTripId': 'trip-a',
      'weightKg': 120,
      'pickupAddress': 'Peenya, Bengaluru',
      'dropAddress': 'Hosur',
      if (netToCarrierPaise != null) 'netToCarrierPaise': netToCarrierPaise,
    };

Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('The shipment screen', () {
    testWidgets('shows no net line at all when the amount is not sent',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [bookedShipment()]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Drop: Hosur'), findsOneWidget,
          reason: 'the shipment loaded');
      expect(find.textContaining('Net to carrier'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('shows the amount to the office, who is sent it',
        (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [bookedShipment(netToCarrierPaise: 4500)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Net to carrier: ₹45'), findsOneWidget);
    });

    /// What the server sends after proof of delivery; it leaves the payment hold out for a driver.
    Map<String, dynamic> deliveredShipment({required bool withPaymentHold}) => {
          ...bookedShipment(),
          'status': 'PENDING_RELEASE',
          'podAtUtcMs': 1760500000000,
          if (withPaymentHold) ...{
            'paymentReady': false,
            'paymentHoldUntilUtcMs': 1760672800000,
          },
        };

    testWidgets(
        'tells a driver delivery was confirmed, without the payment hold or release lines',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [deliveredShipment(withPaymentHold: false)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Proof of delivery submitted'), findsOneWidget);
      for (final payout in [
        'Payment on hold',
        'Ready for Finance review',
        'Payment released'
      ]) {
        expect(find.textContaining(payout), findsNothing, reason: payout);
      }
    });

    testWidgets('tells the office when the payment is held', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [deliveredShipment(withPaymentHold: true)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Proof of delivery submitted'), findsOneWidget);
      expect(find.textContaining('Payment on hold until'), findsOneWidget);
    });
  });

  group('The trip screen', () {
    MockApiAdapter tripServer(Map<String, dynamic> onTrip) => MockApiAdapter(
        (request) => request.path == '/v1/pilot/anchor-trips/trip-a'
            ? jsonResponse({
                'trip': {'id': 'trip-a', 'status': 'OPEN'}
              })
            : jsonResponse({
                'shipments': [onTrip]
              }));

    testWidgets('lists a shipment by its status alone when no amount is sent',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = tripServer(bookedShipment());
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('adds the amount for the office', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter =
          tripServer(bookedShipment(netToCarrierPaise: 4500));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted · ₹45 net'), findsOneWidget);
    });
  });

  group('The Profile screen', () {
    /// The screen refreshes the session first, so the server answers with the same login.
    MockApiAdapter profileServer({required bool office}) =>
        MockApiAdapter((request) => request.path == '/v1/auth/me'
            ? jsonResponse({
                'user': {
                  'id': 'carrier-person',
                  'fullName': 'Synthetic Person'
                },
                'organizations': [carrierOrganization],
                'principal': carrierPrincipal(office: office),
              })
            : jsonResponse({
                'driverProfile': {'primaryVehicleId': 'vehicle-1'},
                'vehicles': [
                  {
                    'id': 'vehicle-1',
                    'registrationNumber': 'KA01AB1234',
                    'vehicleClass': 'MEDIUM',
                    'capacityKg': 1000
                  }
                ],
              }));

    testWidgets('has no way into earnings or payouts for a driver',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = profileServer(office: false);
      await mountScreen(tester, const DriverProfileScreen());
      expect(find.text('Your vehicle'), findsOneWidget,
          reason: 'the screen loaded');
      expect(find.text('Earnings & payouts'), findsNothing);
    });

    testWidgets('keeps it for the office', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = profileServer(office: true);
      await mountScreen(tester, const DriverProfileScreen());
      expect(find.text('Earnings & payouts'), findsOneWidget);
    });
  });
}
