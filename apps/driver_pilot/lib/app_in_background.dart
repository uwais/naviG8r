import 'package:flutter/widgets.dart';

/// True while the app is hidden or paused. Timed checks skip their turn then, so a phone in a
/// pocket sends no requests; each checks once when the app is shown again.
bool get appIsInBackground => switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        true,
      _ => false,
    };
