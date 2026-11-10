import 'package:flutter/material.dart';

import 'driver_session.dart';
import 'ui/nv_list_card.dart';

/// In place of an empty trip list. The server shows a driver only their own trips, so for a driver an empty list
/// means none yet. Everyone else sees nothing here.
class UnassignedDriverNotice extends StatelessWidget {
  const UnassignedDriverNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (DriverSession.carrierRole != 'DRIVER') return const SizedBox.shrink();
    return const NvListEmpty(
        title:
            'Your office has not given you a trip yet. Ask your office for one.');
  }
}
