// Size note: just over 500 lines, all one concern: the maps the screens share, including the
// place editor, and reading a map point out of server data. Splitting would part that one concern.
import "dart:math" as math;

import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "google_geocoding.dart";

/// Read-only route line between two points (publish / book preview).
Widget routePreviewMap({required LatLng a, required LatLng b}) {
  final markers = <Marker>{
    Marker(
      markerId: const MarkerId("route_a"),
      position: a,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ),
    Marker(
      markerId: const MarkerId("route_b"),
      position: b,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    ),
  };
  final line = Polyline(
    polylineId: const PolylineId("route_ab"),
    points: [a, b],
    width: 4,
    color: const Color(0xFF3F51B5),
  );
  final bounds = LatLngBounds(
    southwest: LatLng(
      (a.latitude < b.latitude ? a.latitude : b.latitude),
      (a.longitude < b.longitude ? a.longitude : b.longitude),
    ),
    northeast: LatLng(
      (a.latitude > b.latitude ? a.latitude : b.latitude),
      (a.longitude > b.longitude ? a.longitude : b.longitude),
    ),
  );

  return SizedBox(
    height: 200,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: a, zoom: 6),
        markers: markers,
        polylines: {line},
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        onMapCreated: (controller) async {
          try {
            await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 50));
          } catch (_) {}
        },
      ),
    ),
  );
}

/// Route + optional live driver position (customer tracking).
Widget tripTrackingMap({
  required LatLng origin,
  required LatLng destination,
  LatLng? driver,
  LatLng? pickup,
  LatLng? drop,
}) {
  final markers = <Marker>{
    Marker(
      markerId: const MarkerId("track_origin"),
      position: origin,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ),
    Marker(
      markerId: const MarkerId("track_dest"),
      position: destination,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    ),
    if (pickup != null)
      Marker(
        markerId: const MarkerId("track_pickup"),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
    if (drop != null)
      Marker(
        markerId: const MarkerId("track_drop"),
        position: drop,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      ),
    if (driver != null)
      Marker(
        markerId: const MarkerId("track_driver"),
        position: driver,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: "Driver"),
      ),
  };
  final points = <LatLng>[origin, destination, if (pickup != null) pickup, if (drop != null) drop, if (driver != null) driver];
  final bounds = _boundsForPoints(points);
  final polylines = <Polyline>{
    Polyline(
      polylineId: const PolylineId("track_lane"),
      points: [origin, destination],
      width: 4,
      color: const Color(0xFF3F51B5),
    ),
  };

  return SizedBox(
    height: 220,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: origin, zoom: 6),
        markers: markers,
        polylines: polylines,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        onMapCreated: (controller) async {
          if (bounds == null) return;
          try {
            await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 48));
          } catch (_) {}
        },
      ),
    ),
  );
}

LatLng? latLngFromGeoMap(Map<String, dynamic>? parent, String field) {
  final g = parent?[field];
  if (g is! Map<String, dynamic>) return null;
  final lat = g["lat"];
  final lng = g["lng"];
  double? parseCoord(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
  final la = parseCoord(lat);
  final ln = parseCoord(lng);
  if (la == null || ln == null) return null;
  return LatLng(la, ln);
}

/// @deprecated Use [latLngFromGeoMap].
LatLng? latLngFromTripField(Map<String, dynamic>? trip, String field) => latLngFromGeoMap(trip, field);

/// Map centered on a single point (e.g. driver GPS while route coords load).
Widget singlePointMap({required LatLng center, String label = "Location", double zoom = 13}) {
  return SizedBox(
    height: 220,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: center, zoom: zoom),
        markers: {
          Marker(
            markerId: const MarkerId("single_point"),
            position: center,
            infoWindow: InfoWindow(title: label),
          ),
        },
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
      ),
    ),
  );
}

/// Best-effort map for the driver active-trip screen.
Widget activeTripMap({
  LatLng? laneStart,
  LatLng? laneEnd,
  LatLng? driver,
  LatLng? pickup,
  LatLng? drop,
  String? emptyMessage,
}) {
  if (laneStart != null && laneEnd != null) {
    return tripTrackingMap(
      origin: laneStart,
      destination: laneEnd,
      driver: driver,
      pickup: pickup,
      drop: drop,
    );
  }
  if (driver != null) {
    return singlePointMap(center: driver, label: "You", zoom: 12);
  }
  final fallback = laneStart ?? laneEnd ?? pickup ?? drop;
  if (fallback != null) {
    return singlePointMap(center: fallback, label: "Trip point", zoom: 10);
  }
  return SizedBox(
    height: 220,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            emptyMessage ??
                "No map coordinates yet. Republish the trip with map pins, or wait for GPS.",
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF757575), fontSize: 13),
          ),
        ),
      ),
    ),
  );
}

LatLngBounds? _boundsForPoints(List<LatLng> points) {
  if (points.isEmpty) return null;
  if (points.length == 1) return null;
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;
  for (final p in points.skip(1)) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLng = math.min(minLng, p.longitude);
    maxLng = math.max(maxLng, p.longitude);
  }
  return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
}

/// Anchor trip corridor (thick orange) vs your shipment pickup→drop (thinner blue). A pickup or
/// drop not placed yet has no pin. With [onPickupMoved] or [onDropMoved] that pin can be dragged.
/// Needs at least one point.
Widget bookShipmentRouteMap({
  Key? key,
  LatLng? shipmentPickup,
  LatLng? shipmentDrop,
  LatLng? anchorOrigin,
  LatLng? anchorDestination,
  ValueChanged<LatLng>? onPickupMoved,
  ValueChanged<LatLng>? onDropMoved,
}) {
  final hasAnchor = anchorOrigin != null && anchorDestination != null;
  final polylines = <Polyline>{
    if (hasAnchor)
      Polyline(
        polylineId: const PolylineId("anchor_trip_leg"),
        points: [anchorOrigin, anchorDestination],
        color: const Color(0xFFE65100),
        width: 9,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    if (shipmentPickup != null && shipmentDrop != null)
      Polyline(
        polylineId: const PolylineId("shipment_leg"),
        points: [shipmentPickup, shipmentDrop],
        color: const Color(0xFF0D47A1),
        width: 4,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
  };

  final markers = <Marker>{
    if (hasAnchor) ...[
      Marker(
        markerId: const MarkerId("book_map_anchor_start"),
        position: anchorOrigin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: "Anchor trip start"),
      ),
      Marker(
        markerId: const MarkerId("book_map_anchor_end"),
        position: anchorDestination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: "Anchor trip end"),
      ),
    ],
    if (shipmentPickup != null)
      Marker(
        markerId: const MarkerId("book_map_ship_pickup"),
        position: shipmentPickup,
        draggable: onPickupMoved != null,
        onDragEnd: onPickupMoved,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: "Your pickup"),
      ),
    if (shipmentDrop != null)
      Marker(
        markerId: const MarkerId("book_map_ship_drop"),
        position: shipmentDrop,
        draggable: onDropMoved != null,
        onDragEnd: onDropMoved,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Your drop"),
      ),
  };

  final allPoints = <LatLng>[
    if (hasAnchor) ...[anchorOrigin, anchorDestination],
    if (shipmentPickup != null) shipmentPickup,
    if (shipmentDrop != null) shipmentDrop,
  ];
  final bounds = _boundsForPoints(allPoints);
  final initialTarget = allPoints.first;

  return SizedBox(
    key: key,
    height: 240,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: initialTarget, zoom: 6),
        markers: markers,
        polylines: polylines,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
        onMapCreated: (controller) async {
          if (bounds == null) return;
          try {
            await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 56));
          } catch (_) {}
        },
      ),
    ),
  );
}

/// Place search + draggable pin; [labelController] is sent to your API as city/label text.
class LocationEndpointEditor extends StatefulWidget {
  const LocationEndpointEditor({
    super.key,
    required this.title,
    required this.hint,
    required this.labelController,
    required this.markerId,
    required this.markerHue,
    required this.position,
    required this.onPositionChanged,
    this.showApiKeyHint = true,
    this.showMap = true,
    this.findPlace = GoogleGeocodingService.forwardAddress,
    this.findTown = GoogleGeocodingService.reverseLatLng,
  });

  final String title;
  final String hint;
  final TextEditingController labelController;
  final String markerId;
  final double markerHue;
  final LatLng position;
  final ValueChanged<LatLng> onPositionChanged;
  final bool showApiKeyHint;

  /// False leaves out the map and its drag caption, so a screen can keep the form short until the place is found.
  final bool showMap;
  final PlaceFinder findPlace;
  final TownFinder findTown;

  @override
  State<LocationEndpointEditor> createState() => _LocationEndpointEditorState();
}

class _LocationEndpointEditorState extends State<LocationEndpointEditor> {
  GoogleMapController? _map;
  late LatLng _pos;
  bool _lookupBusy = false;
  bool _reverseBusy = false;
  String? _hintLine;
  // Each search and pin drag bumps this, so a slow town lookup cannot overwrite a newer one.
  int _newestLookup = 0;
  // A failed search still opens the map, so the pin can be dragged to a place Google cannot find.
  bool _searchTried = false;

  @override
  void initState() {
    super.initState();
    _pos = widget.position;
  }

  @override
  void didUpdateWidget(covariant LocationEndpointEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A hidden map is disposed, and its controller with it.
    if (!widget.showMap && !_searchTried) _map = null;
    final o = oldWidget.position;
    final n = widget.position;
    if (o.latitude != n.latitude || o.longitude != n.longitude) {
      _pos = n;
      _map?.animateCamera(CameraUpdate.newLatLng(n));
    }
  }

  Future<void> _lookup() async {
    _newestLookup++;
    setState(() {
      _lookupBusy = true;
      _reverseBusy = false;
      _hintLine = null;
    });
    final outcome = await widget.findPlace(widget.labelController.text);
    if (!mounted) return;
    setState(() {
      _lookupBusy = false;
      _searchTried = true;
    });
    if (!outcome.isOk) {
      setState(() => _hintLine = switch (outcome.failure) {
            PlaceSearchFailure.nothingTyped => "Type a town or area, then search.",
            PlaceSearchFailure.notFound =>
              "Could not find this place. Try a nearby town, or drag the pin on the map to it.",
            PlaceSearchFailure.unreachable =>
              "Could not reach the map service. Check your connection, then search again.",
            PlaceSearchFailure.notWorking || null =>
              "Place search is not working right now. Drag the pin on the map to the place.",
          });
      if (outcome.status == "NO_API_KEY" && mounted && widget.showApiKeyHint) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Add --dart-define=MAPS_API_KEY=… when running Flutter (same key as android/local.properties)."),
          ),
        );
      }
      return;
    }
    final p = outcome.position!;
    setState(() {
      _pos = p;
      // The field becomes the trip's city name, so it holds the short name; the hint shows the full address.
      _hintLine = outcome.formattedAddress;
      widget.labelController.text = outcome.placeName ?? widget.labelController.text;
    });
    widget.onPositionChanged(p);
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(p, 12));
  }

  Future<void> _onDragEnd(LatLng p) async {
    setState(() {
      _pos = p;
      _hintLine = null;
    });
    widget.onPositionChanged(p);

    final lookup = ++_newestLookup;
    setState(() => _reverseBusy = true);
    final outcome = await widget.findTown(p);
    if (!mounted || lookup != _newestLookup) return;
    setState(() => _reverseBusy = false);
    // Without a key nothing can name the pin, so the name typed by hand stays.
    if (outcome.status == "NO_API_KEY") return;
    final name = outcome.isOk ? outcome.placeName : null;
    final noTownAtPin = outcome.failure == PlaceSearchFailure.notFound || (outcome.isOk && name == null);
    setState(() {
      if (name != null) {
        widget.labelController.text = name;
        _hintLine = outcome.formattedAddress;
      } else if (noTownAtPin) {
        // The name from before the drag would publish the trip under a town the pin has left.
        widget.labelController.text = "";
        _hintLine = "Could not name the place at the pin. Type its name above.";
      } else {
        _hintLine = "Could not check the name at the pin. Check it is still right.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: widget.labelController,
          decoration: InputDecoration(
            labelText: widget.hint,
            suffixIcon: _lookupBusy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: "Look up place",
                    icon: const Icon(Icons.search),
                    onPressed: _lookup,
                  ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _lookup(),
        ),
        if (_hintLine != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _hintLine!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
        if (_reverseBusy) ...[
          const SizedBox(height: 4),
          Text("Updating address from pin…", style: Theme.of(context).textTheme.bodySmall),
        ],
        if (widget.showMap || _searchTried) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GoogleMap(
                // Zoomed out when no place is known yet, so the pin can be dragged across the country.
                initialCameraPosition: CameraPosition(target: _pos, zoom: widget.showMap ? 12 : 5),
                markers: {
                  Marker(
                    markerId: MarkerId(widget.markerId),
                    position: _pos,
                    draggable: true,
                    icon: BitmapDescriptor.defaultMarkerWithHue(widget.markerHue),
                    onDragEnd: _onDragEnd,
                  ),
                },
                onMapCreated: (c) => _map = c,
                zoomControlsEnabled: true,
                myLocationButtonEnabled: false,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Drag the pin to fine-tune. Use search to jump to a place.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
