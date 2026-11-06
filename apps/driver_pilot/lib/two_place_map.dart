// The one map a screen shows for its two places, built to the October design's Map component (cp-map): both
// pins, a dotted line between them, a chip naming them in words. The owner's addition (5 Nov 2026): the map
// can move one pin at a time, the one whose box was touched last, because the exact pin sets the price and
// the 15 km booking rule. The place boxes (location_editor.dart) do the search and the address lookup.
import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "maps_config.dart";
import "place_pin_icons.dart";
import "ui/nv_choice.dart";
import "ui/nv_map.dart";
import "ui/tokens.dart";

/// Where a pin starts before the place is known: the map needs a starting point, and the screens
/// refuse to go on until the person has searched for the place or dragged its pin.
const pinNotPlacedYet = LatLng(22.5, 79.0);

/// The two places a screen sets: [start] is the pickup or a trip's From, [end] the drop or its To.
enum MapPlace { start, end }

/// What a screen's two place boxes and its one map share: which place the map moves, which places have
/// had a search (a failed one opens the map, so a place Google cannot find can be tapped in), and the
/// way a tap or drag on the map reaches the box that moves that pin and looks up its address.
class TwoPlaceMapPins extends ChangeNotifier {
  /// [canDraw] is for tests; null asks the platform ([mapsCanDraw]) each time.
  TwoPlaceMapPins({bool? canDraw}) : _canDraw = canDraw;

  final bool? _canDraw;

  /// False when no map can draw here, so a box must not tell the person to tap one.
  bool get mapCanDraw => _canDraw ?? mapsCanDraw;

  MapPlace _moving = MapPlace.start;
  final _searched = <MapPlace>{};
  final _boxes = <MapPlace, ValueChanged<LatLng>>{};

  MapPlace get moving => _moving;
  bool get anySearched => _searched.isNotEmpty;

  void choose(MapPlace place) {
    if (place == _moving) return;
    _moving = place;
    notifyListeners();
  }

  void markSearched(MapPlace place, bool searched) {
    final changed = searched ? _searched.add(place) : _searched.remove(place);
    if (changed) notifyListeners();
  }

  /// Hands [to] to the box of [place], which moves its pin there.
  void movePin(MapPlace place, LatLng to) => _boxes[place]?.call(to);

  void attachBox(MapPlace place, ValueChanged<LatLng> movePin) =>
      _boxes[place] = movePin;

  void detachBox(MapPlace place, ValueChanged<LatLng> movePin) {
    if (_boxes[place] == movePin) _boxes.remove(place);
  }
}

/// Where the camera goes to show the pins: both in view, one at [zoomForOnePlace], or all of India.
CameraUpdate cameraForPins(LatLng? start, LatLng? end,
    {required double zoomForOnePlace}) {
  if (start != null && end != null && start != end) {
    return CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(start.latitude < end.latitude ? start.latitude : end.latitude,
              start.longitude < end.longitude ? start.longitude : end.longitude),
          northeast: LatLng(start.latitude > end.latitude ? start.latitude : end.latitude,
              start.longitude > end.longitude ? start.longitude : end.longitude),
        ),
        48);
  }
  final one = start ?? end;
  return one == null
      ? CameraUpdate.newLatLngZoom(pinNotPlacedYet, 5)
      : CameraUpdate.newLatLngZoom(one, zoomForOnePlace);
}

/// Hidden until a place has a pin or a search, so the form stays short while typing.
class TwoPlaceMap extends StatefulWidget {
  const TwoPlaceMap({
    super.key,
    required this.pins,
    required this.start,
    required this.end,
    required this.startTitle,
    required this.endTitle,
    required this.pinsLabel,
    required this.failedHelp,
    this.pinsAreAddresses = false,
    this.readOnly = false,
  });

  final TwoPlaceMapPins pins;
  final LatLng? start;
  final LatLng? end;

  /// The places' names on their chips and pins: "Pickup" and "Drop", or "From" and "To".
  final String startTitle;
  final String endTitle;

  /// Not shown since the chip became a legend built from [startTitle] and [endTitle]. Kept only so the
  /// screens that pass it need no change in the same commit; safe to remove with them.
  final String pinsLabel;

  /// Under "The map could not load" once both places are set, saying what still works.
  final String failedHelp;

  /// True for a pickup and drop: one pin shows at street level, to place it at a gate. A trip's town is
  /// seen whole.
  final bool pinsAreAddresses;

  /// True while the places are being sent: both pins show, and nothing moves them.
  final bool readOnly;

  @override
  State<TwoPlaceMap> createState() => _TwoPlaceMapState();
}

class _TwoPlaceMapState extends State<TwoPlaceMap> {
  GoogleMapController? _map;
  PlacePinIcons? _icons;

  double get _zoomForOnePlace => widget.pinsAreAddresses ? 17 : 12;

  @override
  void initState() {
    super.initState();
    widget.pins.addListener(_pinsChanged);
    placePinIcons().then((icons) {
      if (mounted) setState(() => _icons = icons);
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(TwoPlaceMap old) {
    super.didUpdateWidget(old);
    if (old.pins != widget.pins) {
      old.pins.removeListener(_pinsChanged);
      widget.pins.addListener(_pinsChanged);
    }
    if (old.start != widget.start || old.end != widget.end) _fitPins();
  }

  @override
  void dispose() {
    widget.pins.removeListener(_pinsChanged);
    super.dispose();
  }

  void _pinsChanged() => setState(() {});

  /// After every change the camera shows both pins (owner, 5 Nov 2026).
  Future<void> _fitPins() async {
    try {
      await _map?.animateCamera(cameraForPins(widget.start, widget.end,
          zoomForOnePlace: _zoomForOnePlace));
    } catch (_) {}
  }

  Marker _pin(MapPlace place, LatLng at, String title, MapPlace moving) {
    final icons = _icons;
    return Marker(
      markerId: MarkerId("${place.name}_place"),
      position: at,
      // Until the drawn dots are ready, Google's pins in the same navy and gold hues.
      icon: icons == null
          ? BitmapDescriptor.defaultMarkerWithHue(place == MapPlace.start ? 220 : 36)
          : (place == MapPlace.start ? icons.start : icons.end),
      anchor: icons == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
      draggable: !widget.readOnly && place == moving,
      zIndex: place == moving ? 2 : 1,
      infoWindow: InfoWindow(title: title),
      onDragEnd: (to) => widget.pins.movePin(place, to),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = widget.start, end = widget.end;
    if (start == null && end == null && !widget.pins.anySearched) {
      _map = null;
      return const SizedBox.shrink();
    }
    final moving = widget.pins.moving;
    final canDraw = widget.pins.mapCanDraw;
    final initialZoom = start != null && end != null
        ? 6.0
        : start != null || end != null
            ? _zoomForOnePlace
            : 5.0;
    final map = GoogleMap(
      initialCameraPosition:
          CameraPosition(target: start ?? end ?? pinNotPlacedYet, zoom: initialZoom),
      markers: {
        if (start != null) _pin(MapPlace.start, start, widget.startTitle, moving),
        if (end != null) _pin(MapPlace.end, end, widget.endTitle, moving),
      },
      polylines: {
        if (start != null && end != null)
          Polyline(
            polylineId: const PolylineId("between_places"),
            points: [start, end],
            width: 3,
            color: NvColors.navy,
            // Dotted on phones; the web map ignores patterns and draws it solid.
            patterns: [PatternItem.dot, PatternItem.gap(10)],
          ),
      },
      onTap: widget.readOnly ? null : (to) => widget.pins.movePin(widget.pins.moving, to),
      onMapCreated: (controller) {
        _map = controller;
        _fitPins();
      },
      zoomControlsEnabled: true,
      myLocationButtonEnabled: false,
    );
    final movingTitle = moving == MapPlace.start ? widget.startTitle : widget.endTitle;
    // Pickup and drop read as plain words mid-sentence; From and To stay as their boxes name them.
    final movingPin = widget.pinsAreAddresses ? movingTitle.toLowerCase() : movingTitle;
    final movingHasPin = (moving == MapPlace.start ? start : end) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Its own space above, so a hidden map leaves no gap in the form.
        const SizedBox(height: NvSpace.s4),
        NvMap(
          map: map,
          pinTitles: (start: widget.startTitle, end: widget.endTitle),
          state: canDraw ? NvMapState.ready : NvMapState.failed,
          failedHelp: start != null && end != null
              ? widget.failedHelp
              : "Type each place in its box and search. The map is not needed.",
        ),
        if (canDraw && !widget.readOnly) ...[
          const SizedBox(height: NvSpace.s2),
          Text("Tap the map to ${movingHasPin ? "move" : "put"} the $movingPin pin.",
              style: NvText.body),
          const SizedBox(height: NvSpace.s2),
          NvChoiceChips<MapPlace>(
            options: [
              NvChoice(MapPlace.start, widget.startTitle),
              NvChoice(MapPlace.end, widget.endTitle),
            ],
            selected: moving,
            onChanged: widget.pins.choose,
          ),
        ],
      ],
    );
  }
}
