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

  test('an expired unpaid booking shows a plain line and where a held payment goes', () {
    expect(
        unpaidBookingExpiredLine({
          'status': 'FAILED_CARRIER_REFUNDED',
          'unpaidBookingExpiredAtUtcMs': 1767225600000,
        }),
        'This booking expired because it was not paid within 30 minutes. '
        'If your bank shows a payment, it comes back within 3 days of when you paid. '
        'Your bank may take 5-7 more working days.');
    expect(
        unpaidBookingExpiredLine({'status': 'FAILED_CARRIER_REFUNDED'}), null);
  });

  test('carrier screens show the expired sentence, not cancelled and refunded', () {
    for (final seesPayment in [true, false]) {
      expect(
          shipmentStatusLabel('FAILED_CARRIER_REFUNDED',
              seesPayment: seesPayment, unpaidBookingExpired: true),
          'This booking expired because it was not paid within 30 minutes.');
    }
    expect(shipmentStatusLabel('FAILED_CARRIER_REFUNDED'),
        'FAILED_CARRIER_REFUNDED');
  });

  test('a payment confirm after the booking expired shows the server sentence', () {
    DioException confirmError(Map<String, dynamic> data) => DioException(
          requestOptions: RequestOptions(path: '/v1/payments/razorpay/confirm'),
          response: Response(
            requestOptions:
                RequestOptions(path: '/v1/payments/razorpay/confirm'),
            statusCode: 409,
            data: data,
          ),
        );
    expect(
        bookingExpiredMessage(confirmError({
          'error': 'booking_expired_unpaid',
          'detail': 'This booking expired because it was not paid within 30 minutes.',
        })),
        'This booking expired because it was not paid within 30 minutes.');
    expect(
        bookingExpiredMessage(confirmError({'error': 'invalid_razorpay_signature'})),
        null);
    expect(bookingExpiredMessage(Exception('offline')), null);
  });

  test('the booking screen says how long the shipper has to pay', () {
    expect(payWithinWindowLine, 'Pay within 30 minutes, or this booking closes.');
  });

  test('checkout stops at 25 minutes, inside the 30 minutes the shipper is told', () {
    expect(razorpayCheckoutTimeoutSeconds, 25 * 60);
  });
}
