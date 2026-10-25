import 'package:dio/dio.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException signUpError(int statusCode, Map<String, dynamic> data) =>
      DioException(
        requestOptions: RequestOptions(path: '/v1/pilot/customer/register'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/pilot/customer/register'),
          statusCode: statusCode,
          data: data,
        ),
      );

  test('too many sign-up tries shows a plain sentence', () {
    api = Api('http://test');
    expect(
        formatApiError(signUpError(429, {'error': 'sign_up_rate_limited'})),
        'Too many sign-up tries. Please wait a few minutes and try again.');
  });

  test('an over-long sign-up field shows the server sentence', () {
    api = Api('http://test');
    for (final code in [
      'invalid_fullName',
      'invalid_orgDisplayName',
      'invalid_phone'
    ]) {
      expect(
          formatApiError(signUpError(400, {
            'error': code,
            'detail': 'A name can have at most 100 characters.'
          })),
          'A name can have at most 100 characters.');
    }
  });

  test('normalizes a fully qualified API URL', () {
    expect(
        normalizeApiBaseUrl(' http://10.0.2.2:3000 '), 'http://10.0.2.2:3000');
  });

  test('repairs a duplicated HTTP scheme from a build define', () {
    expect(normalizeApiBaseUrl('http://http://10.0.2.2:3000'),
        'http://10.0.2.2:3000');
  });

  test('adds HTTP for a bare host and port', () {
    expect(normalizeApiBaseUrl('10.0.2.2:3000'), 'http://10.0.2.2:3000');
  });

  test('preserves a web relative API path', () {
    expect(normalizeApiBaseUrl('/api'), '/api');
  });

  test('an expired unpaid booking shows a plain line', () {
    expect(
        unpaidBookingExpiredLine({
          'status': 'FAILED_CARRIER_REFUNDED',
          'unpaidBookingExpiredAtUtcMs': 1767225600000,
        }),
        'This booking expired because it was not paid within 30 minutes.');
    expect(
        unpaidBookingExpiredLine({'status': 'FAILED_CARRIER_REFUNDED'}), null);
  });
}
