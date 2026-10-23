import "package:flutter/material.dart";

import "tokens.dart";

/// Holds a screen's primary action at the bottom, above the tabs, so it stays visible at
/// 360 x 800 while the content scrolls above it. Place it in Scaffold.bottomNavigationBar.
class NvActionBar extends StatelessWidget {
  const NvActionBar({required this.child, super.key});

  /// The primary action, and its reason line when it is disabled.
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: NvColors.page,
          border: Border(top: BorderSide(color: NvColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, NvSpace.s3, NvSpace.gutter, NvSpace.s3),
            child: child,
          ),
        ),
      );
}
