/// Google Maps / Geocoding Web API key for **Dart** (runtime).
///
/// Must match the key in `android/local.properties` (`MAPS_API_KEY`) used for the SDK.
/// Pass at build/run time, e.g.:
/// `flutter run --dart-define=MAPS_API_KEY=your_key_here`
const String kMapsApiKey = String.fromEnvironment("MAPS_API_KEY", defaultValue: "");
