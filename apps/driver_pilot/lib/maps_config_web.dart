import "dart:html" as html;
import "dart:js_util" as js_util;

String get kMapsApiKey {
  try {
    final config = js_util.getProperty<Object?>(
      html.window,
      "__NAVI8R_CONFIG__",
    );

    if (config == null) {
      return "";
    }

    final value = js_util.getProperty<Object?>(
      config,
      "MAPS_API_KEY",
    );

    return value?.toString().trim() ?? "";
  } catch (_) {
    return "";
  }
}

/// False when Google's map script in web/index.html did not load (no connection, blocked), so no map
/// can draw. The place boxes still work without it.
bool get mapsCanDraw {
  try {
    return js_util.hasProperty(html.window, "google");
  } catch (_) {
    return false;
  }
}
