import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
