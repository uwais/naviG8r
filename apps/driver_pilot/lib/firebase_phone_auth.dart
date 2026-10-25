import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";

import "firebase_app.dart";
import "pilot_api.dart";
import "runtime_config.dart";

/// Firebase phone auth is enabled by default on Android, and on web when
/// runtime-config.js carries the Firebase web settings. Other targets, or
/// builds where Firebase initialization is unavailable, keep the existing OTP
/// provider. Set `--dart-define=USE_FIREBASE_PHONE_AUTH=false` for an explicit
/// legacy-OTP build.
const bool firebasePhoneAuthEnabled = bool.fromEnvironment(
  "USE_FIREBASE_PHONE_AUTH",
  defaultValue: true,
);
const bool _legacyOtpFallbackRequested = bool.fromEnvironment(
  "ALLOW_LEGACY_OTP_FALLBACK",
  defaultValue: false,
);

bool get legacyOtpFallbackEnabled {
  // Web never offers the old code sign-in once Firebase is ready, whatever the build flags say.
  if (kIsWeb) return !firebasePhoneAuthAvailable;
  return _legacyOtpFallbackRequested ||
      defaultTargetPlatform != TargetPlatform.android ||
      !firebasePhoneAuthAvailable;
}

const int firebaseResendCooldownMs = 30 * 1000;

int? firebaseAuthRetryAfterMs(Object error) {
  if (error is FirebaseAuthException &&
      (error.code == "too-many-requests" || error.code == "quota-exceeded")) {
    return 60 * 1000;
  }
  return null;
}

String formatFirebaseAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case "too-many-requests":
      case "quota-exceeded":
        return "Too many verification attempts. Please wait before requesting another code.";
      case "invalid-phone-number":
        return "Enter a valid phone number and try again.";
      case "network-request-failed":
        return "Unable to reach Firebase. Check your connection and try again.";
      case "session-expired":
      case "code-expired":
        return "This verification session expired. Request a new code.";
      case "invalid-verification-code":
        return "That code is incorrect. Check it and try again.";
      case "captcha-check-failed":
      case "invalid-app-credential":
      case "missing-app-credential":
        return "We could not check this browser. Reload the page and try again.";
      case "unauthorized-domain":
      case "app-not-authorized":
      case "operation-not-allowed":
      case "invalid-api-key":
        return "Phone sign-in is not working on this site. Please try again later.";
    }
    return "Could not sign in. Please try again.";
  }
  if (error is TimeoutException) {
    return "Firebase verification timed out. Check your connection and try again.";
  }
  return formatApiError(error);
}

String firebasePhoneNumber(String nationalNumber) {
  return "+91${digitsOnly(nationalNumber)}";
}

bool firebasePhoneAuthAvailable = false;
String? firebasePhoneAuthDiagnostic;

abstract interface class PhoneAuthClient {
  Future<void> requestCode(
    String phoneNumber, {
    required void Function(String) onCodeSent,
    void Function()? onAutoVerified,
  });
  Future<void> verifyCode(String code);
  Future<String> idToken();
  Future<void> signOut();
}

/// Sign-in screens get their client here so tests can stand in for Firebase.
PhoneAuthClient Function() newPhoneAuthClient = FirebasePhoneAuthClient.new;

class FirebasePhoneAuthClient implements PhoneAuthClient {
  FirebasePhoneAuthClient({FirebaseAuth? auth, bool browserFlow = kIsWeb})
      : _auth = auth ?? FirebaseAuth.instance,
        _browserFlow = browserFlow;
  final FirebaseAuth _auth;
  final bool _browserFlow;
  String? _verificationId;
  bool _autoVerified = false;
  ConfirmationResult? _browserConfirmation;

  @override
  Future<void> requestCode(
    String phoneNumber, {
    required void Function(String) onCodeSent,
    void Function()? onAutoVerified,
  }) async {
    if (_browserFlow) {
      // With no verifier given, firebase_auth shows an invisible reCAPTCHA.
      final confirmation = await _auth.signInWithPhoneNumber(phoneNumber);
      _browserConfirmation = confirmation;
      onCodeSent(confirmation.verificationId);
      return;
    }
    final previousVerificationId = _verificationId;
    final previousAutoVerified = _autoVerified;
    _autoVerified = false;
    final callbackResult = Completer<void>();
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          try {
            await _auth.signInWithCredential(credential);
            _autoVerified = true;
            onAutoVerified?.call();
            if (!callbackResult.isCompleted) callbackResult.complete();
          } catch (error, stackTrace) {
            if (!callbackResult.isCompleted) {
              callbackResult.completeError(error, stackTrace);
            }
          }
        },
        verificationFailed: (error) {
          if (!callbackResult.isCompleted) {
            callbackResult.completeError(error);
          }
        },
        codeSent: (id, _) {
          _verificationId = id;
          onCodeSent(id);
          if (!callbackResult.isCompleted) callbackResult.complete();
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
      await callbackResult.future;
    } catch (_) {
      _verificationId = previousVerificationId;
      _autoVerified = previousAutoVerified;
      rethrow;
    }
  }

  @override
  Future<void> verifyCode(String code) async {
    if (_browserFlow) {
      final confirmation = _browserConfirmation;
      if (confirmation == null) throw StateError("Request a code first.");
      await confirmation.confirm(code).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              "Firebase sign-in timed out before contacting the authentication service.",
            ),
          );
      return;
    }
    if (_autoVerified) return;
    final id = _verificationId;
    if (id == null || id.isEmpty) throw StateError("Request a code first.");
    await _auth
        .signInWithCredential(
          PhoneAuthProvider.credential(verificationId: id, smsCode: code),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException(
            "Firebase sign-in timed out before contacting the authentication service.",
          ),
        );
  }

  @override
  Future<String> idToken() async {
    final token = await _auth.currentUser
        ?.getIdToken()
        .timeout(const Duration(seconds: 15));
    if (token == null || token.isEmpty)
      throw StateError("Firebase sign-in did not return an ID token.");
    // The browser would otherwise keep the Firebase sign-in after the swap; the token stays valid for the exchange.
    if (_browserFlow) await _auth.signOut();
    return token;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

Future<bool> initializeFirebasePhoneAuth() async {
  if (kIsWeb) return _initializeBrowserPhoneAuth();
  if (defaultTargetPlatform != TargetPlatform.android ||
      !firebasePhoneAuthEnabled) {
    return false;
  }
  try {
    await ensureFirebaseApp();
    firebasePhoneAuthAvailable = true;
    return true;
  } catch (_) {
    firebasePhoneAuthDiagnostic =
        "Firebase phone sign-in is unavailable. Check Firebase Android configuration.";
    return false;
  }
}

// One image serves every environment, so the project comes from runtime settings;
// the server still refuses a token from any project but its own.
Future<bool> _initializeBrowserPhoneAuth() async {
  final options = firebaseWebOptions(runtimeConfigValue);
  if (!firebasePhoneAuthEnabled || options == null) return false;
  return startFirebaseInBrowser(() async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
  });
}

// If the Firebase scripts never load, initializeApp never returns; main() waits on this before
// runApp, so a time limit keeps the page from staying blank.
@visibleForTesting
Future<bool> startFirebaseInBrowser(Future<void> Function() initialize,
    {Duration timeout = const Duration(seconds: 8)}) async {
  try {
    await initialize().timeout(timeout);
    firebasePhoneAuthAvailable = true;
    return true;
  } catch (_) {
    firebasePhoneAuthDiagnostic =
        "Phone sign-in is not working right now. Please try again later.";
    return false;
  }
}

Future<void> exchangeFirebaseToken(String token) async {
  final response = await api.post<Map<String, dynamic>>(
    "/v1/auth/firebase/exchange",
    data: {"idToken": token},
  );
  final accessToken = response.data?["accessToken"] as String?;
  if (accessToken == null || accessToken.isEmpty) {
    throw StateError("Firebase exchange did not return an access token.");
  }
  await api.setToken(accessToken);
}
