import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException payoutSetupRefusal(Map<String, dynamic> body) {
    final options = RequestOptions(path: '/v1/pilot/carrier/payout-setup');
    return DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 400, data: body),
    );
  }

  setUp(() {
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
}
