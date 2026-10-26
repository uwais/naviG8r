import 'package:driver_pilot/firebase_phone_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stands in for Firebase on the sign-in screens.
class FakePhoneAuth implements PhoneAuthClient {
  final codeRequestsFor = <String>[];
  Object? verifyError;

  @override
  Future<void> requestCode(
    String phoneNumber, {
    required void Function(String) onCodeSent,
    void Function()? onAutoVerified,
  }) async {
    codeRequestsFor.add(phoneNumber);
    onCodeSent('fake-verification');
  }

  @override
  Future<void> verifyCode(String code) async {
    final error = verifyError;
    if (error != null) throw error;
  }

  @override
  Future<String> idToken() async => 'fake-id-token';

  @override
  Future<void> signOut() async {}
}

/// Firebase Auth as the browser sees it: only the reCAPTCHA phone sign-in is answered.
class FakeBrowserAuth implements FirebaseAuth {
  final codeRequestsFor = <String>[];
  final confirmedCodes = <String>[];
  bool signedIn = false;

  @override
  Future<ConfirmationResult> signInWithPhoneNumber(String phoneNumber,
      [RecaptchaVerifier? verifier]) async {
    codeRequestsFor.add(phoneNumber);
    return _FakeConfirmation(this);
  }

  @override
  User? get currentUser => signedIn ? _FakeUser() : null;

  @override
  Future<void> signOut() async => signedIn = false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConfirmation implements ConfirmationResult {
  _FakeConfirmation(this.auth);
  final FakeBrowserAuth auth;

  @override
  String get verificationId => 'browser-verification';

  @override
  Future<UserCredential> confirm(String verificationCode) async {
    auth.confirmedCodes.add(verificationCode);
    auth.signedIn = true;
    return _FakeCredential();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'browser-id-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
