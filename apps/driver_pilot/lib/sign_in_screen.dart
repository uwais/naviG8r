import "dart:async";

import "package:flutter/foundation.dart" show kReleaseMode;
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:go_router/go_router.dart";

import "authorization_session.dart";
import "customer_session.dart";
import "pilot_api.dart";
import "plain_error_sentence.dart";
import "ui/format.dart";
import "ui/sign_in_code_page.dart";
import "ui/sign_in_phone_page.dart";
import "shipper/announce.dart";

/// The one sign-in, for shippers and carriers alike. It asks nothing about the person; after the
/// code the app lands by the account's role (AuthorizationSession.home).
class SignInScreen extends StatefulWidget {
  const SignInScreen({this.startingPhone, super.key});

  /// The number a carrier just registered with, filled in so they only tap Send code.
  final String? startingPhone;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _debugCode;
  String? _challengeId;
  String? _challengePhone;
  // The server spends a code on its first check, so once the token is saved a retry
  // repeats only the account check.
  bool _codeAccepted = false;
  bool _sending = false;
  bool _verifying = false;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;
  String? _error;

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

  void _phoneChanged(String value) {
    // An error about the old number must not sit under a number that may now be right.
    if (_error != null) setState(() => _error = null);
    final phone = digitsOnly(value.trim());
    if (_challengePhone == null || phone == _challengePhone) return;
    setState(() {
      _challengeId = null;
      _challengePhone = null;
      _codeAccepted = false;
      _debugCode = null;
      _code.clear();
      _otpCooldownSeconds = 0;
      _otpCooldownTimer?.cancel();
      _otpCooldownTimer = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _phone.text = widget.startingPhone ?? "";
    CustomerSession.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

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
    try {
      final previousChallengeId = _challengeId;
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start",
          data: {"phone": phone});
      if (!mounted) return;
      _challengeId = r.data?["challengeId"] as String?;
      _challengePhone = phone;
      _codeAccepted = false;
      _startOtpCooldown(r.data?["retryAfterMs"]);
      announce(context, "Code sent to ${formatPhone(phone)}.");
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
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not send the code. Check your connection, then try again."));
      }
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
    if (challengeId == null || phone != _challengePhone) {
      _showVerifyError("Request a code for this phone number first.");
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      if (!_codeAccepted) {
        final r = await api.post<Map<String, dynamic>>(
          "/v1/auth/otp/verify",
          data: {
            "phone": phone,
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
        _showVerifyError(plainErrorSentence(e,
            "Could not sign you in. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // Back to the phone step; the code request for the old number no longer applies.
  void _changeNumber() => setState(() {
        _challengeId = null;
        _challengePhone = null;
        _codeAccepted = false;
        _debugCode = null;
        _error = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    final challengePhone = _challengePhone;
    if (_challengeId == null || challengePhone == null) {
      return SignInPhonePage(
        phone: _phone,
        sending: _sending,
        errorText: _error,
        onSend: _sendOtp,
        onPhoneChanged: _phoneChanged,
        newAccountLinks: {
          "Register business": () => context.go("/customer/register"),
          "Register as teammate": () => context.go("/customer/register-user"),
          "Register as new carrier": () =>
              context.go("/driver/onboarding/register"),
          "Join a carrier fleet": () => context.go("/driver/onboarding/join"),
        },
        onOpenDeveloperLab:
            kReleaseMode ? null : () => context.go("/pilot-lab"),
      );
    }
    return SignInCodePage(
      phone: formatPhone(challengePhone),
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
