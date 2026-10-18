import "package:flutter/material.dart";

import "../ui/nv_button.dart";
import "../ui/tokens.dart";

/// What a match search or a price was for, with the one way to change it.
class SearchSummary extends StatelessWidget {
  const SearchSummary(
      {required this.rows,
      required this.changeLabel,
      required this.onChange,
      super.key});
  final List<(String, String)> rows;
  final String changeLabel;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: NvSpace.s2),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: "$label ", style: NvText.caption),
                  TextSpan(text: value, style: NvText.bodyStrong),
                ])),
              ),
            NvButton(
                label: changeLabel,
                kind: NvButtonKind.secondary,
                onPressed: onChange),
          ],
        ),
      );
}
