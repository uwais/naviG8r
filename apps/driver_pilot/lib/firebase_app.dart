import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";

import "firebase_web_config.dart";

const bool _releaseBuild = bool.fromEnvironment("dart.vm.product");
const String _dartFirebaseProjectId = String.fromEnvironment(
  "FIREBASE_PROJECT_ID",
  defaultValue:
      _releaseBuild ? "project-e8131904-7071-4f79-89c" : "navig8r-beta",
);

const _firebaseApiKey = String.fromEnvironment("FIREBASE_API_KEY");
const _firebaseAppId = String.fromEnvironment("FIREBASE_APP_ID");
const _firebaseSenderId =
    String.fromEnvironment("FIREBASE_MESSAGING_SENDER_ID");
const _firebaseAuthDomain = String.fromEnvironment("FIREBASE_AUTH_DOMAIN");

String get expectedFirebaseProjectId => kIsWeb
    ? (firebaseWebConfig.projectId ?? _dartFirebaseProjectId)
    : _dartFirebaseProjectId;

FirebaseOptions? get firebaseDartOptions {
  final apiKey = kIsWeb
      ? (firebaseWebConfig.apiKey ?? _firebaseApiKey)
      : _firebaseApiKey;
  final appId = kIsWeb
      ? (firebaseWebConfig.appId ?? _firebaseAppId)
      : _firebaseAppId;
  final senderId = kIsWeb
      ? (firebaseWebConfig.messagingSenderId ?? _firebaseSenderId)
      : _firebaseSenderId;
  final authDomain = kIsWeb
      ? (firebaseWebConfig.authDomain ??
          (_firebaseAuthDomain.isEmpty ? null : _firebaseAuthDomain))
      : (_firebaseAuthDomain.isEmpty ? null : _firebaseAuthDomain);
  if (apiKey.isEmpty ||
      appId.isEmpty ||
      senderId.isEmpty ||
      expectedFirebaseProjectId.isEmpty) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: expectedFirebaseProjectId,
    authDomain: authDomain,
  );
}

/// Initializes Firebase once for Auth and FCM and rejects a mixed environment.
Future<FirebaseApp> ensureFirebaseApp() async {
  final options = firebaseDartOptions;
  if (kIsWeb && options == null) {
    throw StateError("Firebase web configuration is missing.");
  }
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
