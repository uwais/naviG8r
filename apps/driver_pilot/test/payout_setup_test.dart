import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    api = Api('http://test');
    AuthorizationSession.clear();
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['bank_account.create_token'],
    };
  });

  testWidgets('the bank details screen promises no check it does not make',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DriverPayoutSetupScreen())));

    expect(find.text('Save bank details'), findsOneWidget);
    expect(
        find.text(
            'Delivery payments go to this account. Check the details before saving.'),
        findsOneWidget);
    expect(find.textContaining('verify'), findsNothing);
    expect(find.textContaining('KYC'), findsNothing);
  });

  test('a bank details format error reads as the server wrote it', () {
    const sentence =
        'IFSC must be 11 characters: four letters for the bank, then 0, then six letters or digits for the branch. Example: HDFC0000123.';
    final options =
        RequestOptions(path: '/v1/pilot/carrier/payout-setup');
    final error = DioException(
      requestOptions: options,
      response: Response(
        requestOptions: options,
        statusCode: 400,
        data: {
          'error': 'invalid_payout_profile',
          'detail': sentence,
          'field': 'ifsc'
        },
      ),
    );

    expect(formatApiError(error), sentence);
  });
}
