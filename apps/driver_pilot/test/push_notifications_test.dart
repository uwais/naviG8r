import 'package:flutter_test/flutter_test.dart';
import 'package:driver_pilot/push_notifications.dart';

void main() {
  group('PushPayload', () {
    test('accepts only the opaque routing contract', () {
      final payload = PushPayload.parse({
        'schemaVersion': '1',
        'notificationId': 'notice-123',
        'presentationKey': 'opaque-group-key',
        'shipmentId': 'must-not-be-used',
      }, requirePresentationKey: true);

      expect(payload?.notificationId, 'notice-123');
      expect(payload?.presentationKey, 'opaque-group-key');
    });

    test('rejects unknown schema versions and oversized IDs', () {
      expect(
        PushPayload.parse({'schemaVersion': '2', 'notificationId': 'notice'}),
        isNull,
      );
      expect(
        PushPayload.parse({
          'schemaVersion': '1',
          'notificationId': 'x' * 129,
        }),
        isNull,
      );
    });

    test('a Load Board push shown while the app is open says what it is about', () {
      expect(localPushWords(null),
          ('Shipment update', 'There is a new update about one of your shipments.'));
      expect(localPushWords('LOAD_BOARD'),
          ('New load on the Load Board', 'Open the Load Board to see it.'));
      expect(localPushWords('MY_LOADS'),
          ('A carrier made a route for your load', 'Open My loads to see it.'));
      expect(localPushWords('SOMETHING_ELSE'),
          ('Shipment update', 'There is a new update about one of your shipments.'));
    });

    test('foreground local notification uses the server replacement tag', () {
      final details = shipmentUpdateNotificationDetails('opaque-group-key');

      expect(shipmentUpdateNotificationId, 0);
      expect(details.tag, 'opaque-group-key');
      expect(details.channelId, 'shipment_updates');
    });
  });
}
