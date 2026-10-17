import "package:flutter/foundation.dart" show kReleaseMode;
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "ui/nv_button.dart";
import "ui/tokens.dart";

/// What someone signed out sees first. The choice only picks which sign-in words and landing
/// to use; it grants nothing, and the server still decides what the person can do.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NvSpace.gutter, NvSpace.s8, NvSpace.gutter, NvSpace.s6),
      children: [
        Text("NaviG8r",
            style: NvText.title.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: NvSpace.s12),
        Semantics(
          header: true,
          child: const Text("How do you use NaviG8r?", style: NvText.display),
        ),
        const SizedBox(height: NvSpace.s3),
        // copy.md goes on "You can add the other later from the account menu.", but no flow
        // adds a company while signed in, so that half is left out until one exists.
        Text("Choose one.", style: NvText.body.copyWith(fontSize: 16)),
        const SizedBox(height: NvSpace.s6),
        _ChoiceCard(
          icon: Icons.inventory_2_outlined,
          title: "I ship goods",
          detail: "Book space on a carrier's trip and follow it to delivery.",
          onChoose: () => context.go("/customer/login"),
        ),
        const SizedBox(height: NvSpace.s3),
        _ChoiceCard(
          icon: Icons.local_shipping_outlined,
          title: "I carry goods",
          detail: "For truck owners, dispatchers and drivers.",
          onChoose: () => context.go("/driver/onboarding/phone"),
        ),
        const SizedBox(height: NvSpace.s8),
        // copy.md's second footer line, "New carrier? Sign in first, then register your
        // company.", is left out: an unregistered phone cannot sign in today.
        const Text(
            "Already have an account? Either choice signs you in with your phone number.",
            style: NvText.caption),
        if (!kReleaseMode) ...[
          const SizedBox(height: NvSpace.s4),
          Align(
            alignment: Alignment.centerLeft,
            child: NvButton(
                label: "Developer lab",
                kind: NvButtonKind.quiet,
                onPressed: () => context.go("/pilot-lab")),
          ),
        ],
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard(
      {required this.icon,
      required this.title,
      required this.detail,
      required this.onChoose});
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NvRadius.card),
        side: const BorderSide(color: NvColors.line));
    return MergeSemantics(
      child: Material(
        color: NvColors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChoose,
          customBorder: shape,
          highlightColor: NvColors.sunken,
          child: Padding(
            padding: const EdgeInsets.all(NvSpace.s4),
            child: Row(children: [
              ExcludeSemantics(
                child: Container(
                  width: NvSpace.s12,
                  height: NvSpace.s12,
                  decoration: BoxDecoration(
                      color: NvColors.navy,
                      borderRadius: BorderRadius.circular(NvRadius.button)),
                  child: Icon(icon, color: NvColors.gold),
                ),
              ),
              const SizedBox(width: NvSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: NvText.heading.copyWith(fontSize: 17)),
                    const SizedBox(height: NvSpace.s1),
                    Text(detail, style: NvText.caption.copyWith(fontSize: 15)),
                  ],
                ),
              ),
              const ExcludeSemantics(
                  child: Icon(Icons.chevron_right, color: NvColors.slate)),
            ]),
          ),
        ),
      ),
    );
  }
}
