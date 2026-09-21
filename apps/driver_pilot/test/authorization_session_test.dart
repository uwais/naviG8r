import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final organizations = [
    {'id': 'shipper-a', 'kind': 'CUSTOMER', 'displayName': 'Shipper A'},
    {'id': 'platform', 'kind': 'PLATFORM', 'displayName': 'Internal'},
    {'id': 'carrier-a', 'kind': 'CARRIER_FLEET', 'displayName': 'Carrier A'},
  ];
  Map<String, dynamic> me(String? selected, {bool owner = false}) => {
        'user': {'id': 'dual', 'phone': '8000000008'},
        'organizations': organizations,
        if (selected != null)
          'principal': {
            'organizationId': selected,
            'roles': [
              selected == 'shipper-a'
                  ? 'SHIPPER'
                  : selected == 'platform'
                      ? 'FINANCE'
                      : 'CARRIER'
            ],
            'permissions': selected == 'shipper-a'
                ? ['load.read', 'pod.accept']
                : selected == 'platform'
                    ? ['payment.capture']
                    : ['load.read', if (owner) 'bank_account.create_token'],
          },
      };
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(
        {'access_token': 'synthetic-token'});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.bind();
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        jsonResponse(me(request.headers['x-organization-id'] as String?)));
  });

  test(
      'requires explicit selection and never combines shipper and finance grants',
      () async {
    await AuthorizationSession.refresh();
    expect(AuthorizationSession.organizationId, isNull);
    expect(AuthorizationSession.can('pod.accept'), isFalse);
    await AuthorizationSession.selectOrganization('shipper-a');
    expect(CustomerSession.customerOrgId, 'shipper-a');
    expect(AuthorizationSession.can('pod.accept'), isTrue);
    expect(AuthorizationSession.can('payment.capture'), isFalse);
    await AuthorizationSession.selectOrganization('platform');
    expect(CustomerSession.customerOrgId, isNull);
    expect(AuthorizationSession.can('pod.accept'), isFalse);
    expect(AuthorizationSession.can('payment.capture'), isTrue);
    expect(mobileAccessRedirect('/customer/shipments'), '/workspace');
  });

  test('uses server permissions for owner actions and blocks deep links',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('carrier-a');
    expect(DriverSession.canSetUpPayouts, isFalse);
    expect(mobileAccessRedirect('/driver/payout-setup'), '/driver');
    api.dio.httpClientAdapter =
        MockApiAdapter((request) => jsonResponse(me('carrier-a', owner: true)));
    await AuthorizationSession.refresh();
    expect(DriverSession.canSetUpPayouts, isTrue);
    expect(mobileAccessRedirect('/driver/payout-setup'), isNull);
  });

  test('sends selected organization and bearer token on protected requests',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      expect(request.headers['x-organization-id'], 'shipper-a');
      expect(request.headers['authorization'], 'Bearer synthetic-token');
      return jsonResponse({'shipments': []});
    });
    await api.get('/shipments');
  });

  test('discards an old organization response arriving after a switch',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    final started = Completer<void>();
    final delayed = Completer<ResponseBody>();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path == '/shipments') {
        started.complete();
        return delayed.future;
      }
      return jsonResponse(me(request.headers['x-organization-id'] as String?));
    });
    final request = api.get('/shipments');
    final assertion = expectLater(
        request,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    await started.future;
    await AuthorizationSession.selectOrganization('platform');
    delayed.complete(jsonResponse({
      'shipments': [
        {'id': 'private-old-shipment'}
      ]
    }));
    await assertion;
  });

  test(
      'recovers revoked membership without selecting another organization silently',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        request.headers['x-organization-id'] != null
            ? jsonResponse({'error': 'membership_inactive'}, 403)
            : jsonResponse(me(null)));
    await AuthorizationSession.refresh();
    expect(AuthorizationSession.signedIn, isTrue);
    expect(api.activeOrganizationId, isNull);
    expect(AuthorizationSession.can('pod.accept'), isFalse);
  });

  test(
      'failed refresh drops grants; signout clears all projections and selection',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unavailable'}, 503));
    await AuthorizationSession.refresh();
    expect(AuthorizationSession.can('pod.accept'), isFalse);
    await AuthorizationSession.signOut();
    expect(CustomerSession.isSignedIn, isFalse);
    expect(DriverSession.hasCarrierOrg, isFalse);
    expect(api.activeOrganizationId, isNull);
    expect(
        await const FlutterSecureStorage().read(key: 'access_token'), isNull);
  });

  test('revoked roles immediately remove actions after refresh', () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    final revoked = me('shipper-a');
    revoked['principal'] = {
      'organizationId': 'shipper-a',
      'roles': [],
      'permissions': []
    };
    api.dio.httpClientAdapter =
        MockApiAdapter((request) => jsonResponse(revoked));
    await AuthorizationSession.refresh();
    expect(CustomerSession.hasCustomerOrg, isFalse);
    expect(mobileAccessRedirect('/customer/shipments'), '/workspace');
  });
}
