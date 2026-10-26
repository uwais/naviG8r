import "dart:html" as html;
import "dart:js_util" as js_util;

/// One setting from runtime-config.js, written by the web container at start; empty when absent.
String runtimeConfigValue(String key) {
  try {
    final config =
        js_util.getProperty<Object?>(html.window, "__NAVI8R_CONFIG__");
    if (config == null) return "";
    final value = js_util.getProperty<Object?>(config, key);
    return value is String ? value : "";
  } catch (_) {
    return "";
  }
}
