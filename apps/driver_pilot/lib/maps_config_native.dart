/// Maps/geocoding API key for native builds.
///
/// Native builds continue to support:
/// --dart-define=MAPS_API_KEY=...
const String kMapsApiKey = String.fromEnvironment(
  "MAPS_API_KEY",
  defaultValue: "",
);