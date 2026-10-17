import "package:flutter/material.dart";

import "nv_button.dart";
import "nv_field.dart";
import "nv_header.dart";
import "tokens.dart";

/// The phone step of signing in, for shippers and carriers alike. The screen that shows it
/// keeps the number, sends the code and says which side the person chose on the start screen.
class SignInPhonePage extends StatelessWidget {
  const SignInPhonePage({
    required this.phone,
    required this.sending,
    required this.onSend,
    required this.onBack,
    required this.shipping,
    required this.onOtherSide,
    this.errorText,
    this.onPhoneChanged,
    this.newAccountLinks = const {},
    super.key,
  });

  final TextEditingController phone;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onBack;

  /// True when the person chose "I ship goods", false for "I carry goods".
  final bool shipping;
  final VoidCallback onOtherSide;
  final String? errorText;
  final ValueChanged<String>? onPhoneChanged;

  /// Today's ways to make a new account, by their button words.
  final Map<String, VoidCallback> newAccountLinks;

  @override
  Widget build(BuildContext context) {
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
              child:
                  const Text("Sign in with your phone", style: NvText.display),
            ),
            const SizedBox(height: NvSpace.s2),
            Text("We send a 6-digit code to this number by SMS.",
                style: NvText.body.copyWith(fontSize: 16)),
            const SizedBox(height: NvSpace.s6),
            NvField(
              label: "Mobile number",
              controller: phone,
              prefix: "+91",
              help: "10 digits. Standard SMS rates may apply.",
              errorText: errorText,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              onChanged: onPhoneChanged,
            ),
            const SizedBox(height: NvSpace.s5),
            NvButton(
                label: "Send code",
                onPressed: onSend,
                loading: sending,
                fullWidth: true),
            const SizedBox(height: NvSpace.s8),
            Container(
              padding: const EdgeInsets.all(NvSpace.s4),
              decoration: BoxDecoration(
                  color: NvColors.sunken,
                  borderRadius: BorderRadius.circular(NvRadius.card)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: "Signing in to "),
                      TextSpan(
                          text: shipping ? "ship goods" : "carry goods",
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: "."),
                    ]),
                    style: NvText.body,
                  ),
                  NvButton(
                      label: shipping
                          ? "I carry goods instead"
                          : "I ship goods instead",
                      kind: NvButtonKind.quiet,
                      onPressed: onOtherSide),
                ],
              ),
            ),
            for (final link in newAccountLinks.entries) ...[
              const SizedBox(height: NvSpace.s2),
              Align(
                alignment: Alignment.centerLeft,
                child: NvButton(
                    label: link.key,
                    kind: NvButtonKind.quiet,
                    onPressed: link.value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
