import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'ui/nv_button.dart';
import 'ui/nv_copy_row.dart';
import 'ui/tokens.dart';

/// The transport details the shipper copies into the e-way bill, in their billing software or on
/// the e-way bill site: one copy row each, and Copy all for the ones known so far.
class EwayBillTransportDetails extends StatefulWidget {
  const EwayBillTransportDetails(
      {required this.carrierName,
      required this.carrierAccepted,
      this.truckPortalField = 'Portal field: Vehicle No. (Part B)',
      this.transporterId,
      this.truckNumber,
      super.key});

  /// Null when the shipment does not name its carrier.
  final String? carrierName;

  /// The transporter ID is sent only once the carrier has accepted. The truck is sent as soon as
  /// the trip names one, so before acceptance it shows with a note that it can still change
  /// (owner, 22 Oct 2026).
  final bool carrierAccepted;
  final String? transporterId;
  final String? truckNumber;

  /// Where the truck goes: Part B when making the bill, Update Part B when adding it later.
  final String truckPortalField;

  @override
  State<EwayBillTransportDetails> createState() =>
      _EwayBillTransportDetailsState();
}

class _EwayBillTransportDetailsState extends State<EwayBillTransportDetails> {
  static const _copiedFor = Duration(seconds: 3);
  static const _copyFailedWords =
      'Could not copy. Press and hold each value to copy it.';

  bool _copied = false;
  bool _copyFailed = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  String get _carrierInSentence => widget.carrierName ?? 'the carrier';

  /// Labelled lines for the rows that are known, in the order the bill asks for them.
  String get _allDetails {
    final name = widget.carrierName;
    final transporterId = widget.transporterId;
    final truck = widget.truckNumber;
    return [
      if (name != null) 'Transporter name: $name',
      if (transporterId != null)
        'Transporter ID: ${transporterId.replaceAll(' ', '')}',
      'Mode: Road',
      if (truck != null) 'Vehicle number: ${truck.replaceAll(' ', '')}',
    ].join('\n');
  }

  Future<void> _copyAll() async {
    final direction = Directionality.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: _allDetails));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copied = false;
        _copyFailed = true;
      });
      SemanticsService.announce(_copyFailedWords, direction,
          assertiveness: Assertiveness.assertive);
      return;
    }
    if (!mounted) return;
    setState(() {
      _copied = true;
      _copyFailed = false;
    });
    SemanticsService.announce('Transport details copied.', direction);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(_copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.carrierName;
    final transporterId = widget.transporterId;
    final truck = widget.truckNumber;
    final afterAccepting = 'After $_carrierInSentence accepts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        name == null
            ? const NvCopyRow(
                label: 'Transporter name',
                state: NvCopyRowState.notYet,
                noValueWords: 'Not known yet')
            : NvCopyRow(
                label: 'Transporter name',
                value: name,
                portalField: 'Portal field: Transporter Name'),
        const SizedBox(height: NvSpace.s2),
        if (!widget.carrierAccepted)
          NvCopyRow(
              label: "Carrier's transporter ID",
              state: NvCopyRowState.notYet,
              noValueWords: afterAccepting)
        else if (transporterId == null)
          NvCopyRow(
              label: "Carrier's transporter ID",
              state: NvCopyRowState.empty,
              noValueWords: '${name ?? 'The carrier'} has not added one.',
              guidance:
                  "Leave Transporter ID empty. Then only you, who made the bill, can change the truck.")
        else
          NvCopyRow(
              label: "Carrier's transporter ID",
              value: transporterId,
              portalField: 'Portal field: Transporter ID. Not your GSTIN.'),
        const SizedBox(height: NvSpace.s2),
        if (truck == null && !widget.carrierAccepted)
          NvCopyRow(
              label: 'Truck number',
              state: NvCopyRowState.notYet,
              noValueWords: afterAccepting)
        else if (truck == null)
          const NvCopyRow(
              label: 'Truck number',
              state: NvCopyRowState.notYet,
              noValueWords: 'Not chosen yet',
              guidance: 'Shown once the carrier names the truck.')
        else ...[
          NvCopyRow(
              label: 'Truck number',
              value: truck,
              portalField: widget.truckPortalField),
          if (!widget.carrierAccepted) ...[
            const SizedBox(height: NvSpace.s1),
            Text('${widget.carrierName ?? "The carrier"} can still change it.',
                style: NvText.caption),
          ],
        ],
        if (name != null || transporterId != null || truck != null) ...[
          const SizedBox(height: NvSpace.s2),
          NvButton(
              label: 'Copy all',
              semanticsLabel: 'Copy all transport details',
              successLabel: _copied ? 'Copied' : null,
              kind: NvButtonKind.secondary,
              fullWidth: true,
              onPressed: _copyAll),
        ],
        if (_copyFailed)
          Semantics(
            liveRegion: true,
            child: Text(_copyFailedWords,
                style: NvText.caption.copyWith(
                    color: NvColors.problem, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}
