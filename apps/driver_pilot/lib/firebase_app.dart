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
  final apiKey =
      kIsWeb ? (firebaseWebConfig.apiKey ?? _firebaseApiKey) : _firebaseApiKey;
  final appId =
      kIsWeb ? (firebaseWebConfig.appId ?? _firebaseAppId) : _firebaseAppId;
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
Future<FirebaseApp>? _firebaseAppFuture;

Future<FirebaseApp> _initializeFirebaseApp() async {
  final options = firebaseDartOptions;
  if (kIsWeb && options == null) {
    throw StateError("Firebase web configuration is missing.");
  }

  // Do not inspect Firebase.apps before initialization. Older FlutterFire web
  // versions access the JS SDK while evaluating that getter; on WebKit this
  // can happen before the loader has installed window.firebase_core.
  late final FirebaseApp app;
  try {
    app = await Firebase.initializeApp(options: options);
  } on FirebaseException catch (error) {
    if (error.code != "duplicate-app") rethrow;
    app = Firebase.app();
  }
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

Future<FirebaseApp> ensureFirebaseApp() async {
  final cached = _firebaseAppFuture;
  if (cached != null) return cached;

  final future = _initializeFirebaseApp();
  _firebaseAppFuture = future;
  try {
    return await future;
  } catch (_) {
    // Allow a later attempt after a transient WebKit/module-loader failure.
    if (identical(_firebaseAppFuture, future)) _firebaseAppFuture = null;
    rethrow;
  }
}
