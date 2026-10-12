import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/push_notifications.dart';
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

  test('initial sign-in preserves a queued cold-start notification tap',
      () async {
    const pending =
        '{"schemaVersion":"1","notificationId":"notice-1","expiresAt":4102444800000}';
    FlutterSecureStorage.setMockInitialValues({
      'push_pending_notification': pending,
    });
    await api.setToken('new-signed-in-token');
    final stored = await const FlutterSecureStorage()
        .read(key: 'push_pending_notification');
    expect(stored, pending);
  });

  test('expired established session clears push state and leaves revocation',
      () async {
    await AuthorizationSession.refresh();
    await const FlutterSecureStorage()
        .write(key: 'push_device_owner', value: 'dual');
    await const FlutterSecureStorage()
        .write(key: 'push_device_id', value: 'device-1');
    await const FlutterSecureStorage()
        .write(key: 'push_device_generation', value: '7');
    await const FlutterSecureStorage()
        .write(key: 'push_alerts_consented', value: 'true');
    await const FlutterSecureStorage()
        .write(key: 'push_alerts_consent_owner', value: 'dual');
    await const FlutterSecureStorage().write(
        key: 'push_pending_notification',
        value: '{"schemaVersion":"1","notificationId":"notice-1"}');
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unauthorized'}, 401));

    await AuthorizationSession.refresh();

    expect(AuthorizationSession.signedIn, isFalse);
    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'push_alerts_consented'), isNull);
    expect(await storage.read(key: 'push_alerts_consent_owner'), isNull);
    expect(await storage.read(key: 'push_pending_notification'), isNull);
    expect(await storage.read(key: 'push_pending_revocation'),
        '{"userId":"dual","deviceId":"device-1","generation":7}');
    PushNotifications.instance.onCredentialChanged();
  });

  test('cold boot with expired stored bearer cleans prior push owner',
      () async {
    await const FlutterSecureStorage()
        .write(key: 'push_device_owner', value: 'old-account');
    await const FlutterSecureStorage()
        .write(key: 'push_device_id', value: 'old-device');
    await const FlutterSecureStorage()
        .write(key: 'push_device_generation', value: '3');
    await const FlutterSecureStorage()
        .write(key: 'push_alerts_consented', value: 'true');
    await const FlutterSecureStorage().write(
        key: 'push_pending_notification',
        value: '{"schemaVersion":"1","notificationId":"old-notice"}');
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unauthorized'}, 401));

    await AuthorizationSession.refresh();

    expect(AuthorizationSession.signedIn, isFalse);
    final storage = const FlutterSecureStorage();
    expect(await storage.read(key: 'push_alerts_consented'), isNull);
    expect(await storage.read(key: 'push_pending_notification'), isNull);
    expect(await storage.read(key: 'push_pending_revocation'),
        '{"userId":"old-account","deviceId":"old-device","generation":3}');
    PushNotifications.instance.onCredentialChanged();
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

  test('keeps push registration response across organization changes',
      () async {
    await AuthorizationSession.refresh();
    await AuthorizationSession.selectOrganization('shipper-a');
    final started = Completer<void>();
    final delayed = Completer<ResponseBody>();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.method == 'PUT' && request.path == '/v1/me/push-devices') {
        started.complete();
        return delayed.future;
      }
      return jsonResponse(me(request.headers['x-organization-id'] as String?));
    });
    final registration = api.put<Map<String, dynamic>>(
      '/v1/me/push-devices',
      data: const {'installationId': 'test-install', 'token': 'test-token'},
    );
    await started.future;
    await AuthorizationSession.selectOrganization('platform');
    delayed.complete(jsonResponse({
      'deviceId': 'device-1',
      'ownershipGeneration': 4,
    }));

    expect((await registration).data?['ownershipGeneration'], 4);
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
