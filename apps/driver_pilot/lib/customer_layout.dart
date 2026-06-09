import "package:flutter/material.dart";

import "driver_theme.dart";

/// Layout breakpoints for customer web (mobile vs desktop).
abstract final class CustomerBreakpoints {
  static const double tablet = 600;
  static const double desktop = 900;
  static const double contentWide = 1100;
  static const double contentNarrow = 640;
}

bool customerUseRail(double width) => width >= CustomerBreakpoints.desktop;

bool customerIsWide(double width) => width >= CustomerBreakpoints.tablet;

/// Centers customer page content with readable max width on larger screens.
class CustomerPageFrame extends StatelessWidget {
  const CustomerPageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = customerIsWide(constraints.maxWidth);
        final maxW = wide ? CustomerBreakpoints.contentWide : CustomerBreakpoints.contentNarrow;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: wide ? 8 : 0),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Two-column row on desktop; stacks on mobile.
class CustomerResponsiveRow extends StatelessWidget {
  const CustomerResponsiveRow({
    required this.primary,
    required this.secondary,
    this.secondaryFlex = 1,
    this.primaryFlex = 1,
    super.key,
  });

  final Widget primary;
  final Widget secondary;
  final int primaryFlex;
  final int secondaryFlex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= CustomerBreakpoints.desktop) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: primaryFlex, child: primary),
              const SizedBox(width: 24),
              Expanded(flex: secondaryFlex, child: secondary),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            const SizedBox(height: 16),
            secondary,
          ],
        );
      },
    );
  }
}

const List<NavigationDestination> kCustomerNavDestinations = [
  NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: "Home"),
  NavigationDestination(icon: Icon(Icons.travel_explore_outlined), selectedIcon: Icon(Icons.travel_explore), label: "Trips"),
  NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: "Book"),
  NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: "Shipments"),
];

List<NavigationRailDestination> customerRailDestinations() {
  return kCustomerNavDestinations
      .map(
        (d) => NavigationRailDestination(
          icon: d.icon,
          selectedIcon: d.selectedIcon ?? d.icon,
          label: Text(d.label),
        ),
      )
      .toList();
}

/// Branded side header for desktop customer shell.
class CustomerBrandHeader extends StatelessWidget {
  const CustomerBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "NaviG8r",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: DriverTheme.navy,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            "Book & track freight",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DriverTheme.muted),
          ),
        ],
      ),
    );
  }
}
