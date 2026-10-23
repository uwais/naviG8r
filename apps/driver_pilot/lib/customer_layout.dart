import "package:flutter/material.dart";

import "ui/nv_header.dart";
import "ui/tokens.dart";

/// Shipper layout sizes. From [desktop] wide the screens use the top bar and two columns
/// (mockups wb-*); below it they use the phone layout, centred.
abstract final class CustomerBreakpoints {
  static const double desktop = 1024;
  static const double contentMax = 1200;
  static const double phoneContentMax = 640;
  static const double desktopGutter = 32;
  static const double sideColumn = 340;

  /// The narrowest a lane card gets in the desktop grid.
  static const double laneCardMin = 320;

  /// Below this width the shipments table scrolls sideways inside its own box.
  static const double tableMin = 880;
}

bool customerIsDesktop(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= CustomerBreakpoints.desktop;

/// Centres a shipper page's content: up to 1200 wide on a desktop, a phone column otherwise.
class CustomerPageFrame extends StatelessWidget {
  const CustomerPageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final desktop = customerIsDesktop(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: desktop
                ? CustomerBreakpoints.contentMax +
                    2 * CustomerBreakpoints.desktopGutter
                : CustomerBreakpoints.phoneContentMax),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal:
                  desktop ? CustomerBreakpoints.desktopGutter : NvSpace.gutter),
          child: child,
        ),
      ),
    );
  }
}

const List<NavigationDestination> kCustomerNavDestinations = [
  NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: "Home"),
  NavigationDestination(
      icon: Icon(Icons.travel_explore_outlined),
      selectedIcon: Icon(Icons.travel_explore),
      label: "Book a trip"),
  NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: "Shipments"),
];

/// The desktop top bar: [header] carries the links and the account button, lined up with the
/// page's content below it.
class CustomerTopBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomerTopBar({required this.header, super.key});

  final NvHeader header;

  @override
  Size get preferredSize => header.preferredSize;

  // The header draws the same bottom line in the same place, so the two read as one line.
  @override
  Widget build(BuildContext context) => Material(
        color: NvColors.page,
        shape: const Border(bottom: BorderSide(color: NvColors.line)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: CustomerBreakpoints.desktopGutter - NvSpace.s2),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: CustomerBreakpoints.contentMax + 2 * NvSpace.s2),
              child: header,
            ),
          ),
        ),
      );
}

/// The name and the three tabs as links, for the desktop top bar. The links scroll sideways
/// rather than overflow when large text meets a narrow window.
class CustomerTopNavigation extends StatelessWidget {
  const CustomerTopNavigation(
      {required this.selectedIndex, required this.onSelect, super.key});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: NvSpace.s2, right: NvSpace.s6),
          child: Text("NaviG8r",
              style: NvText.heading.copyWith(fontWeight: FontWeight.w800)),
        ),
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (index, destination)
                  in kCustomerNavDestinations.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: NvSpace.s1),
                  child: _TopNavigationLink(
                      label: destination.label,
                      selected: index == selectedIndex,
                      onTap: () => onSelect(index)),
                ),
            ]),
          ),
        ),
      ]);
}

class _TopNavigationLink extends StatelessWidget {
  const _TopNavigationLink(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
          selected: selected,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, NvSpace.targetMin),
              padding: const EdgeInsets.symmetric(horizontal: NvSpace.s3),
              backgroundColor: selected ? NvColors.navIndicator : null,
              foregroundColor: selected ? NvColors.navyInk : NvColors.slate,
              textStyle: NvText.bodyStrong,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(NvRadius.button)),
            ),
            child: Text(label),
          ),
        ),
      );
}
