import 'package:flutter/material.dart';

import 'driver_theme.dart';
import 'eway_bill_words.dart';

/// Read-only view of a shipment's e-way bill for carriers and drivers. The server already leaves out
/// the bill date, the maker's GSTIN and the invoice number for carrier logins.
class EwayBillCarrierCard extends StatelessWidget {
  const EwayBillCarrierCard({required this.shipment, super.key});
  final Map<String, dynamic> shipment;

  @override
  Widget build(BuildContext context) {
    final raw = shipment['ewayBill'];
    final bill = raw is Map<String, dynamic> ? raw : null;
    final shipper = shipment['customerOrgName'] is String &&
            (shipment['customerOrgName'] as String).isNotEmpty
        ? shipment['customerOrgName'] as String
        : 'The shipper';
    final number = bill?['billNumber'];
    final children = <Widget>[
      Text('E-way bill', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
    ];
    if (bill == null) {
      children.add(
          Text('$shipper has not added an e-way bill or said none is needed.'));
    } else if (bill['kind'] == 'NOT_NEEDED') {
      children.add(Text(
          '$shipper says no e-way bill is needed: ${notNeededReasonWords(bill)}. '
          "This is the shipper's statement. naviG8r has not checked it."));
    } else {
      children.addAll([
        if (number is String)
          SelectableText(groupedBillNumber(number),
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: DriverTheme.navy)),
        Text(ewayBillCheckLine(bill, forShipper: false)),
        const Text(
            'Shown as the shipper entered it. naviG8r has not made or changed this bill, and has not checked the truck or the expiry.',
            style: TextStyle(color: DriverTheme.muted)),
      ]);
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)));
  }
}
