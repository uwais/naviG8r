import "package:firebase_core/firebase_core.dart";

const bool _releaseBuild = bool.fromEnvironment("dart.vm.product");
const String expectedFirebaseProjectId = String.fromEnvironment(
  "FIREBASE_PROJECT_ID",
  defaultValue:
      _releaseBuild ? "project-e8131904-7071-4f79-89c" : "navig8r-beta",
);

const _firebaseApiKey = String.fromEnvironment("FIREBASE_API_KEY");
const _firebaseAppId = String.fromEnvironment("FIREBASE_APP_ID");
const _firebaseSenderId =
    String.fromEnvironment("FIREBASE_MESSAGING_SENDER_ID");

FirebaseOptions? get firebaseDartOptions {
  if (_firebaseApiKey.isEmpty ||
      _firebaseAppId.isEmpty ||
      _firebaseSenderId.isEmpty ||
      expectedFirebaseProjectId.isEmpty) {
    return null;
  }
  return const FirebaseOptions(
    apiKey: _firebaseApiKey,
    appId: _firebaseAppId,
    messagingSenderId: _firebaseSenderId,
    projectId: expectedFirebaseProjectId,
  );
}

/// Initializes Firebase once for Auth and FCM and rejects a mixed environment.
Future<FirebaseApp> ensureFirebaseApp() async {
  final options = firebaseDartOptions;
  final app = Firebase.apps.isEmpty
      ? await Firebase.initializeApp(options: options)
      : Firebase.app();
  if (expectedFirebaseProjectId.isNotEmpty &&
      app.options.projectId != expectedFirebaseProjectId) {
    throw StateError(
      "Firebase project mismatch: expected $expectedFirebaseProjectId, "
      "got ${app.options.projectId}.",
    );
  }
  if (options != null && app.options.appId != options.appId) {
    throw StateError("Firebase Dart and native configuration do not match.");
  }
  return app;
}

// docker/customer-web/entrypoint.sh checks the same patterns before it writes runtime-config.js.
const _firebaseWebSettingPatterns = {
  "FIREBASE_PROJECT_ID": r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$",
  "FIREBASE_WEB_API_KEY": r"^AIza[0-9A-Za-z_-]{35}$",
  "FIREBASE_WEB_APP_ID": r"^[0-9]{1,3}:[0-9]{6,20}:web:[0-9a-f]{6,40}$",
  "FIREBASE_MESSAGING_SENDER_ID": r"^[0-9]{6,20}$",
};

/// Web Firebase settings, or null when any is missing or malformed so web keeps the old code sign-in.
FirebaseOptions? firebaseWebOptions(String Function(String key) setting) {
  final values = <String, String>{};
  for (final MapEntry(key: name, value: pattern)
      in _firebaseWebSettingPatterns.entries) {
    final value = setting(name);
    if (!RegExp(pattern).hasMatch(value)) return null;
    values[name] = value;
  }
  final projectId = values["FIREBASE_PROJECT_ID"]!;
  return FirebaseOptions(
    apiKey: values["FIREBASE_WEB_API_KEY"]!,
    appId: values["FIREBASE_WEB_APP_ID"]!,
    messagingSenderId: values["FIREBASE_MESSAGING_SENDER_ID"]!,
    projectId: projectId,
    authDomain: "$projectId.firebaseapp.com",
  );
}
