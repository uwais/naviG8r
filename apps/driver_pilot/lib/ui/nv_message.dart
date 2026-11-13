import "package:flutter/material.dart";

import "tokens.dart";

enum NvMessageTone { info, attention, good, problem }

/// An inline banner near the thing it is about: "saved" confirmations and errors. It is a live
/// region, so a screen reader reads it out when it appears or changes.
class NvMessage extends StatelessWidget {
  const NvMessage(this.text, {super.key, required this.tone, this.title});

  final String text;
  final NvMessageTone tone;

  /// An optional bold first line, such as "Delivery confirmed".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final (background, iconColour, textColour) = switch (tone) {
      NvMessageTone.info => (
          NvColors.infoTint,
          NvColors.navy,
          NvColors.navyInk
        ),
      NvMessageTone.attention => (
          NvColors.attentionTint,
          NvColors.attention,
          NvColors.ink
        ),
      NvMessageTone.good => (NvColors.goodTint, NvColors.good, NvColors.ink),
      NvMessageTone.problem => (
          NvColors.problemTint,
          NvColors.problem,
          NvColors.ink
        ),
    };
    final icon = switch (tone) {
      NvMessageTone.good => Icons.check,
      NvMessageTone.info => Icons.info_outline,
      NvMessageTone.attention || NvMessageTone.problem => Icons.error_outline,
    };
    final textStyle = NvText.body.copyWith(color: textColour);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(NvSpace.s3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(NvRadius.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ExcludeSemantics(
                  child: Icon(icon, size: 20, color: iconColour)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!,
                        style: textStyle.copyWith(fontWeight: FontWeight.w700)),
                  Text(text, style: textStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
