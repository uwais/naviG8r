import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/conversation_drafts.dart';
import 'package:driver_pilot/notification_center.dart';
import 'package:driver_pilot/pilot_api.dart';

class _CommunicationAdapter implements HttpClientAdapter {
  final List<String> calls = [];
  final List<Map<String, dynamic>> sentMessages = [];
  int messageCount = 0;
  Completer<void>? sendGate;
  bool failGatedSend = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (options.path == '/v1/notifications/shipments') {
      return _json({
        'shipments': [
          {
            'shipmentId': 'shipment-1',
            'shipmentReference': 'SHIPMENT',
            'latestAtUtcMs': 1791392400000,
            'unreadCount': 1
          },
        ],
        'unreadCount': 1,
        'nextBefore': null
      });
    }
    if (options.path.endsWith('/conversation/timeline') &&
        options.method == 'GET') {
      return _json({
        'conversation': {'id': 'shipment-1'},
        'items': [
          {
            'type': 'event',
            'id': 'event-1',
            'title': 'Load booked',
            'body': 'The carrier accepted this shipment.'
          },
          if (messageCount > 0)
            {
              'type': 'message',
              'id': 'message-1',
              'sequence': 1,
              'senderUserId': 'user-1',
              'body': 'Pickup confirmed.'
            }
        ],
        'canSend': true,
        'readWatermark': {'notificationSequence': 1, 'messageSequence': 1}
      });
    }
    if (options.path.endsWith('/conversation/read') &&
        options.method == 'POST') {
      return _json({'lastReadSequence': 1});
    }
    if (options.path.endsWith('/conversation/messages') &&
        options.method == 'GET') {
      return _json({
        'conversation': {'id': 'shipment-1'},
        'items': [],
        'canSend': true,
        'readWatermark': {'notificationSequence': 0, 'messageSequence': 0}
      });
    }
    if (options.path.endsWith('/conversation/messages') &&
        options.method == 'POST') {
      if (options.data is Map) {
        sentMessages.add(Map<String, dynamic>.from(options.data as Map));
      }
      if (sendGate != null) await sendGate!.future;
      if (failGatedSend) {
        throw DioException(
            requestOptions: options, message: 'Injected send failure');
      }
      messageCount++;
      return _json({
        'created': true,
        'message': {'id': 'message-1'}
      });
    }
    return _json({
      'notification': {'id': 'note-1'}
    });
  }

  ResponseBody _json(Object value) => ResponseBody.fromString(
        jsonEncode(value),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );

  @override
  void close({bool force = false}) {}
}

class _DelayedSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> values = {};
  Completer<void>? deleteGate;
  bool deleteStarted = false;

  @override
  Future<String?> read(
      {required String key, required Map<String, String> options}) async {
    return values[key];
  }

  @override
  Future<void> write(
      {required String key,
      required String value,
      required Map<String, String> options}) async {
    values[key] = value;
  }

  @override
  Future<bool> containsKey(
      {required String key, required Map<String, String> options}) async {
    return values.containsKey(key);
  }

  @override
  Future<void> delete(
      {required String key, required Map<String, String> options}) async {
    deleteStarted = true;
    final gate = deleteGate;
    deleteGate = null;
    if (gate != null) await gate.future;
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll(
      {required Map<String, String> options}) async {
    return values;
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }
}

void _configureApi(_CommunicationAdapter adapter) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
  api = Api('https://example.test');
  api.selectOrganization('org-1');
  api.dio.httpClientAdapter = adapter;
  AuthorizationSession.user = {'id': 'user-1'};
  AuthorizationSession.principal = {
    'organizationId': 'org-1',
    'roles': ['SHIPPER'],
    'permissions': [
      'notification.read',
      'conversation.read',
      'conversation.send'
    ],
  };
}

Future<void> _waitForSendRequest(
    WidgetTester tester, _CommunicationAdapter adapter) async {
  for (var attempt = 0;
      attempt < 20 && adapter.sentMessages.isEmpty;
      attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  test('draft key is isolated by user and active organization', () {
    expect(conversationDraftKey('user-1:org-a', 'shipment-1'),
        isNot(conversationDraftKey('user-2:org-a', 'shipment-1')));
    expect(conversationDraftKey('user-1:org-a', 'shipment-1'),
        isNot(conversationDraftKey('user-1:org-b', 'shipment-1')));
  });

  testWidgets('notification inbox groups activity once per shipment',
      (tester) async {
    final adapter = _CommunicationAdapter();
    _configureApi(adapter);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const NotificationInboxScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Shipment update'), findsOneWidget);
    expect(find.textContaining('New update'), findsOneWidget);
    expect(find.textContaining('Shipment SHIPMENT'), findsOneWidget);
    await tester.tap(find.text('Shipment update'));
    await tester.pumpAndSettle();
    expect(find.text('Load booked'), findsOneWidget);
    expect(find.text('The carrier accepted this shipment.'), findsOneWidget);
    expect(adapter.calls,
        contains('POST /v1/shipments/shipment-1/conversation/read'));
  });

  testWidgets(
      'conversation restores a scoped draft and sends with server acknowledgement',
      (tester) async {
    final adapter = _CommunicationAdapter();
    _configureApi(adapter);
    await ConversationDrafts.write(
        'user-1:org-1', 'shipment-1', 'Draft before open', 'stable-request-1');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const ShipmentConversationScreen(shipmentId: 'shipment-1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Draft before open'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Pickup confirmed.');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(adapter.calls,
        contains('POST /v1/shipments/shipment-1/conversation/messages'));
    expect(adapter.sentMessages.single['body'], 'Pickup confirmed.');
    expect(adapter.sentMessages.single['clientRequestId'],
        isNot('stable-request-1'));
    expect(find.text('Pickup confirmed.'), findsOneWidget);
    expect(await ConversationDrafts.read('user-1:org-1', 'shipment-1'), isNull);
  });

  testWidgets('typing during a successful send preserves the newer draft',
      (tester) async {
    final adapter = _CommunicationAdapter()..sendGate = Completer<void>();
    _configureApi(adapter);
    await ConversationDrafts.write(
        'user-1:org-1', 'shipment-1', 'First message', 'initial-send-key');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const ShipmentConversationScreen(shipmentId: 'shipment-1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'First message');
    tester
        .widget<IconButton>(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Send message',
        ))
        .onPressed!();
    await tester.pump();
    await _waitForSendRequest(tester, adapter);
    expect(adapter.calls,
        contains('POST /v1/shipments/shipment-1/conversation/messages'));
    expect(adapter.sentMessages, hasLength(1));

    await tester.enterText(find.byType(TextField), 'Newer draft');
    adapter.sendGate!.complete();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Newer draft'), findsOneWidget);
    expect(await ConversationDrafts.read('user-1:org-1', 'shipment-1'),
        containsPair('body', 'Newer draft'));
  });

  testWidgets('typing during a failed send preserves the newer draft and key',
      (tester) async {
    final adapter = _CommunicationAdapter()
      ..sendGate = Completer<void>()
      ..failGatedSend = true;
    _configureApi(adapter);
    await ConversationDrafts.write(
        'user-1:org-1', 'shipment-1', 'First message', 'initial-send-key');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const ShipmentConversationScreen(shipmentId: 'shipment-1'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First message'), findsOneWidget);
    tester
        .widget<IconButton>(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Send message',
        ))
        .onPressed!();
    await tester.pump();
    await _waitForSendRequest(tester, adapter);
    expect(adapter.calls,
        contains('POST /v1/shipments/shipment-1/conversation/messages'));
    expect(adapter.sentMessages, hasLength(1));
    final sentRequestId = adapter.sentMessages.single['clientRequestId'];

    await tester.enterText(find.byType(TextField), 'Newer draft');
    adapter.sendGate!.complete();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();

    expect(find.text('Newer draft'), findsOneWidget);
    final draft = await ConversationDrafts.read('user-1:org-1', 'shipment-1');
    expect(draft?['body'], 'Newer draft');
    expect(draft?['clientRequestId'], isNot(sentRequestId));
  });

  testWidgets(
      'typing during successful draft cleanup is saved after the delete',
      (tester) async {
    final adapter = _CommunicationAdapter()..sendGate = Completer<void>();
    final deleteGate = Completer<void>();
    final storage = _DelayedSecureStorage()..deleteGate = deleteGate;
    _configureApi(adapter);
    final previousStorage = FlutterSecureStoragePlatform.instance;
    FlutterSecureStoragePlatform.instance = storage;
    addTearDown(() {
      FlutterSecureStoragePlatform.instance = previousStorage;
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(splashFactory: NoSplash.splashFactory),
      home: const ShipmentConversationScreen(shipmentId: 'shipment-1'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First message');
    await tester.pump();
    expect(find.text('First message'), findsOneWidget);
    tester
        .widget<IconButton>(find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Send message',
        ))
        .onPressed!();
    await tester.pump();
    await _waitForSendRequest(tester, adapter);
    adapter.sendGate!.complete();

    for (var attempt = 0; attempt < 100 && !storage.deleteStarted; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(adapter.sentMessages, hasLength(1));
    expect(storage.deleteStarted, isTrue);
    await tester.enterText(find.byType(TextField), 'Draft during cleanup');
    deleteGate.complete();
    for (var attempt = 0;
        attempt < 20 &&
            adapter.calls
                    .where((call) =>
                        call ==
                        'GET /v1/shipments/shipment-1/conversation/timeline')
                    .length <
                2;
        attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pumpAndSettle();

    expect(find.text('Draft during cleanup'), findsOneWidget);
    expect(await ConversationDrafts.read('user-1:org-1', 'shipment-1'),
        containsPair('body', 'Draft during cleanup'));
  });
}
