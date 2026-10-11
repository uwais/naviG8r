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
    // No field, another error, or no reply from the server: nothing to box.
    expect(
        refusedBankDetailsField(
            payoutSetupRefusal({'error': 'invalid_payout_profile'})),
        isNull);
    expect(
        refusedBankDetailsField(
            payoutSetupRefusal({'error': 'forbidden', 'field': 'ifsc'})),
        isNull);
    expect(refusedBankDetailsField(Exception('offline')), isNull);
  });

  const fieldLabels = {
    'accountHolderName': 'Account holder name',
    'ifsc': 'IFSC / bank identifier',
    'accountNumber': 'Bank account number',
  };

  // The box is the field's own border, at rest and with the cursor in it, so read both from the TextField the screen builds.
  List<BorderSide?> boxOf(WidgetTester tester, String field) {
    final decoration = tester
        .widget<TextField>(find.widgetWithText(TextField, fieldLabels[field]!))
        .decoration!;
    return [
      decoration.enabledBorder?.borderSide,
      decoration.focusedBorder?.borderSide
    ];
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

  final redSide =
      BorderSide(color: DriverTheme.theme().colorScheme.error, width: 2);
  final redBox = [redSide, redSide];
  const noBox = <BorderSide?>[null, null];

  fieldLabels.forEach((field, label) {
    testWidgets(
        'a refused $field gets the red box and no other field does; typing in another field keeps it, typing in it clears it',
        (tester) async {
      api.dio.httpClientAdapter = MockApiAdapter((_) => refusal(field));
      await openScreen(tester);
      await save(tester);

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

  testWidgets('the box moves to the field the server refuses next',
      (tester) async {
    var refused = 'accountNumber';
    api.dio.httpClientAdapter = MockApiAdapter((_) => refusal(refused));
    await openScreen(tester);
    await save(tester);
    expect(boxOf(tester, 'accountNumber'), redBox);
    // The refusal message covers the Save button for a few seconds; wait for it to go.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    refused = 'ifsc';
    await save(tester);
    expect(boxOf(tester, 'ifsc'), redBox);
    expect(boxOf(tester, 'accountNumber'), noBox);
  });
}
