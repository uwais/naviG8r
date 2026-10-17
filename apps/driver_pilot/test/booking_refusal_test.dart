import 'package:dio/dio.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a booking too heavy for the lane gets a sentence, not HTTP 400', () {
    api = Api('http://test');
    final tooHeavy = DioException(
      requestOptions: RequestOptions(path: '/shipments/book'),
      response: Response(
        requestOptions: RequestOptions(path: '/shipments/book'),
        statusCode: 400,
        data: {'error': 'insufficient_capacity'},
      ),
    );
    expect(formatApiError(tooHeavy),
        'This lane does not have room for that weight. Enter a lower weight, or choose another lane.');
  });
}
