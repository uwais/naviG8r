import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../access_refresh.dart";
import "../customer_layout.dart";
import "../customer_session.dart";
import "../driver_theme.dart";
import "../signed_in_header.dart";
import "../ui/nv_header.dart";
import "../ui/tokens.dart";

class CustomerScaffold extends StatelessWidget {
  const CustomerScaffold({
    required this.title,
    required this.currentPath,
    required this.bodyBuilder,
    this.subtitle,
    this.actionBar,
    this.sideBuilder,
    this.titleFocus,
    super.key,
  });

  final String title;
  final String currentPath;
  final WidgetBuilder bodyBuilder;

  /// One line under the title, such as "Check the price, then pay."
  final String? subtitle;

  /// The screen's primary action, held at the bottom in place of the tabs (NvActionBar).
  final Widget? actionBar;

  /// The column beside the main one on a desktop, such as the price and Pay on Book. Only
  /// passed at desktop width: on a phone the screen puts the same widgets in its one column.
  final WidgetBuilder? sideBuilder;

  /// Lets the screen move focus to its title, as after a booking opens the new shipment.
  final FocusNode? titleFocus;

  // Book has no tab: it opens from a lane card, so it sits under Find a lane.
  int _indexForPath(String path) {
    if (path.startsWith("/customer/trips") ||
        path.startsWith("/customer/eligible") ||
        path.startsWith("/customer/book")) return 1;
    if (path.startsWith("/customer/shipments")) return 2;
    return 0;
  }

  static const _tabPaths = [
    "/customer",
    "/customer/trips",
    "/customer/shipments"
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CustomerSession.listenable,
      builder: (context, _) {
        final selected = _indexForPath(currentPath);
        final tabRoot = _tabPaths[selected];
        final desktop = customerIsDesktop(context);
        final backLabel = currentPath == tabRoot
            ? null
            : kCustomerNavDestinations[selected].label;
        void goBack() => context.go(tabRoot);
        void goToIndex(int index) {
          final target = _tabPaths[index];
          if (target != currentPath) context.go(target);
        }

        final signedIn = CustomerSession.isSignedIn;
        final body = bodyBuilder(context);
        final heading = Semantics(
            header: true,
            child: Text(title, style: desktop ? NvText.display : NvText.title));
        final page = CustomerPageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.only(top: NvSpace.s4, bottom: NvSpace.s2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The top bar holds the tabs, so on a desktop Back sits above the title.
                    if (desktop && signedIn && backLabel != null) ...[
                      TextButton.icon(
                        onPressed: goBack,
                        icon: const Icon(Icons.chevron_left, size: 22),
                        label: Text(backLabel),
                        style: TextButton.styleFrom(
                            foregroundColor: NvColors.navyInk,
                            minimumSize: const Size(0, NvSpace.targetMin)),
                      ),
                      const SizedBox(height: NvSpace.s2),
                    ],
                    if (titleFocus == null)
                      heading
                    else
                      Focus(focusNode: titleFocus, child: heading),
                    if (subtitle != null) ...[
                      const SizedBox(height: NvSpace.s1),
                      Text(subtitle!, style: NvText.body),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: sideBuilder == null
                    ? body
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: body),
                          const SizedBox(width: NvSpace.s6),
                          SizedBox(
                            width: CustomerBreakpoints.sideColumn,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                  vertical: NvSpace.s3),
                              child: sideBuilder!(context),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );

        if (!signedIn) {
          // Signed out: no account header and no tabs, only a way back to the start screen.
          return Scaffold(
            backgroundColor: DriverTheme.background,
            appBar: NvHeader.task(
                backLabel: "Back", onBack: () => context.go("/customer")),
            body: SafeArea(child: page),
          );
        }

        if (desktop) {
          return Scaffold(
            backgroundColor: DriverTheme.background,
            appBar: CustomerTopBar(
              header: signedInHeader(context,
                  navigation: CustomerTopNavigation(
                      selectedIndex: selected, onSelect: goToIndex)),
            ),
            body: SafeArea(child: AccessRefresh(child: page)),
            bottomNavigationBar: actionBar,
          );
        }

        return Scaffold(
          backgroundColor: DriverTheme.background,
          appBar: signedInHeader(
            context,
            backLabel: backLabel,
            onBack: backLabel == null ? null : goBack,
          ),
          body: SafeArea(child: AccessRefresh(child: page)),
          bottomNavigationBar: actionBar ??
              NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: goToIndex,
                destinations: kCustomerNavDestinations,
              ),
        );
      },
    );
  }
}
