// A proof of delivery photo the phone cannot show. Hunt, 23 Oct 2026: opened full size it was a blank
// screen with no words.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:driver_pilot/pod_photo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_fixtures.dart' show podPhotos;
import 'support/shipper_shipment_app.dart';

/// Bytes that are not a picture, as a damaged upload would be.
final notAPicture = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

void main() {
  testWidgets('a photo that cannot be shown full size says so', (tester) async {
    final server = await showShipment(
        tester,
        booking(status: 'PENDING_RELEASE', extra: {
          'podAtUtcMs': deliveredAt.millisecondsSinceEpoch,
          'podPhotos': podPhotos(['photo-1']),
        }));
    server.answers['/v1/shipments/shp_9f2c41/pod-photos/photo-1'] =
        ResponseBody.fromBytes(notAPicture, 200, headers: {
      Headers.contentTypeHeader: ['image/jpeg']
    });
    await tester.tap(find.text('View proof of delivery'));
    await tester.pumpAndSettle();
    final shown = find.descendant(
        of: find.byType(PodPhotosScreen), matching: find.byType(Image));
    tester
        .widget<InkWell>(
            find.ancestor(of: shown, matching: find.byType(InkWell)).first)
        .onTap!();
    await tester.pumpAndSettle();
    // Decoding runs outside the test clock, so let it finish and fail.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('This photo cannot be shown.'), findsOneWidget,
        reason: 'the same words as the small view');
    await leave(tester);
  });
}
