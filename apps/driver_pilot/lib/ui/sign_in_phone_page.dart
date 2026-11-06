import "package:flutter/material.dart";

import "nv_button.dart";
import "nv_choice.dart";
import "nv_field.dart";
import "tokens.dart";

/// The country codes the server takes for a phone number, by their chip words.
const _countries = [
  NvChoice("+91", "India +91"),
  NvChoice("+1", "United States +1"),
];

/// The phone step of signing in, for shippers and carriers alike, and what someone signed out
/// sees first. The screen that shows it keeps the number and sends the code.
class SignInPhonePage extends StatelessWidget {
  const SignInPhonePage({
    required this.phone,
    required this.sending,
    required this.onSend,
    this.errorText,
    this.onPhoneChanged,
    this.countryCode = "+91",
    this.onCountryChanged,
    this.useFirebase = false,
    this.onUseFirebaseChanged,
    this.firebaseDiagnostic,
    this.newAccountLinks = const {},
    this.onOpenDeveloperLab,
    super.key,
  });

  final TextEditingController phone;
  final bool sending;
  final VoidCallback onSend;
  final String? errorText;
  final ValueChanged<String>? onPhoneChanged;

  final String countryCode;

  /// Null hides the country choice.
  final ValueChanged<String>? onCountryChanged;

  final bool useFirebase;

  /// Null hides the switch: it shows only where Firebase and the server's own code both work.
  final ValueChanged<bool>? onUseFirebaseChanged;

  /// Why Firebase sign-in could not start, when it could not.
  final String? firebaseDiagnostic;

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
            if (onCountryChanged != null) ...[
              NvChoiceChips<String>(
                label: "Country",
                options: _countries,
                selected: countryCode,
                onChanged: onCountryChanged,
              ),
              const SizedBox(height: NvSpace.s3),
            ],
            NvField(
              label: "Mobile number",
              controller: phone,
              prefix: countryCode,
              help: "10 digits. Standard SMS rates may apply.",
              errorText: errorText,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              onChanged: onPhoneChanged,
            ),
            if (onUseFirebaseChanged != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Use Firebase phone verification",
                    style: NvText.body),
                subtitle: const Text("Turn off only if Firebase is unavailable.",
                    style: NvText.body),
                value: useFirebase,
                onChanged: sending ? null : onUseFirebaseChanged,
              ),
            if (firebaseDiagnostic != null) ...[
              const SizedBox(height: NvSpace.s2),
              Text(firebaseDiagnostic!, style: NvText.body),
            ],
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
