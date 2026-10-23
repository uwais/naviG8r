// Owner, 22 Oct 2026: a message says who it is from, by the name the server gives, and the Messages
// screen names its shipment by route and date.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipment_conversation.dart';
import 'package:driver_pilot/ui/format.dart';

class _TimelineAdapter implements HttpClientAdapter {
  _TimelineAdapter(this.timeline);
  final Map<String, dynamic> timeline;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = options.path.endsWith('/conversation/timeline')
        ? timeline
        : {'lastReadSequence': 1};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _message(String id, String? senderUserId, String body,
        {String? senderLabel}) =>
    {
      'type': 'message',
      'id': id,
      'sequence': 1,
      if (senderUserId != null) 'senderUserId': senderUserId,
      if (senderLabel != null) 'senderLabel': senderLabel,
      'body': body,
    };

Future<void> _open(WidgetTester tester, Map<String, dynamic> timeline,
    {String role = 'SHIPPER', Map<String, dynamic> user = const {'id': 'user-1'}}) async {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
  api = Api('https://example.test');
  api.selectOrganization('org-1');
  api.dio.httpClientAdapter = _TimelineAdapter({
    'conversation': {'id': 'shipment-1'},
    'canSend': true,
    'readWatermark': {'notificationSequence': 0, 'messageSequence': 1},
    ...timeline,
  });
  AuthorizationSession.user = user;
  AuthorizationSession.principal = {
    'organizationId': 'org-1',
    'roles': [role],
    'permissions': [
      'notification.read',
      'conversation.read',
      'conversation.send'
    ],
  };
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: const ShipmentConversationScreen(shipmentId: 'shipment-1'),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'each message shows who sent it, and the title names the shipment',
      (tester) async {
    await _open(tester, {
      'shipmentSummary': {
        'originCity': 'Hoskote',
        'destCity': 'Kolar',
        'windowStart': '2026-10-18',
      },
      'items': [
        _message('m1', 'driver-1', 'Reached the pickup.',
            senderLabel: 'Synthetic Carrier A · Driver'),
        _message('m2', 'user-1', 'Gate 2, please.', senderLabel: 'You'),
      ],
    });
    expect(find.text('Messages'), findsOneWidget);
    expect(find.textContaining('Hoskote to Kolar, 18 Oct'), findsOneWidget);
    expect(find.text('Synthetic Carrier A · Driver'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Shipment participant'), findsNothing);
  });

  testWidgets('an older server with no label or summary keeps the old words',
      (tester) async {
    await _open(tester, {
      'items': [_message('m1', 'driver-1', 'Reached the pickup.')],
    });
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Shipment participant'), findsOneWidget);
    expect(find.textContaining(' to '), findsNothing,
        reason: 'no route line when the server sends none');
  });

  testWidgets("another company's message with no sender id is never You",
      (tester) async {
    await _open(tester, {
      'items': [
        _message('m1', null, 'Reached the pickup.',
            senderLabel: 'Synthetic Carrier A · Driver'),
      ],
    }, user: const {});
    expect(find.text('Synthetic Carrier A · Driver'), findsOneWidget);
    expect(find.text('You'), findsNothing);
  });

  group('Closed when the shipper accepted delivery', () {
    final acceptedAt = DateTime.utc(2026, 10, 20, 6);
    final accepted = {
      'conversation': {
        'id': 'shipment-1',
        'replyPolicyVersion': 'delivery-accepted-v1',
        'replyUntilUtcMs': acceptedAt.millisecondsSinceEpoch,
      },
      'canSend': false,
      'items': <Map<String, dynamic>>[],
    };

    testWidgets('the shipper is told they closed it, and on which day',
        (tester) async {
      await _open(tester, accepted);
      expect(
          find.text(
              'Messages closed when you accepted delivery on ${formatDate(acceptedAt)}. You can still read them.'),
          findsOneWidget);
    });

    testWidgets('the carrier is told the shipper closed it', (tester) async {
      await _open(tester, accepted, role: 'CARRIER');
      expect(
          find.text(
              'Messages closed when the shipper accepted delivery on ${formatDate(acceptedAt)}. You can still read them.'),
          findsOneWidget);
    });

    testWidgets('a chat closed for another reason keeps the old line',
        (tester) async {
      await _open(tester, {
        'conversation': {
          'id': 'shipment-1',
          'replyPolicyVersion': 'support-window-v1',
          'replyUntilUtcMs': acceptedAt.millisecondsSinceEpoch,
        },
        'canSend': false,
        'items': <Map<String, dynamic>>[],
      });
      expect(find.text('You can read this conversation, but not reply.'),
          findsOneWidget);
    });
  });
}
