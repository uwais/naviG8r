import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'eway_bill_fixtures.dart';

/// Someone at carrier-a with a role there; [canAssign] lets them name a trip's truck and driver.
void signInAsCarrierStaff({required String subrole, required bool canAssign}) {
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal = {
    'organizationId': 'carrier-a',
    'roles': ['CARRIER'],
    'subrole': subrole,
    'permissions': ['load.read', if (canAssign) 'trip.assign'],
  };
}

const carrierOrganization = {
  'id': 'carrier-a',
  'kind': 'CARRIER_FLEET',
  'displayName': 'Synthetic Carrier A',
  'kycStatus': 'APPROVED',
};

/// A driver holds no payment.read; the carrier office does. [alsoAllowed] adds permissions to either.
Map<String, dynamic> carrierPrincipal(
        {required bool office, List<String> alsoAllowed = const []}) =>
    {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'subrole': office ? 'OWNER' : 'DRIVER',
      'permissions': [
        'organization.profile.read',
        'load.read',
        if (office) 'payment.read',
        ...alsoAllowed,
      ],
    };

/// A fresh API client and a login at the approved carrier-a, as its office or as one of its drivers.
void signInAsCarrierLogin(
    {required bool office, List<String> alsoAllowed = const []}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  api = Api('http://test');
  AuthorizationSession.clear();
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal =
      carrierPrincipal(office: office, alsoAllowed: alsoAllowed);
  AuthorizationSession.organizations = [carrierOrganization];
  api.selectOrganization('carrier-a');
}

/// The carrier's owner: the office plus who may add the bank account, which is how the app tells an owner from
/// a dispatcher today.
void signInAsCarrierOwner({List<String> alsoAllowed = const []}) =>
    signInAsCarrierLogin(
        office: true,
        alsoAllowed: ['bank_account.create_token', ...alsoAllowed]);

/// A shipment on trip-a as the carrier shipment list sends it; the amount is sent to the office only.
Map<String, dynamic> shipmentOnTripA(
        {String status = 'BOOKED', int? netToCarrierPaise}) =>
    {
      ...shipment(status: status),
      'anchorTripId': 'trip-a',
      'weightKg': 120,
      'pickupAddress': 'Peenya, Bengaluru',
      'dropAddress': 'Hosur',
      if (netToCarrierPaise != null) 'netToCarrierPaise': netToCarrierPaise,
    };
