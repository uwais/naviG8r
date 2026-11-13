import "package:flutter/material.dart";

import "authorization_session.dart";

/// Pulling down reloads who the person is and what they may do, as the header's old refresh
/// icon did. A screen with its own pull-to-refresh keeps it; this one then stays quiet.
class AccessRefresh extends StatelessWidget {
  const AccessRefresh({required this.child, super.key});
  final Widget child;

  static const _key = ValueKey("access-refresh");

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        key: _key,
        onRefresh: AuthorizationSession.refresh,
        // Nested indicators all hear the same scroll, so answer only when no screen-level
        // indicator sits between this one and the list being pulled.
        notificationPredicate: (notification) =>
            notification.depth == 0 &&
            notification.context
                    ?.findAncestorWidgetOfExactType<RefreshIndicator>()
                    ?.key ==
                _key,
        child: child,
      );
}
