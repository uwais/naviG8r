/// Maps/geocoding API key for native builds.
///
/// Native builds continue to support:
/// --dart-define=MAPS_API_KEY=...
const String kMapsApiKey = String.fromEnvironment(
  "MAPS_API_KEY",
  defaultValue: "",
);

/// The phone apps draw maps with the Google Maps SDK built into them, so there is no script that can fail
/// to load.
bool get mapsCanDraw => true;
