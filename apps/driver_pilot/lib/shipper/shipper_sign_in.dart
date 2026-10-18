import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:go_router/go_router.dart";

import "../authorization_session.dart";
import "../customer_session.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "../ui/format.dart";
import "../ui/sign_in_code_page.dart";
import "../ui/sign_in_phone_page.dart";

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _debugCode;
  String? _challengeId;
  String? _challengePhone;
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
    final phone = digitsOnly(value.trim());
    if (_challengePhone == null || phone == _challengePhone) return;
    setState(() {
      _challengeId = null;
      _challengePhone = null;
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
      _startOtpCooldown(r.data?["retryAfterMs"]);
      SemanticsService.announce(
          "Code sent to ${formatPhone(phone)}.", Directionality.of(context));
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
    SemanticsService.announce(error, Directionality.of(context),
        assertiveness: Assertiveness.assertive);
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
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {
          "phone": phone,
          "challengeId": challengeId,
          "code": _code.text.trim()
        },
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      await CustomerSession.refresh();
      if (!mounted) return;
      context.go(AuthorizationSession.hasRole("SHIPPER")
          ? "/customer/shipments"
          : AuthorizationSession.home);
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
        onBack: () => context.go("/customer"),
        shipping: true,
        onOtherSide: () => context.go("/driver/onboarding/phone"),
        newAccountLinks: {
          "Register business": () => context.go("/customer/register"),
          "Register as teammate": () => context.go("/customer/register-user"),
        },
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
