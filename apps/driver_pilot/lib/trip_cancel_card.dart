import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'pilot_api.dart';
import 'ui/nv_button.dart';
import 'ui/nv_choice.dart';
import 'ui/nv_field.dart';
import 'ui/nv_message.dart';
import 'ui/nv_sheet.dart';
import 'ui/tokens.dart';

/// Taking back a trip on the office's trip screen (owner decision, 19 Oct 2026). A trip with no booking is
/// cancelled here, after a question in the page. With bookings the office asks NaviG8r instead, which reviews the
/// request, and can withdraw it. Only whoever may assign trips sees the buttons.
class TripCancelCard extends StatefulWidget {
  const TripCancelCard(
      {required this.trip,
      required this.hasBookings,
      required this.onChanged,
      this.onReload,
      super.key});
  final Map<String, dynamic> trip;

  /// A booking waiting for acceptance, paid or not, or an accepted one.
  final bool hasBookings;

  /// The trip as the server saved it.
  final ValueChanged<Map<String, dynamic>> onChanged;

  /// Loads the trip and its bookings again, when the server says this screen's bookings are out of date.
  final VoidCallback? onReload;

  @override
  State<TripCancelCard> createState() => _TripCancelCardState();
}

enum _Asking { nothing, cancel, withdraw }

const cancelRequestedSentence =
    'You asked NaviG8r to cancel this trip. Shippers cannot book it now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled.';

/// The server's words for refusing to accept a booking on such a trip, shown on Accept before it is tapped.
const cancelRequestedAcceptSentence =
    'You asked NaviG8r to cancel this trip, so it cannot take this booking. Withdraw the request first.';
const tripCancelledSentence =
    'Trip cancelled. Shippers can no longer see or book it.';
const _noBookingsLeftSentence =
    'This trip has no bookings now, so you can cancel it yourself.';

/// What the Ask NaviG8r to cancel sheet ended with: the saved trip, or the server's word that no booking is left.
typedef _AskOutcome = ({Map<String, dynamic>? trip, bool noBookingsLeft});

class _TripCancelCardState extends State<TripCancelCard> {
  _Asking _asking = _Asking.nothing;
  bool _working = false;
  String? _error;
  bool _justWithdrawn = false;
  // The server's answer when it contradicts the bookings this screen loaded, until the screen loads different ones.
  bool? _bookingsPerServer;

  String? get _status => widget.trip['status']?.toString();
  bool get _hasBookings => _bookingsPerServer ?? widget.hasBookings;

  @override
  void didUpdateWidget(TripCancelCard old) {
    super.didUpdateWidget(old);
    if (old.hasBookings != widget.hasBookings) _bookingsPerServer = null;
  }

  Future<void> _send(String path) async {
    final scope = AuthorizationSession.scopeKey;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(
          '/v1/pilot/anchor-trips/${widget.trip['id']}/$path');
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final trip = response.data?['trip'];
      setState(() {
        _working = false;
        _asking = _Asking.nothing;
        _justWithdrawn = path == 'cancel-request/withdraw';
      });
      if (trip is Map<String, dynamic>) widget.onChanged(trip);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _asking = _Asking.nothing;
        _error = _refusalSentence(e);
        if (_refusedFor(e, 'trip_has_bookings')) _bookingsPerServer = true;
      });
    }
  }

  static bool _refusedFor(Object e, String code) {
    final body = e is DioException ? e.response?.data : null;
    return body is Map && body['error'] == code;
  }

  static String _refusalSentence(Object e) {
    if (_refusedFor(e, 'trip_has_bookings')) {
      return 'This trip has bookings, so it cannot be cancelled here.';
    }
    final status = e is DioException ? e.response?.statusCode : null;
    if (status == 403 || status == 404) {
      return 'This trip changed. Pull down to reload this screen.';
    }
    return ewayBillErrorSentence(e);
  }

  Future<void> _openAskSheet() async {
    setState(() {
      _error = null;
      _justWithdrawn = false;
    });
    final outcome = await showNvSheet<_AskOutcome>(
        context: context, builder: (_) => _AskSheet(tripId: widget.trip['id']));
    if (outcome == null || !mounted) return;
    final trip = outcome.trip;
    if (trip != null) widget.onChanged(trip);
    if (outcome.noBookingsLeft) {
      setState(() {
        _bookingsPerServer = false;
        _error = _noBookingsLeftSentence;
      });
      widget.onReload?.call();
    }
  }

  /// A question in the page, never a dialog: the safe answer comes first and has the focus.
  Widget _question(
      {required String title,
      required String text,
      required String keepLabel,
      required String goLabel,
      required NvButtonKind goKind,
      required String goingLabel,
      required VoidCallback onGo}) {
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
          color: NvColors.sunken,
          borderRadius: BorderRadius.circular(NvRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(title, style: NvText.bodyStrong)),
        const SizedBox(height: NvSpace.s2),
        Text(text, style: NvText.body),
        const SizedBox(height: NvSpace.s4),
        // Not an NvButton, for NvSheet's reason: it is held while the answer is on its way, with no reason line.
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(NvSpace.targetMin)),
          autofocus: true,
          onPressed:
              _working ? null : () => setState(() => _asking = _Asking.nothing),
          child: Text(keepLabel, textAlign: TextAlign.center),
        ),
        const SizedBox(height: NvSpace.s3),
        NvButton(
            label: goLabel,
            kind: goKind,
            fullWidth: true,
            loading: _working,
            loadingLabel: goingLabel,
            onPressed: onGo),
      ]),
    );
  }

  List<Widget> _forOpenTrip() {
    if (!_hasBookings) {
      if (_asking == _Asking.cancel) {
        return [
          _question(
              title: 'Cancel this trip?',
              text:
                  'Shippers will no longer see or book it. You can publish a new trip any time. This cannot be undone.',
              keepLabel: 'Keep trip',
              goLabel: 'Cancel trip',
              goKind: NvButtonKind.destructive,
              goingLabel: 'Cancelling',
              onGo: () => _send('cancel')),
        ];
      }
      return [
        NvButton(
            label: 'Cancel this trip',
            kind: NvButtonKind.destructive,
            fullWidth: true,
            onPressed: () => setState(() {
                  _asking = _Asking.cancel;
                  _error = null;
                  _justWithdrawn = false;
                })),
      ];
    }
    return [
      NvButton(
          label: 'Ask NaviG8r to cancel',
          kind: NvButtonKind.secondary,
          fullWidth: true,
          onPressed: _openAskSheet),
    ];
  }

  List<Widget> _forRequestedTrip(bool mayAct) {
    return [
      const NvMessage(cancelRequestedSentence, tone: NvMessageTone.attention),
      if (mayAct) ...[
        const SizedBox(height: NvSpace.s3),
        if (_asking == _Asking.withdraw)
          _question(
              title: 'Withdraw your request?',
              text: 'Shippers can book this trip again while it has room.',
              keepLabel: 'Keep request',
              goLabel: 'Withdraw request',
              goKind: NvButtonKind.primary,
              goingLabel: 'Withdrawing',
              onGo: () => _send('cancel-request/withdraw'))
        else
          NvButton(
              label: 'Withdraw request',
              kind: NvButtonKind.secondary,
              fullWidth: true,
              onPressed: () => setState(() {
                    _asking = _Asking.withdraw;
                    _error = null;
                  })),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mayAct = AuthorizationSession.can('trip.assign');
    final status = _status;
    final List<Widget> children;
    if (status == 'CANCELLED') {
      children = [
        const NvMessage(tripCancelledSentence, tone: NvMessageTone.good)
      ];
    } else if (status == 'CANCEL_REQUESTED') {
      children = _forRequestedTrip(mayAct);
    } else if ((status == 'OPEN' || status == 'FULL') && mayAct) {
      children = [
        if (_justWithdrawn) ...[
          const NvMessage(
              'Request withdrawn. Shippers can book this trip again while it has room.',
              tone: NvMessageTone.good),
          const SizedBox(height: NvSpace.s3),
        ],
        ..._forOpenTrip(),
      ];
    } else {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...children,
      if (_error != null) ...[
        const SizedBox(height: NvSpace.s3),
        NvMessage(_error!, tone: NvMessageTone.problem),
      ],
    ]);
  }
}

const _reasons = [
  NvChoice('TRUCK_UNAVAILABLE', 'Truck not available'),
  NvChoice('DRIVER_UNAVAILABLE', 'Driver not available'),
  NvChoice('ROUTE_CHANGED', 'Route changed'),
  NvChoice('OTHER', 'Other reason'),
];
const _maxNoteLength = 500;

/// "Ask NaviG8r to cancel": a reason from the four, always chosen by the person, and a note only if they want one.
class _AskSheet extends StatefulWidget {
  const _AskSheet({required this.tripId});
  final Object? tripId;

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    final note = _note.text.trim();
    if (note.length > _maxNoteLength) {
      setState(() =>
          _error = 'Keep the note to $_maxNoteLength characters or fewer.');
      return;
    }
    final scope = AuthorizationSession.scopeKey;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(
          '/v1/pilot/anchor-trips/${widget.tripId}/cancel-request',
          data: {'reasonCode': reason, if (note.isNotEmpty) 'note': note});
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final trip = response.data?['trip'];
      closeNvSheetAfterSuccess<_AskOutcome>(context,
          announcement: cancelRequestedSentence,
          result: (
            trip: trip is Map<String, dynamic> ? trip : null,
            noBookingsLeft: false
          ));
    } catch (e) {
      if (!mounted) return;
      // Every booking left since the screen loaded: the card offers Cancel this trip instead.
      if (_TripCancelCardState._refusedFor(e, 'trip_has_no_bookings')) {
        closeNvSheetAfterSuccess<_AskOutcome>(context,
            announcement: _noBookingsLeftSentence,
            result: (trip: null, noBookingsLeft: true));
        return;
      }
      setState(() {
        _sending = false;
        _error = ewayBillErrorSentence(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NvSheet(
      title: 'Why do you want to cancel this trip?',
      message:
          'Shippers cannot book the trip now. NaviG8r reviews your request. Shippers already booked are told if their shipment is cancelled.',
      errorText: _error,
      choices: [
        NvChoiceRows<String>(
          options: _reasons,
          selected: _reason,
          onChanged: (value) => setState(() => _reason = value),
        ),
        const SizedBox(height: NvSpace.s2),
        NvField(
            label: 'Note',
            optional: true,
            controller: _note,
            textCapitalization: TextCapitalization.sentences),
      ],
      primaryLabel: 'Send request',
      onPrimary: _reason == null ? null : _sendRequest,
      disabledReason: _reason == null ? 'Choose a reason first.' : null,
      loading: _sending,
      loadingLabel: 'Sending',
      cancelLabel: 'Keep trip',
    );
  }
}
