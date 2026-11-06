import "dart:async";

import "package:dio/dio.dart" show DioException;
import "package:flutter/foundation.dart" show kReleaseMode;
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:go_router/go_router.dart";

import "authorization_session.dart";
import "customer_session.dart";
import "firebase_phone_auth.dart";
import "phone_country.dart";
import "pilot_api.dart";
import "plain_error_sentence.dart";
import "ui/format.dart";
import "ui/sign_in_code_page.dart";
import "ui/sign_in_phone_page.dart";
import "shipper/announce.dart";

/// What Send code says for each answer to a code request. Only a request that got no answer blames
/// the connection. The server already says when a number has no account, so this does too.
String _sendCodeErrorSentence(Object error) {
  if (serverNeverAnswered(error)) {
    return "Could not send the code. Check your connection, then try again.";
  }
  final body = error is DioException ? error.response?.data : null;
  return switch (body is Map ? body["error"] : null) {
    "user_not_found" =>
      "No account uses this number. Check the number, or register below.",
    "account_inactive" =>
      "This account is no longer active, so it cannot sign in. Contact NaviG8r if this is wrong.",
    "invalid_phone" => "Enter a 10-digit mobile number.",
    "otp_rate_limited" => formatApiError(error),
    _ => "Could not send the code right now. Try again in a few minutes.",
  };
}

/// Firebase answers in its own errors; the code exchange with the server answers like any API call.
String _firebaseErrorSentence(Object error, String fallback) =>
    error is DioException
        ? plainErrorSentence(error, fallback)
        : formatFirebaseAuthError(error);

/// The number a carrier just registered with, handed to the sign-in as the router's extra and never
/// put in the link. A class, not a String: go_router 14 writes an extra it can turn into JSON into
/// the browser's history. A reload has no extra and opens an empty box.
class PhoneForSignIn {
  const PhoneForSignIn(this.number, {this.countryCode = "+91"});
  final String number;
  final String countryCode;
}

/// The one sign-in, for shippers and carriers alike. It asks nothing about the person; after the
/// code the app lands by the account's role (AuthorizationSession.home). Where Firebase phone
/// sign-in started (see initializeFirebasePhoneAuth), Firebase sends and checks the code and the
/// server exchanges its token; otherwise the server's own code is used.
class SignInScreen extends StatefulWidget {
  const SignInScreen(
      {this.startingPhone,
      this.startingCountryCode,
      this.phoneAuth,
      super.key});

  /// The number a carrier just registered with, filled in so they only tap Send code.
  final String? startingPhone;
  final String? startingCountryCode;

  /// Tests pass a stand-in for Firebase.
  final PhoneAuthClient? phoneAuth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String _countryCode = "+91";
  String? _debugCode;
  String? _challengeId;
  String? _challengePhone;
  String? _challengeCountryCode;
  // The server spends a code on its first check, so once the token is saved a retry
  // repeats only the account check.
  bool _codeAccepted = false;
  bool _sending = false;
  bool _verifying = false;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;
  String? _error;
  PhoneAuthClient? _firebase;
  bool _useFirebase = firebasePhoneAuthAvailable;
  bool _firebaseCodeSent = false;

  bool get _codeRequested =>
      _challengePhone != null &&
      (_useFirebase ? _firebaseCodeSent : _challengeId != null);

  bool _isChallengeFor(String phone) =>
      _challengePhone == phone && _challengeCountryCode == _countryCode;

  void _startOtpCooldown(dynamic rawMs) {
    _otpCooldownTimer?.cancel();
    final ms = rawMs is num ? rawMs.toInt() : 0;
    final seconds = ms > 0 ? (ms / 1000).ceil() : 0;
    if (mounted) setState(() => _otpCooldownSeconds = seconds);
    if (seconds > 0) {
      _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() => _otpCooldownSeconds =
            (_otpCooldownSeconds - 1).clamp(0, 1 << 30).toInt());
        if (_otpCooldownSeconds == 0) timer.cancel();
      });
    }
  }

  void _forgetChallenge() {
    _challengeId = null;
    _challengePhone = null;
    _challengeCountryCode = null;
    _firebaseCodeSent = false;
    _codeAccepted = false;
    _debugCode = null;
    _code.clear();
    _otpCooldownSeconds = 0;
    _otpCooldownTimer?.cancel();
    _otpCooldownTimer = null;
  }

  void _phoneChanged(String value) {
    // An error about the old number must not sit under a number that may now be right.
    if (_error != null) setState(() => _error = null);
    final phone = digitsOnly(value.trim());
    if (_challengePhone == null || _isChallengeFor(phone)) return;
    setState(_forgetChallenge);
  }

  void _countryChanged(String value) {
    if (_countryCode == value) return;
    setState(() {
      _countryCode = value;
      _error = null;
      _forgetChallenge();
    });
  }

  void _useFirebaseChanged(bool value) => setState(() {
        _useFirebase = value;
        if (value) _firebase ??= widget.phoneAuth ?? FirebasePhoneAuthClient();
        _error = null;
        _forgetChallenge();
      });

  @override
  void initState() {
    super.initState();
    _phone.text = widget.startingPhone ?? "";
    final startingCountryCode = widget.startingCountryCode;
    if (startingCountryCode != null &&
        supportedCountryCodes.contains(startingCountryCode)) {
      _countryCode = startingCountryCode;
    }
    if (widget.phoneAuth != null) _useFirebase = true;
    if (_useFirebase) _firebase = widget.phoneAuth ?? FirebasePhoneAuthClient();
    CustomerSession.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _firebase?.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String _shownNumber(String phone, String countryCode) =>
      countryCode == "+91" ? formatPhone(phone) : "$countryCode $phone";

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final phone = digitsOnly(_phone.text.trim());
    if (phone.length != 10) {
      setState(() {
        _error = "Enter a 10-digit mobile number.";
        _sending = false;
      });
      return;
    }
    if (_useFirebase) {
      await _sendFirebaseCode(phone);
      return;
    }
    if (!legacyOtpFallbackEnabled) {
      setState(() {
        _error = firebasePhoneAuthDiagnostic ??
            "Firebase phone sign-in is unavailable.";
        _sending = false;
      });
      return;
    }
    try {
      final previousChallengeId = _challengeId;
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start",
          data: {"phone": phone, "countryCode": _countryCode});
      if (!mounted) return;
      _challengeId = r.data?["challengeId"] as String?;
      _challengePhone = phone;
      _challengeCountryCode = _countryCode;
      _codeAccepted = false;
      _startOtpCooldown(r.data?["retryAfterMs"]);
      announce(context, "Code sent to ${_shownNumber(phone, _countryCode)}.");
      final dc = r.data?["debugCode"];
      if (dc is String && dc.isNotEmpty) {
        _debugCode = dc;
        _code.text = dc;
      } else if (_challengeId != previousChallengeId) {
        _debugCode = null;
        _code.clear();
      }
    } catch (e) {
      final retry = otpRetryAfterMs(e);
      if (retry != null) _startOtpCooldown(retry);
      if (mounted) setState(() => _error = _sendCodeErrorSentence(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendFirebaseCode(String phone) async {
    // A failed resend keeps the code already sent for the same number usable.
    final keepCodeSent = _firebaseCodeSent && _isChallengeFor(phone);
    setState(() {
      _challengePhone = phone;
      _challengeCountryCode = _countryCode;
      _firebaseCodeSent = false;
      _codeAccepted = false;
    });
    try {
      await _firebase!.requestCode(
        firebasePhoneNumber(phone, _countryCode),
        onCodeSent: (_) {
          if (mounted) setState(() => _firebaseCodeSent = true);
        },
        onAutoVerified: () {
          if (mounted) setState(() => _firebaseCodeSent = true);
        },
      );
      if (!mounted) return;
      _startOtpCooldown(firebaseResendCooldownMs);
      _debugCode = null;
      _code.clear();
      announce(context, "Code sent to ${_shownNumber(phone, _countryCode)}.");
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _firebaseCodeSent = keepCodeSent;
        if (!keepCodeSent) _challengePhone = null;
        _error = _firebaseErrorSentence(e,
            "Could not send the code. Check your connection, then try again.");
      });
      final retry = firebaseAuthRetryAfterMs(e);
      if (retry != null) _startOtpCooldown(retry);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showVerifyError(String error) {
    setState(() => _error = error);
    announce(context, error, assertiveness: Assertiveness.assertive);
  }

  Future<void> _verify() async {
    final phone = digitsOnly(_phone.text.trim());
    final challengeId = _challengeId;
    if (!_codeRequested || !_isChallengeFor(phone)) {
      _showVerifyError("Request a code for this phone number first.");
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      if (!_codeAccepted && _useFirebase) {
        await _firebase!.verifyCode(_code.text.trim());
        await exchangeFirebaseToken(await _firebase!.idToken());
        _codeAccepted = true;
      } else if (!_codeAccepted) {
        final r = await api.post<Map<String, dynamic>>(
          "/v1/auth/otp/verify",
          data: {
            "phone": phone,
            "countryCode": _countryCode,
            "challengeId": challengeId,
            "code": _code.text.trim()
          },
        );
        final token = r.data?["accessToken"] as String?;
        if (token == null || token.isEmpty) {
          if (mounted) {
            _showVerifyError(
                "Could not sign you in. Check your connection, then try again.");
          }
          return;
        }
        await api.setToken(token);
        _codeAccepted = true;
      }
      await CustomerSession.refresh();
      if (!mounted) return;
      // The code was right, so the account check failed: a dropped connection or the server.
      if (!AuthorizationSession.signedIn) {
        _showVerifyError(
            "Could not finish signing in. Check your connection, then try again.");
        return;
      }
      context.go(AuthorizationSession.home);
    } catch (e) {
      if (mounted) {
        const fallback =
            "Could not sign you in. Check your connection, then try again.";
        _showVerifyError(_useFirebase
            ? _firebaseErrorSentence(e, fallback)
            : plainErrorSentence(e, fallback));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // Back to the phone step; the code request for the old number no longer applies.
  void _changeNumber() => setState(() {
        _forgetChallenge();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final challengePhone = _challengePhone;
    if (!_codeRequested || challengePhone == null) {
      return SignInPhonePage(
        phone: _phone,
        countryCode: _countryCode,
        onCountryChanged: _countryChanged,
        sending: _sending,
        errorText: _error,
        onSend: _sendOtp,
        onPhoneChanged: _phoneChanged,
        useFirebase: _useFirebase,
        // The switch only where both ways work: Firebase started, and the server's own code is allowed.
        onUseFirebaseChanged:
            firebasePhoneAuthAvailable && legacyOtpFallbackEnabled
                ? _useFirebaseChanged
                : null,
        firebaseDiagnostic: firebasePhoneAuthDiagnostic,
        newAccountLinks: {
          "Register a shipper company": () => context.go("/customer/register"),
          "Join a shipper company": () => context.go("/customer/register-user"),
          "Register a carrier company": () =>
              context.go("/driver/onboarding/register"),
          "Join a carrier company": () => context.go("/driver/onboarding/join"),
        },
        onOpenDeveloperLab:
            kReleaseMode ? null : () => context.go("/pilot-lab"),
      );
    }
    return SignInCodePage(
      phone:
          _shownNumber(challengePhone, _challengeCountryCode ?? _countryCode),
      code: _code,
      verifying: _verifying,
      sendingNewCode: _sending,
      secondsUntilNewCode: _otpCooldownSeconds,
      errorText: _error,
      debugCode: _debugCode,
      onSignIn: _verify,
      onSendNewCode: _sendOtp,
      onChangeNumber: _changeNumber,
      onBack: _changeNumber,
    );
  }
}
