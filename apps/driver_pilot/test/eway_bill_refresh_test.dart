// The e-way bill card inside the real shipper detail screen, while the screen refreshes itself every
// 15 seconds over a weak connection. Each test is a way a typed form or a save was lost on a phone.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/eway_bill_truck_form.dart';
import 'package:driver_pilot/organization_access.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

/// What the phone hears back: the shipment, a dropped connection, or a save held open until released.
class FakeServer {
  Map<String, dynamic> current = {
    ...shipment(),
    'updatedAtUtcMs': 1,
  };
  bool connectionDrops = false;
  bool saveConnectionDrops = false;
  Completer<void>? saveHeldOpen;
  Completer<void>? shipmentHeldOpen;

  /// The server answers the shipment request with this refusal instead, such as 403 or 404.
  int? refusalStatus;
  String refusalCode = '';
  final saves = <Map>[];

  Future<ResponseBody> handle(RequestOptions request) async {
    if (request.method == 'POST' && request.path.contains('/eway-bill')) {
      saves.add(request.data as Map);
      final held = saveHeldOpen;
      if (held != null) await held.future;
      if (saveConnectionDrops) {
        throw const HttpException(
            'Connection closed before full header was received');
      }
      current = {
        ...current,
        'ewayBill': {...savedBill, ...request.data as Map},
        'updatedAtUtcMs': 2,
      };
      return jsonResponse({'shipment': current});
    }
    if (connectionDrops) {
      throw const HttpException(
          'Connection closed before full header was received');
    }
    if (request.path == '/shipments/shipment-a') {
      final held = shipmentHeldOpen;
      if (held != null) await held.future;
      final status = refusalStatus;
      if (status != null) return jsonResponse({'error': refusalCode}, status);
      return jsonResponse({'shipment': current});
    }
    return jsonResponse({});
  }
}

Future<FakeServer> mountDetailScreen(WidgetTester tester) async {
  final server = FakeServer();
  api.dio.httpClientAdapter = MockApiAdapter(server.handle);
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const CustomerShipmentDetailScreen(shipmentId: 'shipment-a')));
  await tester.pumpAndSettle();
  return server;
}

/// Leaves the screen, so its 15 second timer stops before the test ends.
Future<void> leaveScreen(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Future<void> fillBillForm(WidgetTester tester) async {
  await tester.tap(find.text('Add e-way bill'));
  await tester.pump();
  await tester.enterText(
      field('E-way bill number (12 digits)'), '479056147955');
  await tester.enterText(
      field('GSTIN of whoever made the bill'), '29ABCDE1234F1Z5');
  await tester.enterText(field('Invoice number'), 'SYN/E2E/101');
  await tester.tap(find.text('Bill date: choose the date'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// The wall clock is not faked, so the time is matched by shape, not value.
final refreshFailedLine = RegExp(
    r'^Could not refresh, so this may be out of date\. Pull down to try again\. Last updated \d\d:\d\d$');

Future<void> waitForNextRefresh(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 15));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(signInAsShipper);

  testWidgets(
      'a refresh that fails keeps the shipment, the open form and what was typed, in plain words',
      (tester) async {
    final server = await mountDetailScreen(tester);
    await fillBillForm(tester);
    server.connectionDrops = true;
    await waitForNextRefresh(tester);
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text on screen');
    expect(find.textContaining(refreshFailedLine), findsOneWidget,
        reason:
            'one small line says the refresh failed and when it last worked');
    expect(find.text('SYN/E2E/101'), findsOneWidget,
        reason: 'the typed invoice number is still in the form');
    expect(find.text('Save e-way bill'), findsOneWidget,
        reason: 'the form is still open');
    server.connectionDrops = false;
    await waitForNextRefresh(tester);
    expect(find.textContaining('Could not refresh'), findsNothing,
        reason: 'the line goes once a refresh works again');
    expect(find.text('SYN/E2E/101'), findsOneWidget,
        reason: 'still typed after the next good refresh');
    await leaveScreen(tester);
  });

  for (final (status, code, sentence) in [
    (
      403,
      'forbidden',
      'You do not have permission for this action in the selected organization.'
    ),
    (
      404,
      'not_found',
      'This record is unavailable in the selected organization.'
    ),
  ]) {
    testWidgets(
        'a refresh the server refuses with $status clears the shipment and says why',
        (tester) async {
      final server = await mountDetailScreen(tester);
      await fillBillForm(tester);
      server.refusalStatus = status;
      server.refusalCode = code;
      await waitForNextRefresh(tester);
      expect(find.text(sentence), findsOneWidget,
          reason: 'the plain refusal, not the stale-data line');
      expect(find.textContaining('Could not refresh'), findsNothing);
      expect(find.text('E-way bill'), findsNothing,
          reason: 'a shipment this person may no longer see is not kept');
      expect(find.text('SYN/E2E/101'), findsNothing);
      await leaveScreen(tester);
    });
  }

  testWidgets(
      'a response that lands after a different person signed in is thrown away',
      (tester) async {
    final server = await mountDetailScreen(tester);
    server.shipmentHeldOpen = Completer<void>();
    server.current = {...server.current, 'externalLoadId': 'LATE-RESPONSE'};
    await tester.pump(const Duration(seconds: 15));
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'someone-else'};
    AuthorizationSession.principal = {
      'organizationId': 'shipper-b',
      'roles': ['SHIPPER'],
      'permissions': ['eway_bill.write']
    };
    server.shipmentHeldOpen!.complete();
    server.shipmentHeldOpen = null;
    await tester.pumpAndSettle();
    expect(find.textContaining('LATE-RESPONSE'), findsNothing,
        reason: 'the late response belongs to the person signed in before');
    expect(find.text('E-way bill'), findsNothing,
        reason: 'what the earlier person loaded is not left on screen either');
    await leaveScreen(tester);
  });

  testWidgets('a first load that fails says so in a plain sentence',
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((_) => throw const HttpException(
        'Connection closed before full header was received'));
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const CustomerShipmentDetailScreen(shipmentId: 'shipment-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text on screen');
    expect(
        find.text(
            'Could not load this shipment. Check your connection and pull down to try again.'),
        findsOneWidget,
        reason: 'a plain sentence with what to do');
    await leaveScreen(tester);
  });

  testWidgets(
      'a save still shows when a refresh fails while the save is on its way',
      (tester) async {
    final server = await mountDetailScreen(tester);
    await fillBillForm(tester);
    server.saveHeldOpen = Completer<void>();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pump();
    server.connectionDrops = true;
    await waitForNextRefresh(tester);
    server.saveHeldOpen!.complete();
    await tester.pumpAndSettle();
    expect(find.text('4790 5614 7955'), findsOneWidget,
        reason: 'the saved bill is shown');
    expect(find.text('Invoice number: SYN/E2E/101'), findsOneWidget,
        reason: 'with what was saved');
    await leaveScreen(tester);
  });

  testWidgets(
      'a save still shows when a good refresh with the old shipment lands while it is on its way',
      (tester) async {
    final server = await mountDetailScreen(tester);
    await fillBillForm(tester);
    server.saveHeldOpen = Completer<void>();
    await tester.tap(find.text('Save e-way bill'));
    await tester.pump();
    server.current = {...server.current, 'refreshed': true};
    await waitForNextRefresh(tester);
    server.saveHeldOpen!.complete();
    await tester.pumpAndSettle();
    expect(find.text('4790 5614 7955'), findsOneWidget,
        reason: 'the save is applied, not dropped because the screen rebuilt');
    await leaveScreen(tester);
  });

  testWidgets(
      'a save that loses its connection keeps the form and says so plainly',
      (tester) async {
    final server = await mountDetailScreen(tester);
    await fillBillForm(tester);
    server.saveConnectionDrops = true;
    await tester.tap(find.text('Save e-way bill'));
    await tester.pumpAndSettle();
    expect(server.saves, hasLength(1), reason: 'the save went out');
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text');
    expect(find.text('Could not save. Check your connection and try again.'),
        findsOneWidget,
        reason: 'a plain sentence with what to do');
    expect(find.text('SYN/E2E/101'), findsOneWidget,
        reason: 'what was typed is kept for the retry');
    await leaveScreen(tester);
  });

  testWidgets('going to the background and back keeps the open form',
      (tester) async {
    await mountDetailScreen(tester);
    await fillBillForm(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitForNextRefresh(tester);
    expect(find.text('SYN/E2E/101'), findsOneWidget,
        reason: 'the typed invoice number is still there');
    await leaveScreen(tester);
  });

  testWidgets(
      'coming back to the app when the sign-in check cannot reach the server keeps the open form',
      (tester) async {
    final server = FakeServer();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path == '/v1/auth/me') {
        throw const HttpException(
            'Connection closed before full header was received');
      }
      return server.handle(request);
    });
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const OrganizationAccess(
            child: CustomerShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pumpAndSettle();
    await fillBillForm(tester);
    // What main.dart does on every resume.
    unawaited(AuthorizationSession.refresh());
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text');
    expect(find.text('SYN/E2E/101'), findsOneWidget,
        reason: 'the typed invoice number is still there');
    await leaveScreen(tester);
  },
      // Fails today: a failed sign-in check drops every grant and OrganizationAccess replaces the
      // whole screen. Keeping grants through a network failure is a security call, not made here.
      skip: true);

  testWidgets('a tracking refresh that fails says so without raw text',
      (tester) async {
    final server = FakeServer();
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path.endsWith('/tracking')) {
        throw const HttpException(
            'Connection closed before full header was received');
      }
      return server.handle(request);
    });
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const CustomerShipmentDetailScreen(shipmentId: 'shipment-a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text');
    expect(find.text('E-way bill'), findsOneWidget,
        reason: 'the shipment and its card still show');
    await leaveScreen(tester);
  });

  testWidgets('a truck save that loses its connection says so plainly',
      (tester) async {
    api.dio.httpClientAdapter = MockApiAdapter((_) => throw const HttpException(
        'Connection closed before full header was received'));
    await mountCard(
        tester,
        EwayBillTruckForm(
            path: '/shipments/shipment-a/eway-bill/truck',
            clearsCheck: false,
            onSaved: (_) {},
            onCancel: () {}));
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck number'), 'KA01AB1234');
    await chooseTodayAtLastMinute(tester);
    await tester.tap(find.text('Save truck'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP'), findsNothing,
        reason: 'no raw exception text');
    expect(find.text('Could not save. Check your connection and try again.'),
        findsOneWidget,
        reason: 'a plain sentence with what to do');
    expect(find.text('KA01AB1234'), findsOneWidget,
        reason: 'the typed truck is kept');
  });

  testWidgets(
      'the carrier detail screen says when it cannot load, instead of a spinner forever',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    var connectionDrops = true;
    api.dio.httpClientAdapter = MockApiAdapter((_) {
      if (connectionDrops) {
        throw const HttpException(
            'Connection closed before full header was received');
      }
      return jsonResponse({
        'shipments': [
          shipment(bill: savedBill),
        ]
      });
    });
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    // Not pumpAndSettle: a spinner that never stops would never settle.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
        find.text(
            'Could not load this shipment. Check your connection and try again.'),
        findsOneWidget,
        reason: 'a plain sentence instead of a spinner that never stops');
    connectionDrops = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('1234 5678 9012'), findsOneWidget,
        reason: 'trying again loads the shipment and its bill');
  });

  testWidgets(
      'the carrier detail screen does not blame the connection when the server answered',
      (tester) async {
    signInAsCarrier(canAddTruck: true);
    api.dio.httpClientAdapter =
        MockApiAdapter((_) => jsonResponse({'error': 'internal'}, 500));
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Could not load this shipment.'), findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
  });

  group('the sentence under an e-way bill save', () {
    final request = RequestOptions(path: '/shipments/shipment-a/eway-bill');
    DioException answered(int status, Object? body) => DioException(
        requestOptions: request,
        response:
            Response(requestOptions: request, statusCode: status, data: body));

    test('is the server sentence when it wrote one', () {
      expect(
          ewayBillErrorSentence(
              answered(400, {'detail': 'The bill number must be 12 digits.'})),
          'The bill number must be 12 digits.');
    });

    test('asks to check the connection when the server never answered', () {
      expect(
          ewayBillErrorSentence(DioException(
              requestOptions: request, type: DioExceptionType.connectionError)),
          'Could not save. Check your connection and try again.');
    });

    test('is one fixed sentence for anything else, never raw text', () {
      for (final error in <Object>[
        answered(500, 'Internal Server Error <html>'),
        answered(403, {'error': 'forbidden'}),
        answered(401, {'error': 'unauthorized'}),
        answered(400, {'detail': ''}),
        StateError('unexpected'),
      ]) {
        expect(ewayBillErrorSentence(error),
            'Something went wrong. Please try again.');
      }
    });
  });
}
