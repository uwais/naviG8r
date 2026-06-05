/// Geocoding Web API key for **Dart** HTTP calls only (city → lat/lng).
///
/// Separate from the native Maps SDK key in `android/local.properties` (`MAPS_API_KEY`),
/// which is injected into the Android manifest and must be Android-restricted (package + SHA-1).
/// Pass at build/run time, e.g.:
/// `flutter run --dart-define=MAPS_API_KEY=your_geocoding_key`
const String kMapsApiKey = String.fromEnvironment("MAPS_API_KEY", defaultValue: "");
