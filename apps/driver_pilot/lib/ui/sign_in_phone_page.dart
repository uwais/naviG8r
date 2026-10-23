import "package:flutter/material.dart";

import "nv_button.dart";
import "nv_field.dart";
import "tokens.dart";

/// The phone step of signing in, for shippers and carriers alike, and what someone signed out
/// sees first. The screen that shows it keeps the number and sends the code.
class SignInPhonePage extends StatelessWidget {
  const SignInPhonePage({
    required this.phone,
    required this.sending,
    required this.onSend,
    this.errorText,
    this.onPhoneChanged,
    this.newAccountLinks = const {},
    this.onOpenDeveloperLab,
    super.key,
  });

  final TextEditingController phone;
  final bool sending;
  final VoidCallback onSend;
  final String? errorText;
  final ValueChanged<String>? onPhoneChanged;

  /// Today's ways to make a new account, by their button words.
  final Map<String, VoidCallback> newAccountLinks;

  /// Null hides the link; release builds have no developer lab.
  final VoidCallback? onOpenDeveloperLab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              NvSpace.gutter, NvSpace.s6, NvSpace.gutter, NvSpace.s6),
          children: [
            // The wordmark is a picture of the name, so screen readers get the name once.
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: "NaviG8r",
                image: true,
                child: Image.asset("assets/brand/navig8r-logo.png",
                    height: 52, excludeFromSemantics: true),
              ),
            ),
            const SizedBox(height: NvSpace.s6),
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
            if (newAccountLinks.isNotEmpty) ...[
              const SizedBox(height: NvSpace.s8),
              Semantics(
                header: true,
                child: const Text("New to NaviG8r?", style: NvText.heading),
              ),
            ],
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
            if (onOpenDeveloperLab != null) ...[
              const SizedBox(height: NvSpace.s6),
              Align(
                alignment: Alignment.centerLeft,
                child: NvButton(
                    label: "Developer lab",
                    kind: NvButtonKind.quiet,
                    onPressed: onOpenDeveloperLab),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
