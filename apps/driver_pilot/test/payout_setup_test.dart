import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  DioException payoutSetupRefusal(Map<String, dynamic> body) {
    final options = RequestOptions(path: '/v1/pilot/carrier/payout-setup');
    return DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 400, data: body),
    );
  }

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

  test('a bank details format error shows the server sentence unchanged', () {
    const sentence =
        'IFSC must be 11 characters: four letters for the bank, then 0, then six letters or digits for the branch. Example: HDFC0000123.';
    final error = payoutSetupRefusal(
        {'error': 'invalid_payout_profile', 'detail': sentence, 'field': 'ifsc'});

    expect(formatApiError(error), sentence);
  });

  test(
      'a bank details error without a sentence falls back to the raw reply, and the app keeps its own sentences',
      () {
    // No sentence from the server: the raw reply shows, as before this change.
    expect(
        formatApiError(payoutSetupRefusal({'error': 'invalid_payout_profile'})),
        startsWith('HTTP 400'));
    // Errors on the app's own list keep its sentence, whatever detail they carry.
    expect(
        formatApiError(payoutSetupRefusal({'error': 'forbidden', 'detail': 'x'})),
        'You do not have permission for this action in the selected organization.');
  });

  test('the refused field is read only from a bank details refusal', () {
    expect(
        refusedBankDetailsField(payoutSetupRefusal(
            {'error': 'invalid_payout_profile', 'detail': 'x', 'field': 'ifsc'})),
        'ifsc');
    // Nothing to box when the reply names no field or is another error, when the
    // request got no reply at all (offline, timed out), or when the error is not from the network.
    expect(
        refusedBankDetailsField(
            payoutSetupRefusal({'error': 'invalid_payout_profile'})),
        isNull);
    expect(
        refusedBankDetailsField(
            payoutSetupRefusal({'error': 'forbidden', 'field': 'ifsc'})),
        isNull);
    expect(
        refusedBankDetailsField(DioException(
            requestOptions:
                RequestOptions(path: '/v1/pilot/carrier/payout-setup'),
            type: DioExceptionType.connectionError)),
        isNull);
    expect(refusedBankDetailsField(Exception('not from the network')), isNull);
  });

  const fieldLabels = {
    'accountHolderName': 'Account holder name',
    'ifsc': 'IFSC / bank identifier',
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
  });
}
