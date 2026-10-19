import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_dates.dart';
import 'eway_bill_error_text.dart';
import 'eway_bill_portal_link.dart';
import 'pilot_api.dart';
import 'ui/format.dart';

/// The moment a date and time typed as India time stands for, whatever zone the phone is set to.
int validUntilUtcMsFromIndiaTime(DateTime date, TimeOfDay time) =>
    DateTime.utc(date.year, date.month, date.day, time.hour, time.minute)
        .subtract(indiaTimeOffset)
        .millisecondsSinceEpoch;

/// Part B of an e-way bill: the truck number and valid-until time, copied from the bill after the
/// truck was added to it. Used by the shipper's card; the carrier only reads the bill.
class EwayBillTruckForm extends StatefulWidget {
  const EwayBillTruckForm(
      {required this.path,
      required this.onSaved,
      required this.onCancel,
      required this.clearsCheck,
      this.current,
      this.assignedTruckNumber,
      this.lead,
      super.key});
  final String path;
  final void Function(Map<String, dynamic> shipment) onSaved;
  final VoidCallback onCancel;
  final bool clearsCheck;

  /// The bill as it is now, to show its truck back when changing it.
  final Map<String, dynamic>? current;

  /// The truck the carrier named for the trip. It fills the field ahead of the bill's own truck, because
  /// after a breakdown it is the truck the bill should now carry.
  final String? assignedTruckNumber;

  /// The first line, saying where the truck was added. Without one it names the portal.
  final String? lead;

  @override
  State<EwayBillTruckForm> createState() => _EwayBillTruckFormState();
}

class _EwayBillTruckFormState extends State<EwayBillTruckForm> {
  final _truckNumber = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    final truck = widget.assignedTruckNumber ?? current?['truckNumber'];
    if (truck is String) _truckNumber.text = truck;
    final validUntil = current?['validUntilUtcMs'];
    if (validUntil is num) {
      final india =
          DateTime.fromMillisecondsSinceEpoch(validUntil.toInt(), isUtc: true)
              .add(indiaTimeOffset);
      _date = DateTime(india.year, india.month, india.day);
      _time = TimeOfDay(hour: india.hour, minute: india.minute);
    }
  }

  @override
  void dispose() {
    _truckNumber.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final india = DateTime.now().toUtc().add(indiaTimeOffset);
    final today = DateTime(india.year, india.month, india.day);
    // The server refuses more than 30 days from now, so the last day is 29 ahead: even 23:59 on it stays
    // inside. Built from the day number, because adding a Duration shifts by an hour across a clock change.
    final last = DateTime(today.year, today.month, today.day + 29);
    final chosen = _date;
    // A saved date outside the allowed range would make the picker fail, so it opens on today.
    final initial =
        chosen != null && !chosen.isBefore(today) && !chosen.isAfter(last)
            ? chosen
            : today;
    final picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: today,
        lastDate: last);
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _chooseTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _time ?? const TimeOfDay(hour: 23, minute: 59));
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final date = _date;
    final time = _time;
    if (_truckNumber.text.trim().isEmpty || date == null || time == null) {
      setState(() =>
          _error = 'Fill in the truck number, the date and the time to save.');
      return;
    }
    final scope = AuthorizationSession.scopeKey;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(widget.path, data: {
        'truckNumber': _truckNumber.text,
        'validUntilUtcMs': validUntilUtcMsFromIndiaTime(date, time),
      });
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final shipment = response.data?['shipment'];
      if (shipment is Map<String, dynamic>) widget.onSaved(shipment);
    } catch (e) {
      if (mounted) setState(() => _error = ewayBillErrorSentence(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateWords() {
    final date = _date;
    if (date == null) return 'Valid until, date in India: choose the date';
    final time = _time;
    final dateWords = formatDate(DateTime.utc(date.year, date.month, date.day),
        withYear: true);
    return time == null
        ? 'Valid until, date in India: $dateWords'
        : 'Valid until, date in India: $dateWords, ${ewayBillClockTime(time.hour, time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final time = _time;
    final filledFromTrip = widget.assignedTruckNumber?.isNotEmpty == true;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.lead ??
          'Add the truck to the bill on the $ewayBillPortalName first, then copy the truck number and the valid-until time from it.'),
      const SizedBox(height: 12),
      TextField(
          controller: _truckNumber,
          enabled: !_busy,
          maxLength: 14,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
              labelText: 'Truck number',
              helperText: filledFromTrip
                  ? 'Filled in from the truck on this trip. Change it if the e-way bill shows a different truck.'
                  : null,
              // Room for large text: the warning to change it is the part that matters.
              helperMaxLines: 10,
              counterText: '',
              border: const OutlineInputBorder())),
      const SizedBox(height: 12),
      OutlinedButton(
          onPressed: _busy ? null : _chooseDate, child: Text(_dateWords())),
      const SizedBox(height: 8),
      OutlinedButton(
          onPressed: _busy ? null : _chooseTime,
          child: Text(time == null
              ? 'Time in India: choose the time'
              : 'Time in India: ${ewayBillClockTime(time.hour, time.minute)}')),
      const SizedBox(height: 8),
      if (widget.clearsCheck)
        const Text('Changing these details clears the check.'),
      EwayBillErrorText(_error),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save truck')),
        TextButton(
            onPressed: _busy ? null : widget.onCancel,
            child: const Text('Cancel')),
      ]),
    ]);
  }
}
