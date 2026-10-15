import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'driver_theme.dart';
import 'eway_bill_closed.dart';
import 'eway_bill_dates.dart';
import 'eway_bill_error_text.dart';
import 'eway_bill_portal_link.dart';
import 'eway_bill_truck_form.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';

enum _Mode { viewing, addingBill, statingNotNeeded, addingTruck }

/// The shipper's e-way bill for one shipment. The bill is made on the government portal; this card
/// only holds the details the shipper types in and shows what ops saw when it looked the bill up.
class EwayBillCard extends StatefulWidget {
  const EwayBillCard({required this.shipment, super.key});
  final Map<String, dynamic> shipment;

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
  num _savedAtUtcMs = 0;

  static Map<String, dynamic>? _billFrom(Map<String, dynamic> shipment) {
    final raw = shipment['ewayBill'];
    return raw is Map<String, dynamic> ? raw : null;
  }

  bool get _canEdit {
    final shipment = widget.shipment;
    return AuthorizationSession.hasRole('SHIPPER') &&
        AuthorizationSession.can('eway_bill.write') &&
        shipment['customerOrgId'] == AuthorizationSession.organizationId &&
        !ewayBillIsClosed(shipment);
  }

  @override
  void didUpdateWidget(EwayBillCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different shipment in the same spot starts clean; nothing typed for the old one may carry over.
    if (widget.shipment['id'] != oldWidget.shipment['id']) {
      _mode = _Mode.viewing;
      _bill = _billFrom(widget.shipment);
      _savedAtUtcMs = 0;
      _error = null;
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
    super.dispose();
  }

  void _openBillForm() {
    final bill = _bill;
    final editing = bill != null && bill['kind'] == 'BILL';
    setState(() {
      _number.text = editing ? '${bill['billNumber'] ?? ''}' : '';
      _gstin.text = editing ? '${bill['makerGstin'] ?? ''}' : '';
      _invoice.text = editing ? '${bill['invoiceNumber'] ?? ''}' : '';
      _billDate = editing ? bill['billDate'] as String? : null;
      _error = null;
      _mode = _Mode.addingBill;
    });
  }

  void _openStatementForm() {
    final bill = _bill;
    final editing = bill != null && bill['kind'] == 'NOT_NEEDED';
    setState(() {
      _reason = editing ? bill['notNeededReason'] as String? : null;
      _note.text = editing ? '${bill['notNeededNote'] ?? ''}' : '';
      _error = null;
      _mode = _Mode.statingNotNeeded;
    });
  }

  void _cancel() => setState(() {
        _error = null;
        _mode = _Mode.viewing;
      });

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
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

  Future<void> _saveBill() async {
    final date = _billDate;
    if (_number.text.trim().isEmpty ||
        date == null ||
        _gstin.text.trim().isEmpty ||
        _invoice.text.trim().isEmpty) {
      setState(() => _error = 'Fill in all four details to save.');
      return;
    }
    await _submit('/shipments/${widget.shipment['id']}/eway-bill', {
      'kind': 'BILL',
      'billNumber': _number.text,
      'billDate': date,
      'makerGstin': _gstin.text,
      'invoiceNumber': _invoice.text,
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

  void _showSaved(Map<String, dynamic>? shipment) => setState(() {
        _bill = shipment == null ? null : _billFrom(shipment);
        final savedTime = shipment?['updatedAtUtcMs'];
        if (savedTime is num) _savedAtUtcMs = savedTime;
        _mode = _Mode.viewing;
      });

  void _openTruckForm() => setState(() {
        _error = null;
        _mode = _Mode.addingTruck;
      });

  List<Widget> _viewing() {
    final bill = _bill;
    final canEdit = _canEdit;
    if (bill == null) {
      return [
        const Text('No e-way bill added yet.'),
        if (canEdit) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
                onPressed: _openBillForm, child: const Text('Add e-way bill')),
            OutlinedButton(
                onPressed: _openStatementForm,
                child: const Text('No e-way bill needed')),
          ]),
          const EwayBillPortalButton(),
        ],
      ];
    }
    if (bill['kind'] == 'NOT_NEEDED') {
      return [
        Text(
            'You said no e-way bill is needed: ${notNeededReasonWords(bill)}.'),
        if (canEdit) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
                onPressed: _busy ? null : _openStatementForm,
                child: const Text('Change')),
            OutlinedButton(
                onPressed: _busy ? null : _remove,
                child: const Text('Remove e-way bill')),
          ]),
        ],
        EwayBillErrorText(_error),
      ];
    }
    final number = bill['billNumber'];
    final date = bill['billDate'];
    final truckLines = ewayBillTruckLines(bill);
    final canAddTruck =
        canEdit && AuthorizationSession.can('eway_bill.add_truck');
    final mismatch = ewayBillTruckMismatchSentence(widget.shipment, bill,
        reader: TruckMismatchReader.shipper);
    return [
      if (number is String)
        SelectableText(groupedBillNumber(number),
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: DriverTheme.navy)),
      if (date is String)
        Text('Bill date: ${ewayBillDateFromCalendarDate(date)}'),
      Text('GSTIN of whoever made the bill: ${bill['makerGstin'] ?? ''}'),
      Text('Invoice number: ${bill['invoiceNumber'] ?? ''}'),
      const SizedBox(height: 8),
      if (truckLines.isEmpty)
        const Text(
            'Truck not added yet. You or your carrier can add it after the truck is on the bill on the portal.')
      else
        for (final line in truckLines) Text(line),
      if (mismatch != null) Text(mismatch),
      const SizedBox(height: 8),
      Text(ewayBillCheckLine(bill, forShipper: true)),
      if (canEdit) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
              onPressed: _busy ? null : _openBillForm,
              child: const Text('Edit')),
          if (canAddTruck)
            OutlinedButton(
                onPressed: _busy ? null : _openTruckForm,
                child: Text(truckLines.isEmpty ? 'Add truck' : 'Change truck')),
          OutlinedButton(
              onPressed: _busy ? null : _remove,
              child: const Text('Remove e-way bill')),
        ]),
        const EwayBillPortalButton(),
      ],
      EwayBillErrorText(_error),
    ];
  }

  Widget _field(TextEditingController controller, String label,
          {String? helper,
          int? maxLength,
          TextInputType? keyboardType,
          TextCapitalization capitalization = TextCapitalization.none}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
              controller: controller,
              enabled: !_busy,
              maxLength: maxLength,
              keyboardType: keyboardType,
              textCapitalization: capitalization,
              decoration: InputDecoration(
                  labelText: label,
                  helperText: helper,
                  helperMaxLines: 2,
                  counterText: '',
                  border: const OutlineInputBorder())));

  List<Widget> _billForm() {
    final checked = _bill?['check'] is Map;
    return [
      Text(
          'Copy these four details from the $ewayBillPortalName. All four are needed to save. naviG8r does not make or change e-way bills.'),
      const EwayBillPortalButton(),
      const SizedBox(height: 8),
      _field(_number, 'E-way bill number (12 digits)',
          maxLength: 14, keyboardType: TextInputType.number),
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton(
              onPressed: _busy ? null : _chooseDate,
              child: Text(_billDate == null
                  ? 'Bill date: choose the date'
                  : 'Bill date: ${ewayBillDateFromCalendarDate(_billDate!)}'))),
      _field(_gstin, 'GSTIN of whoever made the bill',
          helper: 'Used only by naviG8r ops to find the bill on the portal.',
          maxLength: 15,
          capitalization: TextCapitalization.characters),
      _field(_invoice, 'Invoice number',
          helper: 'Used only by naviG8r ops to find the bill on the portal.',
          maxLength: 32),
      if (checked) const Text('Changing these details clears the check.'),
      EwayBillErrorText(_error),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
            onPressed: _busy ? null : _saveBill,
            child: Text(_busy ? 'Saving...' : 'Save e-way bill')),
        TextButton(
            onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
      ]),
    ];
  }

  List<Widget> _statementForm() {
    return [
      const Text('Why is no e-way bill needed?'),
      _ReasonChoices(
          reasons: notNeededReasonChoices,
          selected: _reason,
          enabled: !_busy,
          onChanged: (value) => setState(() => _reason = value)),
      if (_reason == 'OTHER') _field(_note, 'Write the reason', maxLength: 140),
      EwayBillErrorText(_error),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
            onPressed: _busy ? null : _saveStatement,
            child: Text(_busy ? 'Saving...' : 'Save')),
        TextButton(
            onPressed: _busy ? null : _cancel, child: const Text('Cancel')),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_mode) {
      _Mode.viewing => _viewing(),
      _Mode.addingBill => _billForm(),
      _Mode.statingNotNeeded => _statementForm(),
      _Mode.addingTruck => [
          EwayBillTruckForm(
              path: '/shipments/${widget.shipment['id']}/eway-bill/truck',
              current: _bill,
              clearsCheck: _bill?['check'] is Map,
              onSaved: _showSaved,
              onCancel: _cancel),
          const EwayBillPortalButton(),
        ],
    };
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('E-way bill',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...body,
                ])));
  }
}

/// One tappable row per reason, none chosen until the shipper chooses.
class _ReasonChoices extends StatelessWidget {
  const _ReasonChoices(
      {required this.reasons,
      required this.selected,
      required this.enabled,
      required this.onChanged});
  final Map<String, String> reasons;
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final entry in reasons.entries)
          RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: Text(entry.value),
              value: entry.key,
              groupValue: selected,
              onChanged: enabled ? onChanged : null),
      ]);
}
