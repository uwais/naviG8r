import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'driver_theme.dart';
import 'eway_bill_words.dart';

/// What the shipper types on the portal for the truck part of the e-way bill, ready to copy: the truck the
/// carrier named for the trip, in the portal's form, and the carrier's transporter ID. Shown while the shipment
/// is booked, from acceptance until the driver confirms delivery, and only until the bill in naviG8r has a
/// truck, so both parts of the bill can be made in one portal visit (owner decision, 16 Oct 2026). Nothing
/// while the trip names no truck, or after the shipper said no bill is needed.
class EwayBillCopyBox extends StatelessWidget {
  const EwayBillCopyBox(
      {required this.shipment, required this.bill, super.key});
  final Map<String, dynamic> shipment;

  /// The bill as the card holds it, which is newer than the shipment's own right after a save.
  final Map<String, dynamic>? bill;

  bool get _billNeedsTruck {
    final current = bill;
    if (current == null) return true;
    final truck = current['truckNumber'];
    return current['kind'] == 'BILL' && (truck is! String || truck.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final tripTruck = shipment['assignedTruckNumber'];
    final truck = tripTruck is String ? portalTruckNumber(tripTruck) : '';
    // After delivery, entering the truck is too late: a bill made then covers no journey.
    if (truck.isEmpty || shipment['status'] != 'BOOKED' || !_billNeedsTruck) {
      return const SizedBox.shrink();
    }
    final givenId = shipment['carrierTransporterId'];
    final transporterId =
        givenId is String && givenId.isNotEmpty ? givenId : null;
    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            border: Border.all(color: DriverTheme.border),
            borderRadius: BorderRadius.circular(12)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('For the e-way bill',
                  style: Theme.of(context).textTheme.titleSmall),
              _CopyLine(
                  label: 'Truck', value: truck, copiedWords: 'truck number'),
              if (transporterId != null)
                _CopyLine(
                    label: 'Transporter ID',
                    value: transporterId,
                    copiedWords: 'transporter ID'),
              Text(transporterId != null
                  ? 'On the portal, enter this transporter ID so your carrier can change the truck later. Validity starts when the first truck is entered, so enter the truck on loading day, before the goods move. If the goods are already on the way, enter the truck now.'
                  : 'Your carrier has not added a transporter ID yet; ask them for one. Without a transporter ID on the bill, only whoever made the bill can change the truck. Validity starts when the first truck is entered, so enter the truck on loading day, before the goods move. If the goods are already on the way, enter the truck now.'),
            ]));
  }
}

/// "Truck: UP010345" with a Copy button that puts only the value on the clipboard.
class _CopyLine extends StatelessWidget {
  const _CopyLine(
      {required this.label, required this.value, required this.copiedWords});
  final String label;
  final String value;

  /// Names what was copied in the confirmation, for example "truck number".
  final String copiedWords;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Copied $copiedWords')));
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text('$label: $value')),
        TextButton(onPressed: () => _copy(context), child: const Text('Copy')),
      ]);
}
