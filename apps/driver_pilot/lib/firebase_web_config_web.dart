import "dart:html" as html;
import "dart:js_util" as js_util;

class FirebaseWebConfig {
  const FirebaseWebConfig({
    this.apiKey,
    this.appId,
    this.messagingSenderId,
    this.projectId,
    this.authDomain,
  });

  final String? apiKey;
  final String? appId;
  final String? messagingSenderId;
  final String? projectId;
  final String? authDomain;
}

String? _stringProperty(Object? object, String name) {
  if (object == null || !js_util.hasProperty(object, name)) return null;
  final value = js_util.getProperty<Object?>(object, name);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

FirebaseWebConfig _readConfig() {
  final config = js_util.getProperty<Object?>(html.window, "__NAVI8R_CONFIG__");
  final firebase =
      config == null ? null : js_util.getProperty<Object?>(config, "FIREBASE");
  return FirebaseWebConfig(
    apiKey: _stringProperty(firebase, "apiKey"),
    appId: _stringProperty(firebase, "appId"),
    messagingSenderId: _stringProperty(firebase, "messagingSenderId"),
    projectId: _stringProperty(firebase, "projectId"),
    authDomain: _stringProperty(firebase, "authDomain"),
  );
}

final firebaseWebConfig = _readConfig();
