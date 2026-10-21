// Two jobs in one file for now: the read-only maps the screens share, with their map-point readers
// (latLngFromGeoMap), and the place editor. The split into two files is deferred until after go-live
// (owner, 21 Oct 2026); it changes the imports of five lib files and six test files.
import "dart:math" as math;

import "package:flutter/foundation.dart" show kDebugMode;
import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "google_geocoding.dart";

/// Read-only route line between two points (publish / book preview). [aPinHue] and [bPinHue] let a
/// screen match the pins of its own place boxes; [aLabel] and [bLabel] name a pin when it is tapped.
Widget routePreviewMap({
  required LatLng a,
  required LatLng b,
  double aPinHue = BitmapDescriptor.hueGreen,
  double bPinHue = BitmapDescriptor.hueRed,
  String? aLabel,
  String? bLabel,
}) {
  final markers = <Marker>{
    Marker(
      markerId: const MarkerId("route_a"),
      position: a,
      icon: BitmapDescriptor.defaultMarkerWithHue(aPinHue),
      infoWindow: aLabel == null ? InfoWindow.noText : InfoWindow(title: aLabel),
    ),
    Marker(
      markerId: const MarkerId("route_b"),
      position: b,
      icon: BitmapDescriptor.defaultMarkerWithHue(bPinHue),
      infoWindow: bLabel == null ? InfoWindow.noText : InfoWindow(title: bLabel),
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
        // The camera fits the two points only when the map is made, so a moved point makes a new map.
        key: ValueKey((a, b)),
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

/// How long the truck pin takes to reach a new position, so it glides there instead of jumping.
const truckPinGlide = Duration(milliseconds: 1500);

/// Route + optional live driver position (customer tracking). A new [driver] position glides
/// there over [truckPinGlide] from the one shown; a first position, or none, shows at once.
Widget tripTrackingMap({
  required LatLng origin,
  required LatLng destination,
  LatLng? driver,
  LatLng? pickup,
  LatLng? drop,
}) =>
    _TripTrackingMap(
        origin: origin,
        destination: destination,
        driver: driver,
        pickup: pickup,
        drop: drop);

class _TripTrackingMap extends StatefulWidget {
  const _TripTrackingMap({
    required this.origin,
    required this.destination,
    this.driver,
    this.pickup,
    this.drop,
  });

  final LatLng origin;
  final LatLng destination;
  final LatLng? driver;
  final LatLng? pickup;
  final LatLng? drop;

  @override
  State<_TripTrackingMap> createState() => _TripTrackingMapState();
}

class _TripTrackingMapState extends State<_TripTrackingMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glide =
      AnimationController(vsync: this, duration: truckPinGlide);
  LatLng? _glideFrom;

  @override
  void didUpdateWidget(_TripTrackingMap old) {
    super.didUpdateWidget(old);
    if (widget.driver == old.driver) return;
    final shown = _shownDriverGoingTo(old.driver);
    if (shown == null || widget.driver == null) {
      _glideFrom = null;
      _glide.value = 1;
    } else {
      _glideFrom = shown;
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  LatLng? _shownDriver() => _shownDriverGoingTo(widget.driver);

  LatLng? _shownDriverGoingTo(LatLng? to) {
    final from = _glideFrom;
    if (from == null || to == null) return to;
    final t = _glide.value;
    return LatLng(from.latitude + (to.latitude - from.latitude) * t,
        from.longitude + (to.longitude - from.longitude) * t);
  }

  @override
  Widget build(BuildContext context) {
    final pickup = widget.pickup, drop = widget.drop, driver = widget.driver;
    final placeMarkers = <Marker>{
      Marker(
        markerId: const MarkerId("track_origin"),
        position: widget.origin,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId("track_dest"),
        position: widget.destination,
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
    };
    final points = <LatLng>[
      widget.origin,
      widget.destination,
      if (pickup != null) pickup,
      if (drop != null) drop,
      if (driver != null) driver,
    ];
    final bounds = _boundsForPoints(points);
    final polylines = <Polyline>{
      Polyline(
        polylineId: const PolylineId("track_lane"),
        points: [widget.origin, widget.destination],
        width: 4,
        color: const Color(0xFF3F51B5),
      ),
    };

    return SizedBox(
      height: 220,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // A glide frame rebuilds only the marker set; the lane, bounds and place pins are made per update.
        child: AnimatedBuilder(
          animation: _glide,
          builder: (_, __) {
            final shownDriver = _shownDriver();
            return GoogleMap(
              initialCameraPosition: CameraPosition(target: widget.origin, zoom: 6),
              markers: {
                ...placeMarkers,
                if (shownDriver != null)
                  Marker(
                    markerId: const MarkerId("track_driver"),
                    position: shownDriver,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                    infoWindow: const InfoWindow(title: "Driver"),
                  ),
              },
              polylines: polylines,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: (controller) async {
                if (bounds == null) return;
                try {
                  await controller.moveCamera(CameraUpdate.newLatLngBounds(bounds, 48));
                } catch (_) {}
              },
            );
          },
        ),
      ),
    );
  }
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
                "No map location yet. Add the trip again with map pins, or wait for GPS.",
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

/// Where a pin starts before the place is known: the map needs a starting point, and the screens
/// refuse to go on until the person has searched for the place or dragged its pin.
const pinNotPlacedYet = LatLng(22.5, 79.0);

/// The longest pickup or drop address the server takes (maxAddressLength in the API's services.ts).
const maxAddressCharacters = 500;

/// Google's address for a pickup or drop pin, or none: [lookupFailed] when the lookup itself failed (no
/// connection, a refused key), false when Google has no address for the spot.
typedef PinAddress = ({String? address, bool lookupFailed});

/// Google's address for a pickup or drop pin, under its box and again on Book, so the shipper checks
/// the pin itself whatever the typed words say.
String pinAddressLine(PinAddress? pin) => switch (pin) {
      (address: final String address, lookupFailed: _) => "Pin: $address",
      (address: null, lookupFailed: true) =>
        "Pin: could not look up this spot. Check the pin on the map.",
      _ => "Pin: Google has no address for this spot. Check the pin on the map.",
    };

/// Place search and a draggable pin. [labelController] holds the words sent with the pin: a city for a
/// trip's From and To, the full address for a booking's pickup and drop ([keepsFullAddress]).
class LocationEndpointEditor extends StatefulWidget {
  const LocationEndpointEditor({
    super.key,
    required this.title,
    required this.hint,
    this.example,
    required this.labelController,
    required this.markerId,
    required this.markerHue,
    required this.position,
    required this.onPositionChanged,
    this.onPinStale,
    this.onPinNaming,
    this.onSearching,
    this.pinAddress,
    this.onPinAddress,
    this.readOnly = false,
    this.showApiKeyHint = true,
    this.showMap = true,
    this.findPlace = GoogleGeocodingService.forwardAddress,
    this.namePin = GoogleGeocodingService.reverseLatLng,
    this.keepsFullAddress = false,
    this.staysAliveOffScreen = false,
  });

  final String title;

  /// The box's label.
  final String hint;

  /// Greyed words in the empty box, showing what to type.
  final String? example;
  final TextEditingController labelController;
  final String markerId;
  final double markerHue;
  final LatLng position;
  final ValueChanged<LatLng> onPositionChanged;

  /// A trip's From and To only: called when the words change away from the city the pin was found
  /// for, so the screen stops using that pin. After a drag that found no name, any words typed go
  /// with the pin.
  final VoidCallback? onPinStale;

  /// Called with true while a dragged pin's town name is being looked up, and false once it is
  /// settled. [onPositionChanged] reports the pin before the name, so the words lag until then.
  final ValueChanged<bool>? onPinNaming;

  /// Called with true while a place search is out, and false once it answers or is overtaken, so the
  /// screen waits instead of going on with the place as it was.
  final ValueChanged<bool>? onSearching;

  /// Google's address for a pickup or drop pin the screen already holds, as the match search found it.
  final PinAddress? pinAddress;

  /// Called with Google's address for a pickup or drop pin each time the pin is set, and with null
  /// while a dragged pin is being named.
  final ValueChanged<PinAddress?>? onPinAddress;

  /// True while the place is being sent, so the words, search and pin stay as they were sent.
  final bool readOnly;

  /// Shows the developer's missing-maps-key snackbar. Debug builds only: release users never see it.
  final bool showApiKeyHint;

  /// False leaves out the map and its drag caption, so a screen can keep the form short until the place is found.
  final bool showMap;
  final PlaceFinder findPlace;
  final PinNamer namePin;

  /// False for a trip's From and To, whose words become a city name ("Hoskote"). True for a
  /// booking's pickup and drop (owner, 21 Oct 2026): the pin decides the place and the price, and the
  /// words are the address for the driver. Typing never moves or drops the pin; a search pick or a
  /// drag sets it, and fills the box with Google's address only when the box is empty. The map opens
  /// at street level. Pass [GoogleGeocodingService.reverseAddress] as [namePin].
  final bool keepsFullAddress;

  /// True keeps the box in memory when a list scrolls it off screen, so a search or a pin naming
  /// still out is not lost with it.
  final bool staysAliveOffScreen;

  @override
  State<LocationEndpointEditor> createState() => _LocationEndpointEditorState();
}

class _LocationEndpointEditorState extends State<LocationEndpointEditor>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.staysAliveOffScreen;

  /// Street level for a pickup or drop, to place the pin at a gate; a trip's town is seen whole.
  double get _zoomForAPlace => widget.keepsFullAddress ? 17 : 12;

  GoogleMapController? _map;
  late LatLng _pos;
  bool _lookupBusy = false;
  bool _reverseBusy = false;
  String? _hintLine;
  // Each search and pin drag bumps this, so a slow search or pin name cannot overwrite a newer one.
  int _newestLookup = 0;
  // A failed search still opens the map, so the pin can be dragged to a place Google cannot find.
  bool _searchTried = false;
  // A trip's city name the pin was found for. Null when any words go with the pin (no pin yet, or a
  // drag whose place is still being named).
  String? _pinFoundFor;
  late PinAddress? _pinAddress = widget.pinAddress;
  // A pickup or drop map goes to street level once, after a search or the first drag.
  bool _atStreetLevel = false;

  @override
  void initState() {
    super.initState();
    _pos = widget.position;
    final words = widget.labelController.text.trim();
    _pinFoundFor = words.isEmpty ? null : words;
    _atStreetLevel = widget.keepsFullAddress && widget.showMap;
    widget.labelController.addListener(_wordsChanged);
  }

  @override
  void dispose() {
    widget.labelController.removeListener(_wordsChanged);
    super.dispose();
  }

  /// A trip's field must still say the city its pin was found for. A pickup or drop's words never
  /// drop its pin.
  void _wordsChanged() {
    final pinFoundFor = _pinFoundFor;
    if (widget.keepsFullAddress || pinFoundFor == null) return;
    if (widget.labelController.text.trim() == pinFoundFor) return;
    _pinFoundFor = null;
    setState(() {
      _hintLine = null;
      _searchTried = false;
    });
    widget.onPinStale?.call();
  }

  /// A pickup or drop keeps the words typed (a house number, a landmark Google does not know is what
  /// the carrier needs), and an empty box takes the pin's address.
  void _fillEmptyBox(String? pinAddress) {
    if (pinAddress != null && widget.labelController.text.trim().isEmpty) {
      widget.labelController.text = pinAddress;
    }
  }

  void _setPinAddress(PinAddress? pinAddress) {
    setState(() => _pinAddress = pinAddress);
    if (widget.keepsFullAddress) widget.onPinAddress?.call(pinAddress);
  }

  void _setSearching(bool searching) {
    if (searching == _lookupBusy) return;
    setState(() => _lookupBusy = searching);
    widget.onSearching?.call(searching);
  }

  @override
  void didUpdateWidget(covariant LocationEndpointEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.labelController != widget.labelController) {
      oldWidget.labelController.removeListener(_wordsChanged);
      widget.labelController.addListener(_wordsChanged);
    }
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
    final lookup = ++_newestLookup;
    if (_reverseBusy) widget.onPinNaming?.call(false);
    setState(() {
      _reverseBusy = false;
      _hintLine = null;
    });
    _setSearching(true);
    final outcome = await widget.findPlace(widget.labelController.text);
    if (!mounted || lookup != _newestLookup) return;
    _setSearching(false);
    // The place is being sent, and the words, search and pin stay as they were sent.
    if (widget.readOnly) return;
    setState(() => _searchTried = true);
    if (!outcome.isOk) {
      setState(() => _hintLine = placeSearchFailureSentence(outcome.failure, pinOnMap: true));
      if (outcome.status == "NO_API_KEY" && mounted && widget.showApiKeyHint && kDebugMode) {
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
      if (widget.keepsFullAddress) {
        _fillEmptyBox(outcome.formattedAddress);
      } else {
        // A trip's field becomes its city name; the hint shows the full address the pin went to.
        final name = outcome.placeName ?? widget.labelController.text;
        _pinFoundFor = name.trim();
        widget.labelController.text = name;
        _hintLine = outcome.formattedAddress;
      }
    });
    _setPinAddress((address: outcome.formattedAddress, lookupFailed: false));
    widget.onPositionChanged(p);
    _atStreetLevel = widget.keepsFullAddress;
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(p, _zoomForAPlace));
  }

  Future<void> _onDragEnd(LatLng p) async {
    // The dragged pin is the person's choice of place; only a name found for it ties it to words.
    _pinFoundFor = null;
    setState(() {
      _pos = p;
      _hintLine = null;
    });
    // A search still out is overtaken by the drag and will not answer, so its spinner goes now.
    _setSearching(false);
    _setPinAddress(null);
    widget.onPositionChanged(p);
    if (widget.keepsFullAddress && !_atStreetLevel) {
      _atStreetLevel = true;
      _map?.animateCamera(CameraUpdate.newLatLngZoom(p, _zoomForAPlace));
    }

    final lookup = ++_newestLookup;
    setState(() => _reverseBusy = true);
    widget.onPinNaming?.call(true);
    final outcome = await widget.namePin(p);
    if (!mounted || lookup != _newestLookup) return;
    setState(() => _reverseBusy = false);
    widget.onPinNaming?.call(false);
    if (widget.keepsFullAddress) {
      final pinAddress = outcome.isOk ? outcome.formattedAddress : null;
      setState(() => _fillEmptyBox(pinAddress));
      _setPinAddress((address: pinAddress, lookupFailed: !outcome.isOk && outcome.failure != PlaceSearchFailure.notFound));
      return;
    }
    // Without a key nothing can name the pin, so the name typed by hand stays.
    if (outcome.status == "NO_API_KEY") return;
    final name = outcome.isOk ? outcome.placeName : null;
    final noTownAtPin = outcome.failure == PlaceSearchFailure.notFound || (outcome.isOk && name == null);
    setState(() {
      if (name != null) {
        _pinFoundFor = name.trim();
        widget.labelController.text = name;
        _hintLine = outcome.formattedAddress;
      } else if (noTownAtPin) {
        // The name from before the drag would publish the trip under a town the pin has left.
        widget.labelController.text = "";
        _hintLine = "Could not name the place at the pin. Type its name above.";
      } else {
        _hintLine = "Could not check the place name at the pin. Make sure it is still right.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final caption = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: widget.labelController,
          readOnly: widget.readOnly,
          maxLength: widget.keepsFullAddress ? maxAddressCharacters : null,
          decoration: InputDecoration(
            labelText: widget.hint,
            hintText: widget.example,
            suffixIcon: _lookupBusy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: "Search for place",
                    icon: const Icon(Icons.search),
                    onPressed: widget.readOnly ? null : _lookup,
                  ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            if (!widget.readOnly) _lookup();
          },
        ),
        if (_hintLine != null) ...[
          const SizedBox(height: 6),
          Semantics(liveRegion: true, child: Text(_hintLine!, style: caption)),
        ],
        if (widget.keepsFullAddress && _pos != pinNotPlacedYet && !_reverseBusy) ...[
          const SizedBox(height: 6),
          Semantics(liveRegion: true, child: Text(pinAddressLine(_pinAddress), style: caption)),
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
                initialCameraPosition: CameraPosition(
                    target: _pos, zoom: !widget.showMap ? 5 : _zoomForAPlace),
                markers: {
                  Marker(
                    markerId: MarkerId(widget.markerId),
                    position: _pos,
                    draggable: !widget.readOnly,
                    icon: BitmapDescriptor.defaultMarkerWithHue(widget.markerHue),
                    infoWindow: InfoWindow(title: widget.title),
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
          Text("Drag the pin to the exact spot, or search for a place.", style: caption),
        ],
      ],
    );
  }
}
