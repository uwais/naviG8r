import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['bank_account.create_token'],
    };
  });

  testWidgets(
      'the bank details screen has the agreed button and line, and no verify, KYC or "real" wording',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DriverPayoutSetupScreen())));

    expect(find.text('Save bank details'), findsOneWidget);
    expect(
        find.text(
            'Delivery payments go to this account. Check the details before saving.'),
        findsOneWidget);
    expect(find.textContaining(RegExp('verif|kyc', caseSensitive: false)),
        findsNothing);
    // Production always needs the account number, and "real" exposed the test servers.
    expect(find.textContaining(RegExp(r'\breal\b', caseSensitive: false)),
        findsNothing);
  });

  const fieldLabels = {
    'accountHolderName': 'Account holder name',
    'ifsc': 'IFSC code',
    'accountNumber': 'Bank account number',
  };

  // The box is the field's own border, at rest and with the cursor in it, so read both from the TextField the screen builds.
  List<InputBorder?> boxOf(WidgetTester tester, String field) {
    final decoration = tester
        .widget<TextField>(find.widgetWithText(TextField, fieldLabels[field]!))
        .decoration!;
    return [decoration.enabledBorder, decoration.focusedBorder];
  }

  Future<void> openScreen(WidgetTester tester) => tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(body: DriverPayoutSetupScreen())));

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save bank details'));
    await tester.pumpAndSettle();
  }

  ResponseBody refusal(String field) => jsonResponse(
      {'error': 'invalid_payout_profile', 'detail': 'Sentence.', 'field': field},
      400);

  // The box is the theme's own field shape, drawn 2 pixels wide in the error red.
  final themedBox = DriverTheme.theme().inputDecorationTheme.border!.copyWith(
      borderSide:
          BorderSide(color: DriverTheme.theme().colorScheme.error, width: 2));
  final redBox = [themedBox, themedBox];
  const noBox = <InputBorder?>[null, null];
  final sentenceInMessage = find.descendant(
      of: find.byType(SnackBar), matching: find.text('Sentence.'));

  // The refusal message covers the Save button for a few seconds; wait for it to go.
  Future<void> waitForMessageToGo(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  // What the owner reads when a save works but text was typed after the tap.
  const serverLine = 'Bank account added.';
  const changedAfterSaveOpening = 'You changed something after you tapped Save.';
  const changedAfterSave = '$changedAfterSaveOpening '
      'We sent the details from before. '
      'Tap Save again to send the change.';

  fieldLabels.forEach((field, label) {
    testWidgets(
        'a refused $field gets the red box and no other field does; typing in another field keeps it, typing in it clears it',
        (tester) async {
      api.dio.httpClientAdapter = MockApiAdapter((_) => refusal(field));
      await openScreen(tester);
      // Typing before the save does not stop the box; only typing after it is sent does.
      await tester.enterText(
          find.widgetWithText(TextField, fieldLabels['accountHolderName']!),
          'Test Owner');
      await save(tester);

      // The sentence still shows in the message; the box only points at the field.
      expect(sentenceInMessage, findsOneWidget);
      for (final name in fieldLabels.keys) {
        expect(boxOf(tester, name), name == field ? redBox : noBox,
            reason: name);
      }
      final another = fieldLabels.keys.firstWhere((name) => name != field);
      await tester.enterText(
          find.widgetWithText(TextField, fieldLabels[another]!), 'x');
      await tester.pump();
      expect(boxOf(tester, field), redBox);
      await tester.enterText(find.widgetWithText(TextField, label), 'x');
      await tester.pump();
      expect(boxOf(tester, field), noBox);
    });
  });

  testWidgets(
      'the box moves to the field the server refuses next, and goes when a reply names no field',
      (tester) async {
    var next = () => refusal('accountNumber');
    api.dio.httpClientAdapter = MockApiAdapter((_) => next());
    await openScreen(tester);
    await save(tester);
    expect(boxOf(tester, 'accountNumber'), redBox);
    await waitForMessageToGo(tester);

    next = () => refusal('ifsc');
    await save(tester);
    expect(boxOf(tester, 'ifsc'), redBox);
    expect(boxOf(tester, 'accountNumber'), noBox);
    await waitForMessageToGo(tester);

    next = () => jsonResponse({'error': 'forbidden'}, 403);
    await save(tester);
    for (final name in fieldLabels.keys) {
      expect(boxOf(tester, name), noBox, reason: name);
    }
  });

  testWidgets(
      'a refusal that arrives after the owner typed over a field boxes nothing, and the message still shows',
      (tester) async {
    final reply = Completer<ResponseBody>();
    api.dio.httpClientAdapter = MockApiAdapter((_) => reply.future);
    await openScreen(tester);
    await tester.tap(find.text('Save bank details'));
    await tester.pump();

    // The owner types in the account number while the save is in flight.
    await tester.enterText(
        find.widgetWithText(TextField, fieldLabels['accountNumber']!),
        '123456789');
    reply.complete(refusal('accountNumber'));
    await tester.pumpAndSettle();

    for (final name in fieldLabels.keys) {
      expect(boxOf(tester, name), noBox, reason: name);
    }
    expect(sentenceInMessage, findsOneWidget);
    // The line for text typed after a save that worked does not belong on a refusal.
    expect(find.textContaining(changedAfterSaveOpening), findsNothing);
  });

  // A save that works goes on to the payout history, so these tests give the screen a router with that page.
  Future<void> openScreenWithHistory(WidgetTester tester) =>
      tester.pumpWidget(MaterialApp.router(
          theme: DriverTheme.theme(),
          routerConfig: GoRouter(initialLocation: '/setup', routes: [
            GoRoute(
                path: '/setup',
                builder: (_, __) =>
                    const Scaffold(body: DriverPayoutSetupScreen())),
            GoRoute(
                path: '/driver/payout-history',
                builder: (_, __) =>
                    const Scaffold(body: Text('Payout history page'))),
          ])));

  Future<void> typeInto(WidgetTester tester, String field, String text) =>
      tester.enterText(
          find.widgetWithText(TextField, fieldLabels[field]!), text);

  const accountNumberAtTap = '111122223333';
  const accountNumberTypedAfter = '111122224444';

  Future<void> fillInBankDetails(WidgetTester tester,
      {String ifsc = 'HDFC0000123'}) async {
    await typeInto(tester, 'accountHolderName', 'Test Owner');
    await typeInto(tester, 'ifsc', ifsc);
    await typeInto(tester, 'accountNumber', accountNumberAtTap);
  }

  Future<void> tapSaveWithoutWaiting(WidgetTester tester) async {
    await tester.tap(find.text('Save bank details'));
    await tester.pump();
  }

  // What the server says about the signed-in owner; the screen refreshes it after every save that works.
  ResponseBody ownerSession() => jsonResponse({
        'user': {'id': 'owner-a'},
        'organizations': [
          {'id': 'carrier-a'}
        ],
        'principal': {
          'organizationId': 'carrier-a',
          'roles': ['CARRIER'],
          'permissions': ['bank_account.create_token'],
        },
      });

  const payoutSetupPath = '/v1/pilot/carrier/payout-setup';

  // The save gets the reply onSave gives; everything else the screen asks for is the signed-in owner.
  void fakeServer(FutureOr<ResponseBody> Function(RequestOptions) onSave) {
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        request.path == payoutSetupPath ? onSave(request) : ownerSession());
  }

  // The save request and the session refresh after it are the two waits the owner can type during.
  const duringSave = 'the save request';
  const duringRefresh = 'the session refresh that follows it';
  for (final moment in [duringSave, duringRefresh]) {
    testWidgets(
        'text typed during $moment stays on the screen after a save that works, says what was sent, and sends the text from the tap',
        (tester) async {
      final saveReply = Completer<ResponseBody>();
      final sessionReply = Completer<ResponseBody>();
      final sent = <Object?>[];
      var sessionAsked = false;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.path == payoutSetupPath) {
          sent.add(request.data);
          return saveReply.future;
        }
        sessionAsked = true;
        return sessionReply.future;
      });
      await openScreenWithHistory(tester);
      await fillInBankDetails(tester);
      await tapSaveWithoutWaiting(tester);

      if (moment == duringSave) {
        await typeInto(tester, 'accountNumber', accountNumberTypedAfter);
        saveReply.complete(jsonResponse({'message': serverLine}));
      } else {
        saveReply.complete(jsonResponse({'message': serverLine}));
        // The refresh is asked for a moment after the save is answered.
        for (var turn = 0; turn < 20 && !sessionAsked; turn++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(sessionAsked, isTrue, reason: 'the refresh was never asked for');
        await typeInto(tester, 'accountNumber', accountNumberTypedAfter);
      }
      sessionReply.complete(ownerSession());
      await tester.pumpAndSettle();

      // The line is true: the server got the text from the tap, not the text typed after it.
      expect(sent, [
        {
          'orgId': 'carrier-a',
          'accountHolderName': 'Test Owner',
          'ifsc': 'HDFC0000123',
          'accountNumber': accountNumberAtTap,
        }
      ]);
      // The server's own line stays, with the new one under it.
      final message = find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('$serverLine\n$changedAfterSave'));
      expect(message, findsOneWidget,
          reason:
              'the owner must be told the text typed after the tap was not sent');
      // Four seconds is too short to read it.
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          greaterThan(const Duration(seconds: 4)));
      expect(find.text('Close'), findsOneWidget,
          reason:
              'the message covers the Save button, so it needs a way to close');
      expect(find.text('Payout history page'), findsNothing,
          reason: 'the screen no longer matches what was saved, so it stays');
      expect(find.text('Save bank details'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(
                  find.widgetWithText(TextField, fieldLabels['accountNumber']!))
              .controller!
              .text,
          accountNumberTypedAfter,
          reason: 'the text typed after the tap is still there to be saved');
    });
  }

  const nameAndIfscTypedAfterTap = {
    'accountHolderName': 'Other Owner',
    'ifsc': 'HDFC0000999',
  };
  nameAndIfscTypedAfterTap.forEach((field, text) {
    testWidgets(
        'text typed in $field after the tap is told about too, and does not open the payout history',
        (tester) async {
      final saveReply = Completer<ResponseBody>();
      fakeServer((_) => saveReply.future);
      await openScreenWithHistory(tester);
      await fillInBankDetails(tester);
      await tapSaveWithoutWaiting(tester);
      await typeInto(tester, field, text);
      saveReply.complete(jsonResponse({'message': serverLine}));
      await tester.pumpAndSettle();

      expect(find.textContaining(changedAfterSaveOpening), findsOneWidget);
      expect(find.text('Payout history page'), findsNothing);
    });
  });

  testWidgets(
      'a save that works with nothing typed after the tap goes to the payout history with only the server line',
      (tester) async {
    fakeServer((_) => jsonResponse({'message': serverLine}));
    await openScreenWithHistory(tester);
    // Typing before the tap does not count; only typing after it does.
    await fillInBankDetails(tester);
    await save(tester);

    expect(find.text('Payout history page'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text(serverLine)),
        findsOneWidget);
    expect(find.textContaining(changedAfterSaveOpening), findsNothing);
  });

  testWidgets(
      'typing that leaves what was sent as it was (a digit typed and deleted, a space after the number) goes to the payout history',
      (tester) async {
    final saveReply = Completer<ResponseBody>();
    fakeServer((_) => saveReply.future);
    await openScreenWithHistory(tester);
    await fillInBankDetails(tester);
    await tapSaveWithoutWaiting(tester);

    // The app trims the number before sending, so the space is not a change.
    await typeInto(tester, 'accountNumber', '${accountNumberAtTap}4');
    await typeInto(tester, 'accountNumber', '$accountNumberAtTap ');
    saveReply.complete(jsonResponse({'message': serverLine}));
    await tester.pumpAndSettle();

    // Staying here would invite a second save: another RazorpayX contact for the same details.
    expect(find.text('Payout history page'), findsOneWidget,
        reason:
            'what was sent still matches the screen, so there is nothing to warn about');
    expect(find.textContaining(changedAfterSaveOpening), findsNothing);
  });

  // The server upper-cases the IFSC, so retyping it in the other case sends it nothing new.
  const ifscRetypedInOtherCase = {
    'HDFC0000123': 'hdfc0000123',
    'hdfc0000123': 'HDFC0000123',
  };
  ifscRetypedInOtherCase.forEach((ifscAtTap, ifscRetyped) {
    testWidgets(
        'the IFSC tapped as $ifscAtTap and retyped as $ifscRetyped goes to the payout history',
        (tester) async {
      final saveReply = Completer<ResponseBody>();
      fakeServer((_) => saveReply.future);
      await openScreenWithHistory(tester);
      await fillInBankDetails(tester, ifsc: ifscAtTap);
      await tapSaveWithoutWaiting(tester);
      await typeInto(tester, 'ifsc', ifscRetyped);
      saveReply.complete(jsonResponse({'message': serverLine}));
      await tester.pumpAndSettle();

      expect(find.text('Payout history page'), findsOneWidget,
          reason:
              'the server holds the same IFSC either way, so there is nothing to warn about');
      expect(find.textContaining(changedAfterSaveOpening), findsNothing);
    });
  });

  testWidgets(
      'Close closes the message, and the second tap on Save sends the text typed after the first',
      (tester) async {
    final firstReply = Completer<ResponseBody>();
    final accountNumbersSent = <Object?>[];
    fakeServer((request) {
      accountNumbersSent.add((request.data as Map)['accountNumber']);
      return accountNumbersSent.length == 1
          ? firstReply.future
          : Future.value(jsonResponse({'message': serverLine}));
    });
    await openScreenWithHistory(tester);
    await fillInBankDetails(tester);
    await tapSaveWithoutWaiting(tester);
    await typeInto(tester, 'accountNumber', accountNumberTypedAfter);
    firstReply.complete(jsonResponse({'message': serverLine}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing,
        reason: 'the message covers Save until it is closed');

    await save(tester);
    expect(accountNumbersSent, [accountNumberAtTap, accountNumberTypedAfter],
        reason:
            'the message promises that tapping Save again sends the change');
    expect(find.text('Payout history page'), findsOneWidget);
  });

  testWidgets(
      'a screen reader can reach Save under the message: the old message goes and the new save shows its own line',
      (tester) async {
    // With a screen reader on, a message that has a button stays up until it is closed.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final firstReply = Completer<ResponseBody>();
    var saves = 0;
    fakeServer((_) => ++saves == 1
        ? firstReply.future
        : Future.value(jsonResponse({'message': serverLine})));
    await openScreenWithHistory(tester);
    await fillInBankDetails(tester);
    await tapSaveWithoutWaiting(tester);
    await typeInto(tester, 'accountNumber', accountNumberTypedAfter);
    firstReply.complete(jsonResponse({'message': serverLine}));
    await tester.pumpAndSettle();
    expect(find.textContaining(changedAfterSaveOpening), findsOneWidget);

    // The bar hides the Save button from a finger, not from a screen reader.
    tester.semantics.performAction(
        find.semantics.byLabel('Save bank details'), SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(find.text('Payout history page'), findsOneWidget);
    expect(find.textContaining(changedAfterSaveOpening), findsNothing,
        reason: 'the old message is about a save that is over');
    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.text(serverLine)),
        findsOneWidget,
        reason:
            'the new save shows its own line, not one queued behind the old message');
  });
}
