// Over 500 lines on purpose: one card whose four modes share one state (its form controllers and
// the save in flight); splitting the forms out would pass that state between files.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'authorization_session.dart';
import 'eway_bill_closed.dart';
import 'eway_bill_dates.dart';
import 'eway_bill_error_text.dart';
import 'eway_bill_portal_link.dart';
import 'eway_bill_transport_details.dart';
import 'eway_bill_truck_form.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';
import 'ui/format.dart';
import 'ui/nv_button.dart';
import 'ui/nv_choice.dart';
import 'ui/nv_field.dart';
import 'ui/nv_message.dart';
import 'ui/tokens.dart';

enum _Mode { viewing, addingBill, statingNotNeeded, addingTruck }

const ewayBillFootnote =
    'NaviG8r does not make or change e-way bills.';

/// True for the shipper who booked this shipment, holding eway_bill.write, while the server
/// still takes changes to its bill.
bool shipperCanWriteEwayBill(Map<String, dynamic> shipment) =>
    AuthorizationSession.hasRole('SHIPPER') &&
    AuthorizationSession.can('eway_bill.write') &&
    shipment['customerOrgId'] == AuthorizationSession.organizationId &&
    !ewayBillIsClosed(shipment);

/// The words of the shipper's e-way bill step. The bill is made in the shipper's billing software
/// or on the e-way bill site; this only holds the details the shipper types in and shows what
/// NaviG8r staff saw when they looked the bill up. It sits inside the shipment's step list; the
/// portal button for part 1 is the screen's primary action, in its action bar on a phone and in
/// this panel on a desktop.
class EwayBillCard extends StatefulWidget {
  const EwayBillCard(
      {required this.shipment,
      this.onSaved,
      this.portalButtonInPanel = false,
      this.tripStarted = false,
      super.key});
  final Map<String, dynamic> shipment;

  /// The trip has left, so a passed valid-until time no longer stops it starting, and the bill can no
  /// longer be removed. The shipment alone cannot say so while it is on the way; the screen knows from
  /// the trip.
  final bool tripStarted;

  /// Puts part 1's "Open the e-way bill portal" in this panel, for a desktop that has no action
  /// bar to hold it.
  final bool portalButtonInPanel;

  /// The shipment the server returned after a save, so the screen's steps move on at once.
  final ValueChanged<Map<String, dynamic>>? onSaved;

  @override
  State<EwayBillCard> createState() => _EwayBillCardState();
}

class _EwayBillCardState extends State<EwayBillCard> {
  _Mode _mode = _Mode.viewing;
  late Map<String, dynamic>? _bill = _billFrom(widget.shipment);
  final _number = TextEditingController();
  final _gstin = TextEditingController();
  final _invoice = TextEditingController();
  final _note = TextEditingController();
  String? _billDate;
  String? _reason;
  bool _busy = false;
  String? _error;
  String? _formSummary;
  final _formSummaryFocus = FocusNode();
  String? _numberError;
  String? _gstinError;
  num _savedAtUtcMs = 0;

  /// A saved bill with its truck shows only its summary until the shipper asks to change it
  /// (Uwais, 22 Oct 2026: the done step read as too busy).
  bool _changesShown = false;

  static Map<String, dynamic>? _billFrom(Map<String, dynamic> shipment) {
    final raw = shipment['ewayBill'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  bool get _canEdit => shipperCanWriteEwayBill(widget.shipment);

  bool get _canAddTruck =>
      _canEdit && AuthorizationSession.can('eway_bill.add_truck');

  String? get _carrierName {
    final name = widget.shipment['carrierDisplayName']?.toString() ?? '';
    return name.trim().isEmpty ? null : name.trim();
  }

  /// The carrier's transporter ID, sent to shippers only once the carrier has accepted.
  String? get _transporterId {
    final id = widget.shipment['carrierTransporterId'];
    return id is String && id.trim().isNotEmpty ? id.trim() : null;
  }

  /// The truck the carrier named for the trip, in the portal's form.
  String? get _tripTruck {
    final truck = widget.shipment['assignedTruckNumber'];
    if (truck is! String) return null;
    final portalForm = portalTruckNumber(truck);
    return portalForm.isEmpty ? null : portalForm;
  }

  @override
  void didUpdateWidget(EwayBillCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different shipment in the same spot starts clean; nothing typed for the old one may carry over.
    if (widget.shipment['id'] != oldWidget.shipment['id']) {
      _mode = _Mode.viewing;
      _bill = _billFrom(widget.shipment);
      _savedAtUtcMs = 0;
      _changesShown = false;
      _clearErrors();
      _busy = false;
      _billDate = null;
      _reason = null;
      for (final controller in [_number, _gstin, _invoice, _note]) {
        controller.clear();
      }
      return;
    }
    // The screen refreshes every 15 seconds. Never overwrite something half typed.
    if (_mode != _Mode.viewing || _busy) return;
    // A refresh that started before our own save can arrive after it; the newer server time wins.
    final parentTime = widget.shipment['updatedAtUtcMs'];
    if (parentTime is num && parentTime < _savedAtUtcMs) return;
    _bill = _billFrom(widget.shipment);
  }

  @override
  void dispose() {
    _number.dispose();
    _gstin.dispose();
    _invoice.dispose();
    _note.dispose();
    _formSummaryFocus.dispose();
    super.dispose();
  }

  void _clearErrors() {
    _error = null;
    _formSummary = null;
    _numberError = null;
    _gstinError = null;
  }

  void _openBillForm() {
    if (_busy) return;
    final bill = _bill;
    final editing = bill != null && bill['kind'] == 'BILL';
    setState(() {
      _number.text = editing ? '${bill['billNumber'] ?? ''}' : '';
      _gstin.text = editing ? '${bill['makerGstin'] ?? ''}' : '';
      _invoice.text = editing ? '${bill['invoiceNumber'] ?? ''}' : '';
      _billDate = editing ? bill['billDate'] as String? : null;
      _clearErrors();
      _mode = _Mode.addingBill;
    });
  }

  void _openStatementForm() {
    if (_busy) return;
    final bill = _bill;
    final editing = bill != null && bill['kind'] == 'NOT_NEEDED';
    setState(() {
      _reason = editing ? bill['notNeededReason'] as String? : null;
      _note.text = editing ? '${bill['notNeededNote'] ?? ''}' : '';
      _clearErrors();
      _mode = _Mode.statingNotNeeded;
    });
  }

  void _openTruckForm() {
    if (_busy) return;
    setState(() {
      _clearErrors();
      _mode = _Mode.addingTruck;
    });
  }

  void _cancel() => setState(() {
        _clearErrors();
        _mode = _Mode.viewing;
      });

  Future<void> _chooseDate() async {
    final today = indiaToday();
    final current = _billDate == null ? null : DateTime.tryParse(_billDate!);
    final initial =
        current != null && !current.isAfter(today) ? current : today;
    final oneYearBack = DateTime(today.year - 1);
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        // An older saved date must still open the picker, so the range reaches back to it.
        firstDate: initial.isBefore(oneYearBack) ? initial : oneYearBack,
        lastDate: today);
    if (picked == null || !mounted) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() => _billDate = '${picked.year}-$month-$day');
  }

  // Checks the two mistakes testers made, before anything is sent (spec/copy.md, step 2 errors).
  // The GSTIN check runs only when the carrier's transporter ID is on this screen to compare with.
  bool _formHasFieldErrors() {
    final digits = _number.text.replaceAll(RegExp(r'[\s-]'), '');
    _numberError = RegExp(r'^\d+$').hasMatch(digits) && digits.length != 12
        ? 'This has ${digits.length} digits. An e-way bill number has 12.'
        : null;
    final transporterId = _transporterId;
    String squeezed(String text) =>
        text.replaceAll(RegExp(r'\s'), '').toUpperCase();
    _gstinError = transporterId != null &&
            _gstin.text.trim().isNotEmpty &&
            squeezed(_gstin.text) == squeezed(transporterId)
        ? "This is the carrier's transporter ID. Enter the GSTIN that made the bill."
        : null;
    final count = [_numberError, _gstinError].whereType<String>().length;
    _formSummary = switch (count) {
      0 => null,
      1 => '1 detail needs fixing before you can save.',
      _ => '$count details need fixing before you can save.',
    };
    return count > 0;
  }

  Future<void> _saveBill() async {
    final direction = Directionality.of(context);
    final date = _billDate;
    setState(() => _error = null);
    if (_formHasFieldErrors()) {
      setState(() {});
      _showFormSummary(direction);
      return;
    }
    if (_number.text.trim().isEmpty ||
        date == null ||
        _gstin.text.trim().isEmpty ||
        _invoice.text.trim().isEmpty) {
      setState(() => _formSummary = 'Fill in all four details to save.');
      _showFormSummary(direction);
      return;
    }
    setState(() => _formSummary = null);
    await _submit('/shipments/${widget.shipment['id']}/eway-bill', {
      'kind': 'BILL',
      'billNumber': _number.text,
      'billDate': date,
      'makerGstin': _gstin.text,
      'invoiceNumber': _invoice.text,
    });
  }

  // A failed save says how many details need fixing, then focus moves to that summary
  // (accessibility.md, e-way bill form).
  void _showFormSummary(TextDirection direction) {
    SemanticsService.announce(_formSummary!, direction,
        assertiveness: Assertiveness.assertive);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _formSummaryFocus.requestFocus();
    });
  }

  Future<void> _saveStatement() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Choose why no e-way bill is needed.');
      return;
    }
    await _submit('/shipments/${widget.shipment['id']}/eway-bill', {
      'kind': 'NOT_NEEDED',
      'reason': reason,
      if (reason == 'OTHER') 'note': _note.text,
    });
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Remove the e-way bill?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Keep it')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Remove')),
              ],
            ));
    if (!mounted || confirmed != true) return;
    await _submit('/shipments/${widget.shipment['id']}/eway-bill/remove', null);
  }

  Future<void> _submit(String path, Map<String, dynamic>? data) async {
    if (_busy) return;
    final scope = AuthorizationSession.scopeKey;
    final shipmentId = widget.shipment['id'];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(path, data: data);
      if (!mounted ||
          scope != AuthorizationSession.scopeKey ||
          shipmentId != widget.shipment['id']) {
        return;
      }
      final shipment = response.data?['shipment'];
      _showSaved(shipment is Map<String, dynamic> ? shipment : null);
    } catch (e) {
      if (mounted && shipmentId == widget.shipment['id']) {
        setState(() => _error = ewayBillErrorSentence(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSaved(Map<String, dynamic>? shipment) {
    setState(() {
      _bill = shipment == null ? null : _billFrom(shipment);
      final savedTime = shipment?['updatedAtUtcMs'];
      if (savedTime is num) _savedAtUtcMs = savedTime;
      _mode = _Mode.viewing;
      _changesShown = false;
    });
    final bill = _bill;
    if (bill != null && bill['kind'] == 'BILL') {
      final truck = bill['truckNumber'];
      SemanticsService.announce(
          truck is! String || truck.isEmpty
              ? 'E-way bill saved. The truck is not on it yet.'
              : _truckNeedsAttention(bill)
                  ? 'E-way bill saved. Check the truck and the valid-until time shown.'
                  : 'E-way bill saved. Nothing more for you to do until delivery.',
          Directionality.of(context));
    }
    if (shipment != null) widget.onSaved?.call(shipment);
  }

  List<Widget> _noBill() {
    final canEdit = _canEdit;
    final status = widget.shipment['status'];
    final actions = canEdit
        ? [
            const SizedBox(height: NvSpace.s3),
            NvButton(
                label: 'Enter the bill details',
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: _openBillForm),
            const SizedBox(height: NvSpace.s2),
            NvButton(
                label: 'Say no e-way bill is needed',
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: _openStatementForm),
          ]
        : const <Widget>[];
    if (status == 'PENDING_CARRIER_ACCEPT') {
      final truck = _tripTruck;
      return [
        Text(
            'Make the bill after ${_carrierName ?? "the carrier"} accepts. We will tell you.',
            style: NvText.body),
        const SizedBox(height: NvSpace.s3),
        EwayBillTransportDetails(
            carrierName: _carrierName,
            carrierAccepted: false,
            truckNumber: truck),
        ...actions,
      ];
    }
    if (status != 'BOOKED') {
      return [
        Text(
            ewayBillIsClosed(widget.shipment)
                ? 'No e-way bill was added.'
                : 'No e-way bill added yet.',
            style: NvText.body),
        ...actions,
      ];
    }
    return [
      Text(
          'Make the bill on loading day, in your billing software or on the portal. Copy in these details:',
          style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
      const SizedBox(height: NvSpace.s3),
      EwayBillTransportDetails(
          carrierName: _carrierName,
          carrierAccepted: true,
          transporterId: _transporterId,
          truckNumber: _tripTruck),
      // Under the portal button, so a 1280 x 900 desktop still shows that button without scrolling.
      if (canEdit && widget.portalButtonInPanel) ...[
        const SizedBox(height: NvSpace.s3),
        const EwayBillPortalButton(
            label: 'Open the e-way bill portal', kind: NvButtonKind.primary),
      ],
      const SizedBox(height: NvSpace.s3),
      const Text(
          'The trip cannot start until the bill is here, or you say none is needed.',
          style: NvText.body),
      ...actions,
    ];
  }

  List<Widget> _notNeeded(Map<String, dynamic> bill) {
    final entered = bill['enteredAtUtcMs'];
    return [
      if (entered is num)
        Text(
            'You said so on ${formatDate(DateTime.fromMillisecondsSinceEpoch(entered.toInt(), isUtc: true))}.',
            style: NvText.body),
      Text('Reason: ${notNeededReasonWords(bill)}', style: NvText.caption),
      if (_canEdit)
        Wrap(spacing: NvSpace.s2, children: [
          NvButton(
              label: 'Change',
              kind: NvButtonKind.quiet,
              onPressed: _openStatementForm),
          // The server refuses removal once the trip has started.
          if (!widget.tripStarted)
            NvButton(
                label: 'Remove e-way bill',
                kind: NvButtonKind.quiet,
                onPressed: _remove,
                loading: _busy),
        ]),
      EwayBillErrorText(_error),
    ];
  }

  Widget _fact(String label, String value, {bool identifier = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s1),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: NvSpace.s3,
          children: [
            Text(label, style: NvText.caption),
            Text(value,
                style: identifier
                    ? NvText.id.copyWith(fontWeight: FontWeight.w600)
                    : NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
          ],
        ),
      );

  String? _validUntilWords(Map<String, dynamic> bill) {
    final validUntil = bill['validUntilUtcMs'];
    if (validUntil is! num) return null;
    final moment =
        DateTime.fromMillisecondsSinceEpoch(validUntil.toInt(), isUtc: true);
    return '${formatDate(moment)}, ${formatTimeIst(moment)}';
  }

  List<Widget> _billWithoutTruck(Map<String, dynamic> bill) {
    final number = bill['billNumber'];
    // The server refuses a truck before the carrier accepts.
    final accepted = widget.shipment['status'] == 'BOOKED';
    final waitingForCarrier =
        widget.shipment['status'] == 'PENDING_CARRIER_ACCEPT';
    final canAddTruck = _canAddTruck && !waitingForCarrier;
    return [
      Text.rich(TextSpan(style: NvText.body, children: [
        const TextSpan(text: 'Bill '),
        TextSpan(
            text: formatBillNumber(number is String ? number : ''),
            style: NvText.id),
        const TextSpan(text: ' saved. The truck is not on it yet.'),
      ])),
      if (_canAddTruck) ...[
        const SizedBox(height: NvSpace.s3),
        Text(
            waitingForCarrier
                ? 'Add the truck after ${_carrierName ?? "the carrier"} accepts.'
                : 'Add the truck on the portal, then here. The trip cannot start until you do.',
            style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
      ],
      if (accepted || waitingForCarrier) ...[
        const SizedBox(height: NvSpace.s3),
        EwayBillTransportDetails(
            carrierName: _carrierName,
            carrierAccepted: accepted,
            transporterId: accepted ? _transporterId : null,
            truckNumber: accepted ? _tripTruck : null,
            truckPortalField: 'Portal: Update Part B, Vehicle No.'),
      ],
      const SizedBox(height: NvSpace.s3),
      const Text(
          'The bill runs one day per 200 km from when the truck is added, to midnight India time.',
          style: NvText.caption),
      if (bill['check'] is Map) ...[
        const SizedBox(height: NvSpace.s2),
        Text(ewayBillCheckLine(bill, forShipper: true),
            style: NvText.caption),
      ],
      if (canAddTruck) ...[
        const SizedBox(height: NvSpace.s3),
        NvButton(
            label: 'Add truck', fullWidth: true, onPressed: _openTruckForm),
        const SizedBox(height: NvSpace.s2),
        const EwayBillPortalButton(
            label: 'Open the e-way bill portal', kind: NvButtonKind.quiet),
      ],
    ];
  }

  List<Widget> _billProblem(Map<String, dynamic> bill) => [
        Text('NaviG8r found a difference',
            style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
        const SizedBox(height: NvSpace.s2),
        Text(ewayBillCheckLine(bill, forShipper: true), style: NvText.body),
        const SizedBox(height: NvSpace.s2),
        const Text(
            'If the bill is wrong, fix it on the portal first. Then fix it here.',
            style: NvText.body),
        if (_canEdit) ...[
          const SizedBox(height: NvSpace.s3),
          NvButton(
              label: 'Fix the details',
              fullWidth: true,
              onPressed: _openBillForm),
        ],
        const SizedBox(height: NvSpace.s3),
        if (bill['billNumber'] is String)
          _fact('Bill number', formatBillNumber(bill['billNumber'] as String),
              identifier: true),
        if (bill['billDate'] is String)
          _fact('Bill date', _calendarDateWords(bill['billDate'] as String)),
        if (bill['makerGstin'] is String)
          _fact('Your GSTIN', bill['makerGstin'] as String, identifier: true),
        if (bill['invoiceNumber'] is String)
          _fact('Invoice number', bill['invoiceNumber'] as String,
              identifier: true),
        if (bill['truckNumber'] is String)
          _fact('Truck', bill['truckNumber'] as String, identifier: true),
      ];

  List<Widget> _billWithTruck(Map<String, dynamic> bill) {
    final checked = bill['check'] is Map;
    final validUntil = _validUntilWords(bill);
    final mismatch = ewayBillTruckMismatchSentence(widget.shipment, bill,
        reader: TruckMismatchReader.shipper);
    return [
      // "Nothing more to do" would contradict a wrong truck or a passed valid-until time shown below it.
      if (!checked &&
          !_truckNeedsAttention(bill) &&
          !ewayBillIsClosed(widget.shipment)) ...[
        const NvMessage(
            'E-way bill saved. Nothing more for you to do until delivery.',
            tone: NvMessageTone.good),
        const SizedBox(height: NvSpace.s3),
      ],
      if (bill['billNumber'] is String)
        _fact('Bill number', formatBillNumber(bill['billNumber'] as String),
            identifier: true),
      _fact('Truck', bill['truckNumber'] as String, identifier: true),
      if (validUntil != null) _fact('Valid until', validUntil),
      // The countdown and the has-passed reminder, after the truck and valid-until lines.
      for (final line in ewayBillTruckLines(bill,
              forShipper: true, tripStarted: widget.tripStarted)
          .skip(2))
        Text(line, style: NvText.caption),
      if (mismatch != null) ...[
        const SizedBox(height: NvSpace.s2),
        Text(mismatch, style: NvText.body),
      ],
      if (checked) ...[
        const SizedBox(height: NvSpace.s2),
        Text(ewayBillCheckLine(bill, forShipper: true), style: NvText.caption),
      ],
    ];
  }

  /// The truck on the bill differs from the trip's, or the valid-until time has passed.
  bool _truckNeedsAttention(Map<String, dynamic> bill) {
    final validUntilMs = bill['validUntilUtcMs'];
    return ewayBillTruckMismatchSentence(widget.shipment, bill,
                reader: TruckMismatchReader.shipper) !=
            null ||
        (validUntilMs is num &&
            validUntilMs <= DateTime.now().millisecondsSinceEpoch);
  }

  // Read from this card's own bill, which a save updates before the screen's shipment does. Only a
  // shipper who can change the bill gets the summary; anything wrong with it keeps the changes open.
  bool get _summaryOnly {
    final bill = _bill;
    if (!_canEdit ||
        _changesShown ||
        _mode != _Mode.viewing ||
        bill?['kind'] != 'BILL') {
      return false;
    }
    final truck = bill!['truckNumber'];
    final check = bill['check'];
    return truck is String &&
        truck.isNotEmpty &&
        !(check is Map && check['result'] == 'PROBLEM') &&
        !_truckNeedsAttention(bill);
  }

  List<Widget> _billActions(Map<String, dynamic> bill) {
    if (!_canEdit) return const [];
    final truck = bill['truckNumber'];
    final hasTruck = truck is String && truck.isNotEmpty;
    if (_summaryOnly) {
      return [
        const SizedBox(height: NvSpace.s2),
        Align(
            alignment: Alignment.centerLeft,
            child: NvButton(
                label: 'Change or remove the e-way bill',
                kind: NvButtonKind.quiet,
                onPressed: () => setState(() => _changesShown = true))),
      ];
    }
    return [
      const SizedBox(height: NvSpace.s2),
      Wrap(spacing: NvSpace.s2, children: [
        NvButton(
            label: 'Edit the bill', kind: NvButtonKind.quiet, onPressed: _openBillForm),
        if (hasTruck && _canAddTruck)
          NvButton(
              label: 'Change truck',
              kind: NvButtonKind.quiet,
              onPressed: _openTruckForm),
        // The server refuses removal once the trip has started.
        if (!widget.tripStarted)
          NvButton(
              label: 'Remove e-way bill',
              kind: NvButtonKind.quiet,
              onPressed: _remove,
              loading: _busy),
      ]),
    ];
  }

  List<Widget> _viewing() {
    final bill = _bill;
    if (bill == null) return _noBill();
    if (bill['kind'] == 'NOT_NEEDED') return _notNeeded(bill);
    final check = bill['check'];
    final truck = bill['truckNumber'];
    final body = check is Map && check['result'] == 'PROBLEM'
        ? _billProblem(bill)
        : truck is String && truck.isNotEmpty
            ? _billWithTruck(bill)
            : _billWithoutTruck(bill);
    return [...body, ..._billActions(bill), EwayBillErrorText(_error)];
  }

  List<Widget> _billForm() {
    final checked = _bill?['check'] is Map;
    final date = _billDate;
    return [
      const Text('E-WAY BILL · STEP 2 OF 2', style: NvText.label),
      const SizedBox(height: NvSpace.s1),
      Semantics(
          header: true,
          child: const Text("Enter the bill's details", style: NvText.heading)),
      const SizedBox(height: NvSpace.s1),
      const Text('Copy these four from the bill.', style: NvText.body),
      if (_formSummary != null) ...[
        const SizedBox(height: NvSpace.s3),
        Focus(
            focusNode: _formSummaryFocus,
            child: NvMessage(_formSummary!, tone: NvMessageTone.problem)),
      ],
      const SizedBox(height: NvSpace.s4),
      NvField(
          label: 'E-way bill number',
          controller: _number,
          help: '12 digits, at the top of the bill.',
          errorText: _numberError,
          identifier: true,
          keyboardType: TextInputType.number),
      const SizedBox(height: NvSpace.s3),
      const Text('Bill date', style: NvText.bodyStrong),
      const SizedBox(height: 6),
      NvButton(
          label: date == null
              ? 'Choose the date'
              : _calendarDateWords(date, withYear: true),
          kind: NvButtonKind.secondary,
          fullWidth: true,
          onPressed: _chooseDate),
      const SizedBox(height: NvSpace.s3),
      NvField(
          label: 'Your GSTIN',
          controller: _gstin,
          help:
              "The GSTIN that made the bill. Not the carrier's transporter ID.",
          errorText: _gstinError,
          identifier: true),
      const SizedBox(height: NvSpace.s3),
      NvField(label: 'Invoice number', controller: _invoice, identifier: true),
      if (checked) ...[
        const SizedBox(height: NvSpace.s2),
        const Text("If you change these, NaviG8r's portal check is removed.",
            style: NvText.caption),
      ],
      EwayBillErrorText(_error),
      const SizedBox(height: NvSpace.s4),
      NvButton(
          label: 'Save e-way bill',
          loadingLabel: 'Saving',
          loading: _busy,
          fullWidth: true,
          onPressed: _saveBill),
      const SizedBox(height: NvSpace.s2),
      NvButton(
          label: 'Cancel',
          kind: NvButtonKind.quiet,
          fullWidth: true,
          onPressed: _cancel),
    ];
  }

  List<Widget> _statementForm() {
    return [
      Text('Why is no e-way bill needed?',
          style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
      const SizedBox(height: NvSpace.s2),
      NvChoiceRows<String>(
          options: [
            for (final entry in notNeededReasonChoices.entries)
              NvChoice(entry.key, entry.value),
          ],
          selected: _reason,
          onChanged: (value) => setState(() => _reason = value)),
      if (_reason == 'OTHER') ...[
        const SizedBox(height: NvSpace.s3),
        NvField(label: 'Write the reason', controller: _note),
      ],
      EwayBillErrorText(_error),
      const SizedBox(height: NvSpace.s4),
      NvButton(
          label: 'Save',
          loadingLabel: 'Saving',
          loading: _busy,
          fullWidth: true,
          onPressed: _saveStatement),
      const SizedBox(height: NvSpace.s2),
      NvButton(
          label: 'Cancel',
          kind: NvButtonKind.quiet,
          fullWidth: true,
          onPressed: _cancel),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bill = _bill;
    final body = switch (_mode) {
      _Mode.viewing => _viewing(),
      _Mode.addingBill => _billForm(),
      _Mode.statingNotNeeded => _statementForm(),
      _Mode.addingTruck => [
          EwayBillTruckForm(
              path: '/shipments/${widget.shipment['id']}/eway-bill/truck',
              current: bill,
              assignedTruckNumber: _tripTruck,
              lead:
                  'Add the truck on the portal first. Then copy the truck number and valid-until time here.',
              clearsCheck: bill?['check'] is Map,
              onSaved: _showSaved,
              onCancel: _cancel),
          const EwayBillPortalButton(
              label: 'Open the e-way bill portal', kind: NvButtonKind.quiet),
        ],
    };
    final aboutNotNeeded = _mode == _Mode.statingNotNeeded ||
        (_mode == _Mode.viewing && bill?['kind'] == 'NOT_NEEDED');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...body,
        if (!aboutNotNeeded && !_summaryOnly) ...[
          const SizedBox(height: NvSpace.s3),
          const Text(ewayBillFootnote, style: NvText.caption),
        ],
      ],
    );
  }
}

/// "1 Oct" for a calendar date written as 2026-10-01, or with the year in a form.
String _calendarDateWords(String date, {bool withYear = false}) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  // Noon UTC is the same calendar day in India.
  return formatDate(DateTime.utc(parsed.year, parsed.month, parsed.day, 12),
      withYear: withYear);
}
