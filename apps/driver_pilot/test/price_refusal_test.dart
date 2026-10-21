import 'package:dio/dio.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException priceRefusal(String path, int status, String code) {
    final options = RequestOptions(path: path);
    return DioException(
      requestOptions: options,
      response: Response(
          requestOptions: options, statusCode: status, data: {'error': code}),
    );
  }

  test('a carrier company NaviG8r has not approved is told to contact NaviG8r',
      () {
    expect(
        formatApiError(priceRefusal(
            '/v1/pilot/rates/estimate', 403, 'company_not_approved')),
        'NaviG8r has to approve your company before you can see prices. Contact NaviG8r.');
  });

  test('a shipper company NaviG8r has not approved cannot quote or book', () {
    for (final path in ['/shipments/quote', '/shipments/book']) {
      expect(formatApiError(priceRefusal(path, 403, 'company_not_approved')),
          'NaviG8r has to approve your company before you can see prices or book. Contact NaviG8r.');
    }
  });

  test('a quote asked for by a login that is not a shipper says who can see prices',
      () {
    expect(
        formatApiError(
            priceRefusal('/shipments/quote', 403, 'quote_requires_shipper')),
        'Only a shipper company can see prices here.');
  });

  test('too many price requests asks the user to wait', () {
    expect(
        formatApiError(priceRefusal('/shipments/quote', 429, 'rate_limited')),
        'Too many requests. Please wait a while and try again.');
  });
}
