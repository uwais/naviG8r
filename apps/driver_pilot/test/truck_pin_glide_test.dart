// Rishabh, 20 Oct 2026: the truck pin on the shipper's tracking map glides to a new position
// over about a second and a half, instead of jumping.
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/shipper_shipment_app.dart';

LatLng _truckPin(WidgetTester tester) => tester
    .widget<GoogleMap>(find.byType(GoogleMap))
    .markers
    .firstWhere((marker) => marker.markerId.value == 'track_driver')
    .position;

Map<String, dynamic> _tracking(double lat, double lng) => {
      'trip': {
        ...lane(status: 'IN_PROGRESS'),
        'origin': {'lat': 12.97, 'lng': 77.59},
        'destination': {'lat': 13.08, 'lng': 80.27},
      },
      'liveLocation': {'lat': lat, 'lng': lng},
      'isLive': true,
    };

void main() {
  testWidgets('a new truck position glides from the old one, then stops on it',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/shipments/shp_9f2c41');
    server.answers['/shipments/shp_9f2c41'] = {'shipment': booking()};
    server.answers['/shipments/shp_9f2c41/tracking'] = _tracking(12.0, 78.0);
    await tester.pumpAndSettle();
    expect(_truckPin(tester), const LatLng(12.0, 78.0),
        reason: 'the first position shows at once');

    server.answers['/shipments/shp_9f2c41/tracking'] = _tracking(13.0, 79.0);
    await tester.tap(find.byTooltip('Refresh'));
    // A frame at a time until the pin first moves: the new position arrives a few frames after the tap.
    for (var frame = 0;
        frame < 40 && _truckPin(tester) == const LatLng(12.0, 78.0);
        frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final halfway = _truckPin(tester);
    expect(halfway.latitude, inExclusiveRange(12.0, 13.0),
        reason: 'part way there, not jumped');
    expect(halfway.longitude, inExclusiveRange(78.0, 79.0));

    await tester.pump(truckPinGlide);
    await tester.pumpAndSettle();
    expect(_truckPin(tester), const LatLng(13.0, 79.0),
        reason: 'it ends on the new position');
    await leave(tester);
  });
}
