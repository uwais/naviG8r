import 'package:dio/dio.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException payoutSetupRefusal(Map<String, dynamic> body) {
    final options = RequestOptions(path: '/v1/pilot/carrier/payout-setup');
    return DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 400, data: body),
    );
  }

  test('a bank details format error shows the server sentence unchanged', () {
    const sentence =
        'IFSC must be 11 characters: four letters for the bank, then 0, then six letters or digits for the branch. Example: HDFC0000123.';
    final error = payoutSetupRefusal({
      'error': 'invalid_payout_profile',
      'detail': sentence,
      'field': 'ifsc'
    });

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
        formatApiError(
            payoutSetupRefusal({'error': 'forbidden', 'detail': 'x'})),
        'You do not have permission for this action in the selected organization.');
  });

  test('the refused field is read only from a bank details refusal', () {
    expect(
        refusedBankDetailsField(payoutSetupRefusal({
          'error': 'invalid_payout_profile',
          'detail': 'x',
          'field': 'ifsc'
        })),
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
}
