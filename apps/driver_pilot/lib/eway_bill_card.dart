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
    'NaviG8r never makes or changes an e-way bill. You make it in your billing software or on the e-way bill site.';

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
      super.key});
  final Map<String, dynamic> shipment;

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

  Future<void> _remove() =>
      _submit('/shipments/${widget.shipment['id']}/eway-bill/remove', null);

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
    });
    final bill = _bill;
    if (bill != null && bill['kind'] == 'BILL') {
      final truck = bill['truckNumber'];
      SemanticsService.announce(
          truck is String && truck.isNotEmpty
              ? 'E-way bill saved. Nothing more for you to do until delivery.'
              : 'E-way bill saved. The truck is not on it yet.',
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
                label: 'I have made it. Enter the details',
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: _openBillForm),
            const SizedBox(height: NvSpace.s2),
            NvButton(
                label: 'No e-way bill needed',
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: _openStatementForm),
          ]
        : const <Widget>[];
    if (status == 'PENDING_CARRIER_ACCEPT') {
      return [
        const Text(
            'You can make the bill once the carrier accepts and names the truck. We will send you an update.',
            style: NvText.body),
        const SizedBox(height: NvSpace.s3),
        EwayBillTransportDetails(
            carrierName: _carrierName, carrierAccepted: false),
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
          'Make the bill in your billing software or on the e-way bill site. Copy these in:',
          style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
      const SizedBox(height: NvSpace.s3),
      EwayBillTransportDetails(
          carrierName: _carrierName,
          carrierAccepted: true,
          transporterId: _transporterId,
          truckNumber: _tripTruck),
      // Above the loading-day line so a 900 dp tall desktop still shows it without scrolling.
      if (canEdit && widget.portalButtonInPanel) ...[
        const SizedBox(height: NvSpace.s3),
        const EwayBillPortalButton(
            label: 'Open the e-way bill portal', kind: NvButtonKind.primary),
      ],
      const SizedBox(height: NvSpace.s3),
      const Text(
          'Make it on loading day, before the goods move: the bill is valid from when the truck is entered.',
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
    final canAddTruck = _canAddTruck;
    return [
      Text.rich(TextSpan(style: NvText.body, children: [
        const TextSpan(text: 'Bill '),
        TextSpan(
            text: formatBillNumber(number is String ? number : ''),
            style: NvText.id),
        const TextSpan(text: ' saved. The truck is not on it yet.'),
      ])),
      if (canAddTruck) ...[
        const SizedBox(height: NvSpace.s3),
        Text(
            'Add the truck in your billing software or on the e-way bill site before the goods move, then enter it here.',
            style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
      ],
      if (widget.shipment['status'] == 'BOOKED') ...[
        const SizedBox(height: NvSpace.s3),
        EwayBillTransportDetails(
            carrierName: _carrierName,
            carrierAccepted: true,
            transporterId: _transporterId,
            truckNumber: _tripTruck,
            truckPortalField: 'Portal: Update Part B, Vehicle No.'),
      ],
      const SizedBox(height: NvSpace.s3),
      const Text(
          "The bill's validity starts when the truck is added: one day per 200 km, ending at midnight India time.",
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
        Text('NaviG8r staff found a difference',
            style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
        const SizedBox(height: NvSpace.s2),
        Text(ewayBillCheckLine(bill, forShipper: true), style: NvText.body),
        const SizedBox(height: NvSpace.s2),
        const Text(
            'If the portal is right, fix it here. If the bill itself is wrong, change it in your billing software or on the e-way bill site first.',
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
      if (!checked && !ewayBillIsClosed(widget.shipment)) ...[
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
      for (final line in ewayBillTruckLines(bill).skip(2))
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

  List<Widget> _billActions(Map<String, dynamic> bill) {
    if (!_canEdit) return const [];
    final truck = bill['truckNumber'];
    final hasTruck = truck is String && truck.isNotEmpty;
    return [
      const SizedBox(height: NvSpace.s2),
      Wrap(spacing: NvSpace.s2, children: [
        NvButton(
            label: 'Edit', kind: NvButtonKind.quiet, onPressed: _openBillForm),
        if (hasTruck && _canAddTruck)
          NvButton(
              label: 'Change truck',
              kind: NvButtonKind.quiet,
              onPressed: _openTruckForm),
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
      const Text('E-WAY BILL · PART 2 OF 2', style: NvText.label),
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
        const Text('Changing these details clears the check.',
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
      const SizedBox(height: NvSpace.s1),
      const Text('NaviG8r staff then check it on the portal.',
          style: NvText.caption),
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
                  'Add the truck to the bill in your billing software or on the e-way bill site first, then copy the truck number and the valid-until time from it.',
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
        if (!aboutNotNeeded) ...[
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
