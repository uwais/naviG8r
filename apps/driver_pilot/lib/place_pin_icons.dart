// The two pins of a screen's one map, drawn in code as the October design's Map component draws them:
// pickup (or From) a navy dot, drop (or To) a gold dot with a navy ring. A white edge keeps each dot
// visible on any map colour.
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "ui/tokens.dart";

typedef PlacePinIcons = ({BitmapDescriptor start, BitmapDescriptor end});

/// Each dot's width on the map in logical pixels: large enough to see, and to press to drag, on a phone.
const placePinSize = 24.0;

Future<PlacePinIcons>? _drawn;

/// Drawn once and shared by every map.
Future<PlacePinIcons> placePinIcons() => _drawn ??= drawPlacePinIcons();

/// Draws both dots afresh. Maps use [placePinIcons]; a test calls this, since under flutter test the
/// shared drawing, started inside an earlier test, never finishes.
Future<PlacePinIcons> drawPlacePinIcons() async =>
    (start: await _dot(NvColors.navy), end: await _dot(NvColors.gold));

Future<BitmapDescriptor> _dot(Color fill) async {
  // Drawn at three times its size so it stays sharp on dense screens.
  const scale = 3.0;
  const side = placePinSize * scale;
  const centre = Offset(side / 2, side / 2);
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawCircle(centre, side / 2, Paint()..color = NvColors.card)
    ..drawCircle(centre, side / 2 - 2 * scale, Paint()..color = NvColors.navy)
    ..drawCircle(centre, side / 2 - 5 * scale, Paint()..color = fill);
  final image = await recorder.endRecording().toImage(side.toInt(), side.toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return BitmapDescriptor.bytes(png!.buffer.asUint8List(),
      width: placePinSize, height: placePinSize);
}
