// Bug-hunt batch 2, the Messages screen: sending stays off until the server says it may send (X4), a
// refusal because messages closed says so and shows the closed banner at once (X3), and a timed check
// after more than a page of news starts over from the newest page instead of leaving a gap (R1).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipment_conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Answer {
  const _Answer(this.body, [this.status = 200]);
  final Map<String, dynamic> body;
  final int status;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.answer);
  final Future<_Answer> Function(RequestOptions) answer;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final reply = await answer(options);
    return ResponseBody.fromString(jsonEncode(reply.body), reply.status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }

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

void _signIn(String role, {String? subrole}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('https://example.test');
  api.selectOrganization('org-1');
  AuthorizationSession.user = {'id': 'user-1'};
  AuthorizationSession.principal = {
    'organizationId': 'org-1',
    'roles': [role],
    if (subrole != null) 'subrole': subrole,
    'permissions': ['conversation.read', 'conversation.send'],
  };
}

Future<void> _open(WidgetTester tester) => tester.pumpWidget(const MaterialApp(
    home: ShipmentConversationScreen(shipmentId: 'shipment-1')));

void main() {
  group('X4 sending starts off', () {
    testWidgets('no composer while the first load is out', (tester) async {
      _signIn('CARRIER');
      final gate = Completer<void>();
      api.dio.httpClientAdapter = _Adapter((request) async {
        await gate.future;
        return _Answer({
          'conversation': {
            'id': 'shipment-1',
            'replyPolicyVersion': 'delivery-accepted-v1',
            'replyUntilUtcMs': 1760000000000
          },
          'canSend': false,
          'items': [_message('m1', 'Delivered.')],
        });
      });
      await _open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(TextField), findsNothing,
          reason: 'the server has not said this reader may send');
      gate.complete();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no composer when the first load fails', (tester) async {
      _signIn('SHIPPER');
      api.dio.httpClientAdapter = _Adapter(
          (request) async => const _Answer({'error': 'unavailable'}, 503));
      await _open(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('X3 a send refused because messages closed', () {
    for (final (role, sentence) in [
      ('SHIPPER', 'Messages are closed for this shipment.'),
      ('CARRIER', 'Messages are closed for this booking.'),
    ]) {
      testWidgets('$role: says so and shows the closed banner at once',
          (tester) async {
        _signIn(role);
        var closed = false;
        api.dio.httpClientAdapter = _Adapter((request) async {
          if (request.path.endsWith('/messages')) {
            closed = true;
            return const _Answer({'error': 'conversation_read_only'}, 409);
          }
          if (request.path.endsWith('/timeline')) {
            return _Answer({
              'conversation': {'id': 'shipment-1'},
              'canSend': !closed,
              'items': [_message('m1', 'Delivered.')],
            });
          }
          return const _Answer({});
        });
        await _open(tester);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(find.byType(TextField), 'One more thing');
        await tester.tap(find.byTooltip('Send message'));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text(sentence), findsOneWidget);
        expect(find.text('You can read this conversation, but not reply.'),
            findsOneWidget,
            reason: 'the chat reloads, so the closed banner shows now');
        expect(find.byType(TextField), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }

    test('an unknown reader gets the plain sentence', () {
      AuthorizationSession.principal = null;
      final refusal = DioException(
        requestOptions: RequestOptions(path: '/messages'),
        response: Response(
            requestOptions: RequestOptions(path: '/messages'),
            statusCode: 409,
            data: {'error': 'conversation_read_only'}),
      );
      expect(formatApiError(refusal), 'Messages are closed.');
    });
  });

  testWidgets(
      'R1 a timed check with no message in common takes the newest page and its cursor',
      (tester) async {
    _signIn('SHIPPER');
    var newest = [_message('m10', 'Loaded at the pickup.')];
    var cursor = 'cursor-10';
    api.dio.httpClientAdapter = _Adapter((request) async {
      if (!request.path.endsWith('/timeline')) return const _Answer({});
      if (request.queryParameters['before'] == 'cursor-30') {
        return _Answer({
          'conversation': {'id': 'shipment-1'},
          'canSend': true,
          'items': [_message('m20', 'Reached Hosur.')],
          'nextBefore': 'cursor-20',
        });
      }
      return _Answer({
        'conversation': {'id': 'shipment-1'},
        'canSend': true,
        'items': newest,
        'nextBefore': cursor,
      });
    });
    await _open(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loaded at the pickup.'), findsOneWidget);

    // More than a page arrived since: the newest page holds none of the messages on screen.
    newest = [_message('m30', 'Reached Chennai.')];
    cursor = 'cursor-30';
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Loaded at the pickup.'), findsNothing,
        reason: 'the old list goes, so nothing sits next to it with a gap between');
    expect(find.text('Reached Chennai.'), findsOneWidget);

    await tester.tap(find.text('Show earlier messages'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Reached Hosur.'), findsOneWidget,
        reason: 'Show earlier messages goes on from the new page');
    await tester.pumpWidget(const SizedBox());
  });
}
