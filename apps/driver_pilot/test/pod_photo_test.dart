// Proof of delivery photos (owner, 22 Oct 2026): the driver adds one to three before Confirm delivery, each sent as
// it is picked; the shipper and the carrier office view them. The phone's camera and photos are faked through the
// pickPodPhoto seam, since a widget test cannot open the real plugin.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/pod_photo_capture.dart';
import 'package:driver_pilot/pod_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart' show podPhotos, shipmentOnTripA;
import 'support/carrier_office_bookings.dart'
    show answer, mountRouted, signInAsOwner, trip;
import 'support/mock_api.dart';
import 'support/shipper_shipment_app.dart';

/// The first bytes of a JPEG, which is all the app reads before sending.
final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);

/// A driver on the road with one drop to confirm, and the photo requests kept apart from the rest.
class PhotoServer {
  PhotoServer({List<String> sentEarlier = const []}) {
    carrier = signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-today', status: 'IN_PROGRESS')],
      bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles',
            drop: 'Guindy, Chennai',
            photoIds: sentEarlier)
      ],
    ));
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (!request.path.contains('/pod-photos')) return carrier.answer(request);
      photoRequests.add(request);
      final refusal = nextRefusal;
      nextRefusal = null;
      if (refusal != null) return refusal();
      if (request.method == 'DELETE') return jsonResponse({'removed': true});
      return jsonResponse({
        'photo': {
          'id': 'photo-${photoRequests.length}',
          'contentType': 'image/jpeg',
          'uploadedAtUtcMs': 1
        }
      }, 201);
    });
  }

  late final CarrierServer carrier;
  final photoRequests = <RequestOptions>[];

  /// Answers the next photo request instead of the server; it may throw, as a dropped connection does.
  ResponseBody Function()? nextRefusal;
}

FilledButton confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Confirm delivery'));

void main() {
  final realPicker = pickPodPhoto;
  final sources = <ImageSource>[];
  Object? picked;
  setUp(() {
    sources.clear();
    picked = jpeg;
    pickPodPhoto = (source) async {
      sources.add(source);
      final answer = picked;
      if (answer is Exception) throw answer;
      return answer as Uint8List?;
    };
  });
  tearDown(() => pickPodPhoto = realPicker);

  group('The driver (dr-confirm)', () {
    testWidgets(
        'Confirm waits for a photo; Take photo sends it as it is; Remove takes it off again',
        (tester) async {
      final server = PhotoServer();
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
          size: const Size(400, 1600));
      expect(find.text('Choose from gallery'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
      expect(find.text('Add the proof of delivery first.'), findsOneWidget);

      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(sources, [ImageSource.camera]);
      final sent = server.photoRequests.single;
      expect([sent.method, sent.path],
          ['POST', '/v1/shipments/guindy/pod-photos']);
      expect(sent.contentType, 'image/jpeg');
      expect(sent.data, jpeg, reason: 'the picture itself, not JSON');
      expect(find.text('Photo added'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(find.text('Add the proof of delivery first.'), findsNothing);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect([server.photoRequests.last.method, server.photoRequests.last.path],
          ['DELETE', '/v1/shipments/guindy/pod-photos/photo-1']);
      expect(find.text('Photo added'), findsNothing);
      expect(confirmButton(tester).onPressed, isNull);
      expect(server.carrier.sent, isEmpty, reason: 'nothing was confirmed');
    });

    testWidgets('Choose from gallery uses the phone photos; three is the most',
        (tester) async {
      final server = PhotoServer();
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
          size: const Size(400, 1600));
      for (var count = 0; count < 3; count++) {
        await tester.tap(find.text('Choose from gallery'));
        await tester.pumpAndSettle();
      }
      expect(sources, List.filled(3, ImageSource.gallery));
      expect(server.photoRequests, hasLength(3));
      expect(find.text('3 photos added'), findsOneWidget);
      expect(find.text('Take photo'), findsNothing);
      expect(find.text('Choose from gallery'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      expect(server.carrier.sent.single.path, '/shipments/guindy/driver-pod');
    });

    testWidgets('each failure is one plain line, and nothing is held as sent',
        (tester) async {
      final server = PhotoServer();
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
          size: const Size(400, 1600));
      Future<void> takePhoto() async {
        await tester.tap(find.text('Take photo'));
        await tester.pumpAndSettle();
      }

      picked = Uint8List.fromList('not a photo'.codeUnits);
      await takePhoto();
      expect(
          find.text(
              'This file is not a photo the app can send. Take a photo instead.'),
          findsOneWidget);
      expect(server.photoRequests, isEmpty, reason: 'checked on the phone');

      picked = jpeg;
      server.nextRefusal =
          () => jsonResponse({'error': 'pod_photo_too_large'}, 413);
      await takePhoto();
      expect(find.text('This photo is too large to send. Take it again.'),
          findsOneWidget);

      server.nextRefusal = () => throw const SocketException('no signal');
      await takePhoto();
      expect(
          find.text(
              'Could not send the photo: no signal. Try again when you have one.'),
          findsOneWidget);

      picked = Exception('camera_access_denied');
      await takePhoto();
      expect(
          find.text(
              'Could not open the camera. Allow NaviG8r to use it in your phone settings.'),
          findsOneWidget);
      expect(find.text('Photo added'), findsNothing);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('a photo sent on an earlier visit counts', (tester) async {
      final server = PhotoServer(sentEarlier: ['photo-earlier']);
      await mountCarrierApp(tester, '/driver/shipment/guindy/pod',
          size: const Size(400, 1600));
      expect(find.text('Photo added'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget,
          reason: 'this phone no longer has the picture');
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(server.photoRequests, isEmpty);
    });
  });

  group('Viewing the photos', () {
    testWidgets(
        'the shipper opens them with the sign-in and sees each one full size',
        (tester) async {
      final server = await showShipment(
          tester,
          booking(status: 'PENDING_RELEASE', extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
            'paymentHoldUntilUtcMs': deliveredAt
                .add(const Duration(hours: 48))
                .millisecondsSinceEpoch,
            'podPhotos': podPhotos(['photo-1']),
          }));
      server.answers['/v1/shipments/shp_9f2c41/pod-photos/photo-1'] =
          ResponseBody.fromBytes(jpeg, 200, headers: {
        Headers.contentTypeHeader: ['image/jpeg']
      });
      expect(find.text('Accept delivery'), findsOneWidget);
      await tester.tap(find.text('View proof of delivery'));
      await tester.pumpAndSettle();
      final fetched = server.requests.last;
      expect(fetched.path, '/v1/shipments/shp_9f2c41/pod-photos/photo-1');
      expect(fetched.responseType, ResponseType.bytes);
      expect(find.text('Proof of delivery'), findsOneWidget);
      final shown = find.descendant(
          of: find.byType(PodPhotosScreen), matching: find.byType(Image));
      expect((tester.widget<Image>(shown).image as MemoryImage).bytes, jpeg);

      tester
          .widget<InkWell>(
              find.ancestor(of: shown, matching: find.byType(InkWell)).first)
          .onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget,
          reason: 'full size, to zoom in on the signature');
      await leave(tester);
    });

    testWidgets('no photos, no button', (tester) async {
      await showShipment(
          tester,
          booking(status: 'PENDING_RELEASE', extra: {
            'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          }));
      expect(find.text('Accept delivery'), findsOneWidget);
      expect(find.text('View proof of delivery'), findsNothing);
      await leave(tester);
    });

    testWidgets('the carrier office sees them on the delivered booking',
        (tester) async {
      signInAsOwner();
      answer(bookings: [
        shipmentOnTripA(status: 'PENDING_RELEASE', photoIds: ['photo-1'])
      ], trips: [
        trip(status: 'COMPLETED')
      ]);
      await mountRouted(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Delivery confirmed'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'View proof of delivery'),
          findsOneWidget);
    });
  });
}
