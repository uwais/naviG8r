// Bug-hunt batch 2, X2: a push tap for a notice from another company switched company and then landed on
// Home, because the screens were still being rebuilt for the new company and there was no navigator yet.
import 'dart:convert';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart' as app;
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipment_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  testWidgets('a tap on a notice from the other company opens its messages',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'synthetic',
      // The tap the app was opened with, waiting for the sign-in to load.
      'push_pending_notification': jsonEncode({
        'schemaVersion': '1',
        'notificationId': 'notice-1',
        'expiresAt': 4102444800000,
      }),
    });
    AuthorizationSession.clear();
    await app.main();
    api.dio.httpClientAdapter = MockApiAdapter((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final selected = request.headers['x-organization-id'] as String?;
      switch (request.uri.path) {
        case '/v1/auth/me':
          return jsonResponse({
            'user': {'id': 'p1', 'fullName': 'Priya', 'phone': '9845012345'},
            'organizations': [
              {
                'id': 'a',
                'displayName': 'Ravi Roadways',
                'kind': 'CARRIER_FLEET',
                'kycStatus': 'APPROVED'
              },
              {'id': 'b', 'displayName': 'Sharma Textiles', 'kind': 'CUSTOMER'},
            ],
            if (selected != null)
              'principal': {
                'organizationId': selected,
                'roles': [selected == 'a' ? 'CARRIER' : 'SHIPPER'],
                'subrole': selected == 'a' ? 'OWNER' : 'CUSTOMER_ADMIN',
                'permissions': [
                  'load.read',
                  'notification.read',
                  'conversation.read'
                ],
              }
          });
        case '/v1/notifications/notice-1/open':
          return jsonResponse({'organizationId': 'b', 'shipmentId': 's9'});
        case '/v1/shipments/s9/conversation/timeline':
          return jsonResponse({
            'conversation': {'id': 's9'},
            'canSend': false,
            'items': [],
          });
      }
      return jsonResponse({});
    });
    api.selectOrganization('a');
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(AuthorizationSession.organizationId, 'b');
    expect(find.byType(ShipmentConversationScreen), findsOneWidget,
        reason: 'the tap opens the notice it was for, not Home');
    await tester.pumpWidget(const SizedBox());
  });
}
