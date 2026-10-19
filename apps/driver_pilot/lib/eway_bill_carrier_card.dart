import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_words.dart';
import 'ui/format.dart';
import 'ui/tokens.dart';

/// A shipment's e-way bill for carriers and drivers, read only. The shipper adds the truck to the bill;
/// every carrier login only reads it, though the carrier pays any check-post fine, so it shows the
/// bill's state in words (owner decision, 18 Oct 2026). The server already leaves out the bill date,
/// the maker's GSTIN and the invoice number for carrier logins. It has no frame or title of its own:
/// the booking screen shows it inside its "Truck on the e-way bill" step.
class EwayBillCarrierCard extends StatelessWidget {
  const EwayBillCarrierCard({required this.shipment, super.key});
  final Map<String, dynamic> shipment;

  String get _shipper => shipment['customerOrgName'] is String &&
          (shipment['customerOrgName'] as String).isNotEmpty
      ? shipment['customerOrgName'] as String
      : 'The shipper';

  List<Widget> _billLines(Map<String, dynamic> bill) {
    final number = bill['billNumber'];
    final truckLines = ewayBillTruckLines(bill);
    // Naming a trip's truck and driver is what makes a login the carrier office here; a driver cannot.
    final office = AuthorizationSession.can('trip.assign');
    final mismatch = ewayBillTruckMismatchSentence(shipment, bill,
        reader: office
            ? TruckMismatchReader.carrierOffice
            : TruckMismatchReader.driver);
    return [
      // A driver reads the number out at a check post, so it is set large (dr-ewb).
      if (number is String)
        SelectableText(formatBillNumber(number),
            style: office ? NvText.id : NvText.idDisplay),
      if (truckLines.isEmpty)
        Text('$_shipper has not added the truck to the bill yet.',
            style: NvText.body)
      else
        for (final line in truckLines) Text(line, style: NvText.body),
      if (mismatch != null) Text(mismatch, style: NvText.body),
      Text(ewayBillCheckLine(bill, forShipper: false), style: NvText.body),
      Text(
          truckLines.isEmpty
              ? 'Shown as the shipper entered it. NaviG8r has not made or changed this bill, and has not checked the truck or the expiry.'
              : 'Shown as entered in NaviG8r. NaviG8r has not made or changed this bill, and has not checked it against the portal.',
          style: NvText.caption),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final raw = shipment['ewayBill'];
    final bill = raw is Map<String, dynamic> ? raw : null;
    final List<Widget> lines;
    if (bill == null) {
      lines = [
        Text('$_shipper has not added an e-way bill or said none is needed.',
            style: NvText.body)
      ];
    } else if (bill['kind'] == 'NOT_NEEDED') {
      lines = [
        Text(
            '$_shipper says no e-way bill is needed: ${notNeededReasonWords(bill)}. '
            "This is the shipper's statement. NaviG8r has not checked it.",
            style: NvText.body)
      ];
    } else {
      lines = _billLines(bill);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, line) in lines.indexed) ...[
          if (index > 0) const SizedBox(height: NvSpace.s2),
          line,
        ],
      ],
    );
  }
}
