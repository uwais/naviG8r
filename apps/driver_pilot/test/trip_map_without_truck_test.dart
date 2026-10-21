// The tracking map must draw with no truck position: the shipper screen has none until the trip
// is live, and the driver's map has none before the first GPS fix. Flutter's tween builder
// asserted on a missing end point, so these maps threw instead of drawing.
import 'package:driver_pilot/location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _origin = LatLng(12.97, 77.59);
const _destination = LatLng(13.08, 80.27);

Marker? _truckPin(WidgetTester tester) {
  for (final marker in tester.widget<GoogleMap>(find.byType(GoogleMap)).markers) {
    if (marker.markerId.value == 'track_driver') return marker;
  }
  return null;
}

/// Mounts [mapFor] and returns the truck position it is drawn with, which a test then changes.
Future<ValueNotifier<LatLng?>> _mount(
    WidgetTester tester, Widget Function(LatLng? driver) mapFor,
    {LatLng? driver}) async {
  final truckPosition = ValueNotifier<LatLng?>(driver);
  addTearDown(truckPosition.dispose);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<LatLng?>(
          valueListenable: truckPosition,
          builder: (_, position, __) => mapFor(position)),
    ),
  ));
  return truckPosition;
}

Widget _tracking(LatLng? driver) =>
    tripTrackingMap(origin: _origin, destination: _destination, driver: driver);

Widget _active(LatLng? driver) =>
    activeTripMap(laneStart: _origin, laneEnd: _destination, driver: driver);

void main() {
  for (final (name, mapFor) in [
    ('tripTrackingMap', _tracking),
    ('activeTripMap', _active),
  ]) {
    group(name, () {
      testWidgets('draws with no truck position', (tester) async {
        await _mount(tester, mapFor);
        expect(tester.takeException(), isNull);
        expect(find.byType(GoogleMap), findsOneWidget);
        expect(_truckPin(tester), isNull);
      });

      testWidgets('a first truck position shows at once, on the same map',
          (tester) async {
        final truckPosition = await _mount(tester, mapFor);
        final mapBefore = tester.state(find.byType(GoogleMap));

        truckPosition.value = const LatLng(12.5, 78.0);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_truckPin(tester)?.position, const LatLng(12.5, 78.0),
            reason: 'there is nothing to glide from, so it does not glide');
        expect(tester.state(find.byType(GoogleMap)), same(mapBefore),
            reason: 'the map is kept, not made again');
      });

      testWidgets('a truck position going away removes the pin',
          (tester) async {
        final truckPosition =
            await _mount(tester, mapFor, driver: const LatLng(12.5, 78.0));
        expect(_truckPin(tester)?.position, const LatLng(12.5, 78.0));
        final mapBefore = tester.state(find.byType(GoogleMap));

        truckPosition.value = null;
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_truckPin(tester), isNull);
        expect(tester.state(find.byType(GoogleMap)), same(mapBefore));
      });

      testWidgets('a moved truck glides on the same map', (tester) async {
        final truckPosition =
            await _mount(tester, mapFor, driver: const LatLng(12.0, 78.0));
        final mapBefore = tester.state(find.byType(GoogleMap));

        truckPosition.value = const LatLng(13.0, 79.0);
        await tester.pump();
        await tester.pump(truckPinGlide ~/ 2);
        final halfway = _truckPin(tester)!.position;
        expect(halfway.latitude, inExclusiveRange(12.0, 13.0));
        expect(halfway.longitude, inExclusiveRange(78.0, 79.0));

        await tester.pumpAndSettle();
        expect(_truckPin(tester)?.position, const LatLng(13.0, 79.0));
        expect(tester.state(find.byType(GoogleMap)), same(mapBefore));
      });
    });
  }
}
