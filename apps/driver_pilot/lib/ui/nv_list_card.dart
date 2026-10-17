import "package:flutter/material.dart";

import "tokens.dart";

/// A short label over its value on a list card, for example "Room left" over "105 kg".
class NvFact {
  const NvFact(this.label, this.value);
  final String label;
  final String value;
}

/// One item in a list. The whole card is its only tap target, with no buttons inside, so a
/// slip on a list cannot start a trip or remove anything.
class NvListCard extends StatelessWidget {
  const NvListCard(
      {required this.title,
      required this.onOpen,
      this.status,
      this.subtitle,
      this.facts = const [],
      this.footnote,
      this.next,
      this.needsYou = false,
      super.key});

  /// The route, "Bengaluru to Chennai", or on a booking the shipper's name.
  final String title;
  final VoidCallback onOpen;

  /// A status label beside the title. It must not be tappable.
  final Widget? status;
  final String? subtitle;
  final List<NvFact> facts;

  /// A caption after the facts, for example the truck and driver on a trip.
  final String? footnote;

  /// Who acts next, shown after "Next:".
  final String? next;

  /// Draws the navy border that marks a card waiting on this person.
  final bool needsYou;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NvRadius.card),
      side: BorderSide(
          color: needsYou ? NvColors.navy : NvColors.line,
          width: needsYou ? 1.5 : 1),
    );
    return MergeSemantics(
      child: Material(
        color: NvColors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          customBorder: shape,
          highlightColor: NvColors.sunken,
          child: Padding(
            padding: const EdgeInsets.all(NvSpace.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(title,
                          style: NvText.bodyStrong
                              .copyWith(color: NvColors.navyInk))),
                  if (status != null) ...[
                    const SizedBox(width: NvSpace.s2),
                    status!,
                  ],
                ]),
                if (subtitle != null) ...[
                  const SizedBox(height: NvSpace.s1),
                  Text(subtitle!, style: NvText.caption),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: NvSpace.s2),
                  Wrap(
                    spacing: NvSpace.s6,
                    runSpacing: NvSpace.s2,
                    children: [
                      for (final fact in facts)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fact.label, style: NvText.caption),
                            Text(fact.value,
                                style: NvText.bodyStrong
                                    .copyWith(color: NvColors.navyInk)),
                          ],
                        ),
                    ],
                  ),
                ],
                if (footnote != null) ...[
                  const SizedBox(height: NvSpace.s2),
                  Text(footnote!, style: NvText.caption),
                ],
                Row(children: [
                  Expanded(
                    child: next == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: NvSpace.s2),
                            child: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: "Next: ",
                                  style: NvText.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: NvColors.ink)),
                              TextSpan(
                                  text: next,
                                  style: NvText.caption
                                      .copyWith(color: NvColors.ink)),
                            ])),
                          ),
                  ),
                  const ExcludeSemantics(
                      child: Icon(Icons.chevron_right,
                          size: 20, color: NvColors.slate)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The placeholder card shown while a list loads. The screen announces the loading words once.
class NvListLoadingCard extends StatelessWidget {
  const NvListLoadingCard({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(
              height: height,
              decoration: BoxDecoration(
                  color: NvColors.sunken,
                  borderRadius: BorderRadius.circular(NvRadius.sm))),
        );
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.line)),
        child: Column(children: [
          bar(0.7, 16),
          const SizedBox(height: NvSpace.s2),
          bar(0.5, 12),
          const SizedBox(height: NvSpace.s3),
          bar(0.8, 32),
        ]),
      ),
    );
  }
}

/// What a list shows when it has nothing in it, for example "No lanes are open right now."
class NvListEmpty extends StatelessWidget {
  const NvListEmpty({required this.title, this.help, super.key});
  final String title;
  final String? help;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.sunken,
            borderRadius: BorderRadius.circular(NvRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
            if (help != null) ...[
              const SizedBox(height: NvSpace.s1),
              Text(help!, style: NvText.caption.copyWith(color: NvColors.ink)),
            ],
          ],
        ),
      );
}

/// What a list shows when it could not load, with the one way to try again.
class NvListError extends StatelessWidget {
  const NvListError(
      {required this.title, required this.onRetry, this.help, super.key});
  final String title;
  final String? help;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.problemTint,
            borderRadius: BorderRadius.circular(NvRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(title,
                  style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
            ),
            if (help != null) ...[
              const SizedBox(height: NvSpace.s1),
              Text(help!, style: NvText.caption.copyWith(color: NvColors.ink)),
            ],
            const SizedBox(height: NvSpace.s3),
            OutlinedButton(onPressed: onRetry, child: const Text("Try again")),
          ],
        ),
      );
}
