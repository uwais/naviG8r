import 'package:flutter/widgets.dart';

/// True while the app is hidden, paused or detached. The timed checks (the screens' 15 s and 30 s
/// checks and the bell) skip their turn then, and each checks once when the app is shown again.
/// A trip's location sharing is not a timed check, and this does not stop it.
bool get appIsInBackground => switch (WidgetsBinding.instance.lifecycleState) {
      AppLifecycleState.hidden ||
      AppLifecycleState.paused ||
      AppLifecycleState.detached =>
        true,
      _ => false,
    };
