import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_closed.dart';
import 'eway_bill_portal_link.dart';
import 'eway_bill_truck_form.dart';
import 'eway_bill_words.dart';
import 'ui/format.dart';
import 'ui/nv_button.dart';
import 'ui/nv_copy_row.dart';
import 'ui/tokens.dart';

/// A shipment's e-way bill for carriers and drivers. Everyone reads it; a carrier owner or dispatcher
/// can also type in the truck once it is on the bill on the portal. The server already leaves out the
/// bill date, the maker's GSTIN and the invoice number for carrier logins. It has no frame or title of
/// its own: the booking screen shows it inside its "Truck on the e-way bill" step.
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

  Widget _truckForm(Map<String, dynamic> bill) {
    final assignedTruck = widget.shipment['assignedTruckNumber'];
    return EwayBillTruckForm(
        path:
            '/v1/pilot/carrier/shipments/${widget.shipment['id']}/eway-bill/truck',
        current: bill,
        assignedTruckNumber: assignedTruck is String ? assignedTruck : null,
        clearsCheck: bill['check'] is Map,
        onSaved: _showSaved,
        onCancel: () => setState(() => _addingTruck = false));
  }

  /// ca-booking-truck: the office copies the bill number and the trip's truck into the portal's Part B.
  List<Widget> _addTruckLines(Map<String, dynamic> bill) {
    final number = bill['billNumber'];
    final tripTruck = widget.shipment['assignedTruckNumber'];
    return [
      const Text(
          'Add the truck on the portal before the goods move, then enter it here.',
          style: NvText.bodyStrong),
      if (number is String && number.isNotEmpty)
        NvCopyRow(
            label: 'E-way bill number',
            value: formatBillNumber(number),
            portalField: 'Portal: Update Part B, find the bill by this number'),
      if (tripTruck is String && tripTruck.isNotEmpty)
        NvCopyRow(
            label: 'Truck number',
            value: portalTruckNumber(tripTruck),
            portalField: 'Portal field: Vehicle No.'),
      const Text(
          "The bill's validity starts when you add the truck on the portal: one day per 200 km, ending at midnight India time.",
          style: NvText.caption),
      const Text(
          'Shown as the shipper entered it. NaviG8r has not made or changed this bill, and has not checked the truck or the expiry.',
          style: NvText.caption),
      if (_addingTruck)
        _truckForm(bill)
      else
        NvButton(
            label: 'Add truck',
            onPressed: () => setState(() => _addingTruck = true),
            fullWidth: true),
      const EwayBillPortalButton(),
    ];
  }

  List<Widget> _billLines(Map<String, dynamic> bill) {
    final number = bill['billNumber'];
    final truckLines = ewayBillTruckLines(bill);
    final canAddTruck = _canAddTruck;
    if (canAddTruck && truckLines.isEmpty) return _addTruckLines(bill);
    // Holding eway_bill.add_truck is what makes a login the carrier office here; a driver does not.
    final office = AuthorizationSession.can('eway_bill.add_truck');
    final mismatch = ewayBillTruckMismatchSentence(widget.shipment, bill,
        reader: office
            ? TruckMismatchReader.carrierOffice
            : TruckMismatchReader.driver);
    return [
      // A driver reads the number out at a check post, so it is set large (dr-ewb).
      if (number is String)
        SelectableText(formatBillNumber(number),
            style: office ? NvText.id : NvText.idDisplay),
      if (truckLines.isEmpty)
        const Text('Truck not added yet.', style: NvText.body)
      else
        for (final line in truckLines) Text(line, style: NvText.body),
      if (mismatch != null) Text(mismatch, style: NvText.body),
      Text(ewayBillCheckLine(bill, forShipper: false), style: NvText.body),
      Text(
          truckLines.isEmpty
              ? 'Shown as the shipper entered it. NaviG8r has not made or changed this bill, and has not checked the truck or the expiry.'
              : 'Shown as entered in NaviG8r. NaviG8r has not made or changed this bill, and has not checked it against the portal.',
          style: NvText.caption),
      if (canAddTruck && _addingTruck)
        _truckForm(bill)
      else if (canAddTruck)
        Align(
            alignment: Alignment.centerLeft,
            child: NvButton(
                label: 'Change truck',
                kind: NvButtonKind.secondary,
                onPressed: () => setState(() => _addingTruck = true))),
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
    final List<Widget> lines;
    if (bill == null) {
      lines = [
        Text('$shipper has not added an e-way bill or said none is needed.',
            style: NvText.body)
      ];
    } else if (bill['kind'] == 'NOT_NEEDED') {
      lines = [
        Text(
            '$shipper says no e-way bill is needed: ${notNeededReasonWords(bill)}. '
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
