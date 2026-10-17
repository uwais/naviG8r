// Booking refusals in words (17 Oct 2026). The Book screen's room-left line and carried-over weight were checked by
// hand on the emulator: the screen starts the payment and map plugins, which do not run in widget tests.
import 'package:dio/dio.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

DioException refusal(String code) => DioException(
      requestOptions: RequestOptions(path: '/shipments/book'),
      response: Response(
        requestOptions: RequestOptions(path: '/shipments/book'),
        statusCode: 400,
        data: {'error': code},
      ),
    );

void main() {
  setUp(() => api = Api('http://test'));

  test('a booking too heavy for the lane gets a sentence, not HTTP 400', () {
    expect(formatApiError(refusal('insufficient_capacity')),
        'This lane does not have room for that weight. Enter a lower weight, or choose another lane.');
  });

  test('a trip that stopped taking bookings gets a sentence, not HTTP 400', () {
    expect(formatApiError(refusal('anchor_trip_not_open')),
        'This trip is no longer taking bookings. Choose another lane.');
  });
}
