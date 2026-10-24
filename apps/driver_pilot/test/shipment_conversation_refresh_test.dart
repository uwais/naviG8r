// The Messages screen checks for new messages every 30 seconds. Hunt, 23 Oct 2026: that check replaced
// the list with the newest page, so earlier messages the reader had loaded were gone.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipment_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _TimelineAdapter implements HttpClientAdapter {
  _TimelineAdapter(this.answer);
  final Map<String, dynamic> Function(RequestOptions) answer;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(answer(options)), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _message(String id, String body) => {
      'type': 'message',
      'id': id,
      'sequence': 1,
      'senderLabel': 'Ravi Roadways · Office',
      'body': body,
    };

void main() {
  testWidgets('the timed check keeps the earlier messages loaded and adds the new one',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
    api = Api('https://example.test');
    api.selectOrganization('org-1');
    AuthorizationSession.user = {'id': 'user-1'};
    AuthorizationSession.principal = {
      'organizationId': 'org-1',
      'roles': ['SHIPPER'],
      'permissions': ['conversation.read', 'conversation.send'],
    };
    var newest = [_message('m1', 'Loaded at the pickup.')];
    api.dio.httpClientAdapter = _TimelineAdapter((request) {
      if (!request.path.endsWith('/timeline')) return {};
      final older = request.queryParameters['before'] != null;
      return {
        'conversation': {'id': 'shipment-1'},
        'canSend': true,
        'items': older ? [_message('m0', 'Reached the pickup.')] : newest,
        'nextBefore': older ? null : 'cursor-1',
      };
    });
    await tester.pumpWidget(const MaterialApp(
        home: ShipmentConversationScreen(shipmentId: 'shipment-1')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Show earlier messages'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Reached the pickup.'), findsOneWidget);

    newest = [_message('m1', 'Loaded at the pickup.'), _message('m2', 'Left for Chennai.')];
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Reached the pickup.'), findsOneWidget,
        reason: 'the earlier message the reader loaded stays');
    expect(find.text('Left for Chennai.'), findsOneWidget,
        reason: 'the new message is added');
    expect(find.text('Loaded at the pickup.'), findsOneWidget,
        reason: 'a message in both pages shows once');
    expect(find.text('Show earlier messages'), findsNothing,
        reason: 'everything earlier is already loaded');
    await tester.pumpWidget(const SizedBox());
  });
}
