import "package:flutter/material.dart";

import "tokens.dart";

/// One section of a screen on a white card, such as "Truck and driver" or "Trucks (3)": its heading, an
/// optional action beside it (it moves under the heading when there is no room), then the content.
class NvSectionCard extends StatelessWidget {
  const NvSectionCard(
      {required this.title, required this.children, this.action, super.key});

  final String title;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NvSpace.s3,
              runSpacing: NvSpace.s2,
              children: [
                Semantics(
                    header: true, child: Text(title, style: NvText.heading)),
                if (action != null) action!,
              ],
            ),
            ...children,
          ],
        ),
      );
}
