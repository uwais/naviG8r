import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";

import "firebase_app.dart";
import "pilot_api.dart";

/// Android Firebase phone auth is enabled by default. Non-Android targets, or
/// Android builds where Firebase initialization is unavailable, keep the
/// existing OTP provider. Set `--dart-define=USE_FIREBASE_PHONE_AUTH=false`
/// for an explicit Android legacy-OTP build.
const bool firebasePhoneAuthEnabled = bool.fromEnvironment(
  "USE_FIREBASE_PHONE_AUTH",
  defaultValue: true,
);
const bool _legacyOtpFallbackRequested = bool.fromEnvironment(
  "ALLOW_LEGACY_OTP_FALLBACK",
  defaultValue: false,
);

bool get legacyOtpFallbackEnabled =>
    _legacyOtpFallbackRequested ||
    kIsWeb ||
    defaultTargetPlatform != TargetPlatform.android ||
    !firebasePhoneAuthAvailable;

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
        return "This verification session expired. Request a new code.";
      case "invalid-verification-code":
        return "That code is incorrect. Check it and try again.";
    }
  }
  if (error is TimeoutException) {
    return "Firebase verification timed out. Check your connection and try again.";
  }
  return error.toString();
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

class FirebasePhoneAuthClient implements PhoneAuthClient {
  FirebasePhoneAuthClient({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;
  String? _verificationId;
  bool _autoVerified = false;

  @override
  Future<void> requestCode(
    String phoneNumber, {
    required void Function(String) onCodeSent,
    void Function()? onAutoVerified,
  }) async {
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
    return token;
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

Future<bool> initializeFirebasePhoneAuth() async {
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
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
