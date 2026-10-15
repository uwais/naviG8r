import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'driver_theme.dart';
import 'eway_bill_closed.dart';
import 'eway_bill_portal_link.dart';
import 'eway_bill_truck_form.dart';
import 'eway_bill_words.dart';

/// A shipment's e-way bill for carriers and drivers. Everyone reads it; a carrier owner or dispatcher
/// can also type in the truck once it is on the bill on the portal. The server already leaves out the
/// bill date, the maker's GSTIN and the invoice number for carrier logins.
class EwayBillCarrierCard extends StatefulWidget {
  const EwayBillCarrierCard({required this.shipment, super.key});
  final Map<String, dynamic> shipment;

  @override
  State<EwayBillCarrierCard> createState() => _EwayBillCarrierCardState();
}

class _EwayBillCarrierCardState extends State<EwayBillCarrierCard> {
  late Map<String, dynamic>? _bill = _billFrom(widget.shipment);
  bool _addingTruck = false;
  num _savedAtUtcMs = 0;

  static Map<String, dynamic>? _billFrom(Map<String, dynamic> shipment) {
    final raw = shipment['ewayBill'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  bool get _canAddTruck =>
      AuthorizationSession.can('eway_bill.add_truck') &&
      _bill?['kind'] == 'BILL' &&
      !ewayBillIsClosed(widget.shipment);

  @override
  void didUpdateWidget(EwayBillCarrierCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different shipment in the same spot starts clean; an open truck form for the old one closes.
    if (widget.shipment['id'] != oldWidget.shipment['id']) {
      _bill = _billFrom(widget.shipment);
      _addingTruck = false;
      _savedAtUtcMs = 0;
      return;
    }
    // The screen refreshes every 15 seconds. Never overwrite something half typed.
    if (_addingTruck) return;
    // A refresh that started before our own save can arrive after it; the newer server time wins.
    final parentTime = widget.shipment['updatedAtUtcMs'];
    if (parentTime is num && parentTime < _savedAtUtcMs) return;
    _bill = _billFrom(widget.shipment);
  }

  void _showSaved(Map<String, dynamic> shipment) => setState(() {
        _bill = _billFrom(shipment);
        final savedTime = shipment['updatedAtUtcMs'];
        if (savedTime is num) _savedAtUtcMs = savedTime;
        _addingTruck = false;
      });

  List<Widget> _billLines(Map<String, dynamic> bill) {
    final number = bill['billNumber'];
    final truckLines = ewayBillTruckLines(bill);
    final canAddTruck = _canAddTruck;
    final mismatch = ewayBillTruckMismatchSentence(widget.shipment, bill,
        canUpdate: canAddTruck);
    final assignedTruck = widget.shipment['assignedTruckNumber'];
    return [
      if (number is String)
        SelectableText(groupedBillNumber(number),
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: DriverTheme.navy)),
      if (truckLines.isEmpty)
        Text(canAddTruck
            ? 'Truck not on this bill yet. Add your truck to the bill on the portal, then enter it here.'
            : 'Truck not added yet.')
      else
        for (final line in truckLines) Text(line),
      if (mismatch != null) Text(mismatch),
      Text(ewayBillCheckLine(bill, forShipper: false)),
      Text(
          truckLines.isEmpty
              ? 'Shown as the shipper entered it. naviG8r has not made or changed this bill, and has not checked the truck or the expiry.'
              : 'Shown as entered in naviG8r. naviG8r has not made or changed this bill, and has not checked it against the portal.',
          style: const TextStyle(color: DriverTheme.muted)),
      if (canAddTruck && _addingTruck) ...[
        const SizedBox(height: 8),
        EwayBillTruckForm(
            path:
                '/v1/pilot/carrier/shipments/${widget.shipment['id']}/eway-bill/truck',
            current: bill,
            assignedTruckNumber: assignedTruck is String ? assignedTruck : null,
            clearsCheck: bill['check'] is Map,
            onSaved: _showSaved,
            onCancel: () => setState(() => _addingTruck = false)),
      ] else if (canAddTruck) ...[
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
                onPressed: () => setState(() => _addingTruck = true),
                child:
                    Text(truckLines.isEmpty ? 'Add truck' : 'Change truck'))),
      ],
      if (canAddTruck) const EwayBillPortalButton(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shipment = widget.shipment;
    final bill = _bill;
    final shipper = shipment['customerOrgName'] is String &&
            (shipment['customerOrgName'] as String).isNotEmpty
        ? shipment['customerOrgName'] as String
        : 'The shipper';
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
      children.addAll(_billLines(bill));
    }
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children)));
  }
}
