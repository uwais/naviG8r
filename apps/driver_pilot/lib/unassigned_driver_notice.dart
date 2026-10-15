import 'package:flutter/material.dart';

import 'driver_session.dart';
import 'driver_theme.dart';

/// Under an empty trip list. The server shows a driver only their own trips, so for a driver an empty list
/// means none yet. Everyone else sees nothing here.
class UnassignedDriverNotice extends StatelessWidget {
  const UnassignedDriverNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (DriverSession.carrierRole != 'DRIVER') return const SizedBox.shrink();
    return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: Text(
            'Your carrier has not assigned you a trip yet. Ask your carrier to assign one.',
            style: TextStyle(color: DriverTheme.mutedOnBackground)));
  }
}
