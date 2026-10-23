import "package:flutter/material.dart";

import "tokens.dart";

/// Which group a status word belongs to; the colour only supports the word.
enum NvStatusTone { attention, info, good, problem, ended }

/// A status word on a tint, such as "Waiting for carrier". Not tappable. The words are in
/// spec/copy.md and replace every system code.
class NvStatusLabel extends StatelessWidget {
  const NvStatusLabel(this.word, {super.key, required this.tone})
      : assert(word != "", "a status is always a word, never colour alone");

  final String word;
  final NvStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      NvStatusTone.attention => (NvColors.attentionTint, NvColors.attention),
      NvStatusTone.info => (NvColors.infoTint, NvColors.navy),
      NvStatusTone.good => (NvColors.goodTint, NvColors.good),
      NvStatusTone.problem => (NvColors.problemTint, NvColors.problem),
      NvStatusTone.ended => (NvColors.sunken, NvColors.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: NvSpace.s2, vertical: NvSpace.s1 / 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(NvRadius.sm),
      ),
      child: Text(word,
          style: NvText.caption
              .copyWith(color: foreground, fontWeight: FontWeight.w600)),
    );
  }
}
