import "package:flutter/material.dart";

import "nv_button.dart";
import "nv_field.dart";
import "nv_header.dart";
import "tokens.dart";

/// The code step of signing in. The code request's id stays in the screen's state and is never
/// shown. The wait before a new code is the server's own, counted down, not a pressure timer.
class SignInCodePage extends StatelessWidget {
  const SignInCodePage({
    required this.phone,
    required this.code,
    required this.verifying,
    required this.sendingNewCode,
    required this.secondsUntilNewCode,
    required this.onSignIn,
    required this.onSendNewCode,
    required this.onChangeNumber,
    required this.onBack,
    this.errorText,
    this.debugCode,
    super.key,
  });

  /// The number the code went to, as it should read: "+91 98450 12345".
  final String phone;
  final TextEditingController code;
  final bool verifying;
  final bool sendingNewCode;
  final int secondsUntilNewCode;
  final VoidCallback onSignIn;
  final VoidCallback onSendNewCode;
  final VoidCallback onChangeNumber;
  final VoidCallback onBack;
  final String? errorText;

  /// Test servers send the code back; production never does.
  final String? debugCode;

  @override
  Widget build(BuildContext context) {
    final minutes = secondsUntilNewCode ~/ 60;
    final seconds = (secondsUntilNewCode % 60).toString().padLeft(2, "0");
    return Scaffold(
      appBar: NvHeader.task(backLabel: "Back", onBack: onBack),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              NvSpace.gutter, NvSpace.s6, NvSpace.gutter, NvSpace.s6),
          children: [
            Semantics(
              header: true,
              child: const Text("Enter the code", style: NvText.display),
            ),
            const SizedBox(height: NvSpace.s2),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: "We sent a 6-digit code to "),
                TextSpan(
                    text: phone,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: "."),
              ]),
              style: NvText.body.copyWith(fontSize: 16),
            ),
            if (debugCode != null) ...[
              const SizedBox(height: NvSpace.s2),
              Text("Debug OTP: $debugCode", style: NvText.caption),
            ],
            const SizedBox(height: NvSpace.s6),
            NvField(
              label: "6-digit code",
              controller: code,
              help: "The code fills in by itself if your phone reads the SMS.",
              errorText: errorText,
              identifier: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
            ),
            const SizedBox(height: NvSpace.s5),
            NvButton(
                label: "Sign in",
                onPressed: onSignIn,
                loading: verifying,
                loadingLabel: "Signing you in",
                fullWidth: true),
            const SizedBox(height: NvSpace.s6),
            Wrap(
              spacing: NvSpace.s3,
              runSpacing: NvSpace.s2,
              children: [
                NvButton(
                  label: "Send a new code",
                  kind: NvButtonKind.secondary,
                  onPressed: secondsUntilNewCode > 0 ? null : onSendNewCode,
                  loading: sendingNewCode,
                  disabledReason:
                      "No SMS yet? You can ask for a new code in $minutes:$seconds.",
                ),
                NvButton(
                    label: "Change number",
                    kind: NvButtonKind.quiet,
                    onPressed: onChangeNumber),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
