/// Geocoding Web API key for **Dart** HTTP calls only (city → lat/lng).
///
/// Separate from the native Maps SDK key in `android/local.properties` (`MAPS_API_KEY`),
/// which is injected into the Android manifest and must be Android-restricted (package + SHA-1).
/// Pass at build/run time, e.g.:
/// `flutter run --dart-define=MAPS_API_KEY=your_geocoding_key`
export "maps_config_native.dart"
    if (dart.library.html) "maps_config_web.dart";