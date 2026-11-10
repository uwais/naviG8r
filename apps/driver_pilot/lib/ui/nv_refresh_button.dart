import "package:flutter/material.dart";

import "tokens.dart";

/// Loads the screen again, for when the other party has changed something. Pull-to-refresh is
/// not enough on its own: Flutter does not drag a list with a mouse, so on a desktop browser a
/// pull never starts. While loading it shows a ring and cannot be pressed.
class NvRefreshButton extends StatelessWidget {
  const NvRefreshButton(
      {required this.loading, required this.onPressed, super.key});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: "Refresh",
        onPressed: loading ? null : onPressed,
        color: NvColors.navyInk,
        constraints: const BoxConstraints(
            minWidth: NvSpace.targetMin, minHeight: NvSpace.targetMin),
        icon: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
      );
}
