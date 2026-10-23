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
