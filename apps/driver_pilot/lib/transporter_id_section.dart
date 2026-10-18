import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'driver_session.dart';
import 'pilot_api.dart';
import 'refusal_sentence.dart';
import 'ui/nv_button.dart';
import 'ui/nv_field.dart';
import 'ui/nv_section_card.dart';
import 'ui/tokens.dart';

/// Under the transporter ID field at sign-up and on Profile (spec/copy.md, Profile).
const transporterIdHelperText =
    "Your GSTIN, or a TRANSIN if you have no GST registration. Shippers copy it into their e-way bills. It is not the shipper's GSTIN.";

/// The carrier's transporter ID on Profile. The owner and owner-driver add, change or clear it; a dispatcher
/// reads it; a driver does not see it, and the server does not send it to one. Shippers put it on the e-way
/// bill, which assigns the bill to this carrier.
class TransporterIdSection extends StatefulWidget {
  const TransporterIdSection({super.key});

  @override
  State<TransporterIdSection> createState() => _TransporterIdSectionState();
}

class _TransporterIdSectionState extends State<TransporterIdSection> {
  // Read once, when Profile opens the section: a refresh started elsewhere on Profile (a pull-down, or saving
  // the truck) empties the session's copy while it runs, and must not swap the field out mid-edit.
  final _loadedWhenOpened = DriverSession.transporterIdLoaded;
  String? _savedTransporterId = DriverSession.transporterId;
  late final _transporterId =
      TextEditingController(text: _savedTransporterId ?? '');
  final _transporterIdFocus = FocusNode();
  // A saved ID shows as text with a Change button, so it is not edited by accident; with none saved, the field is open.
  late bool _editing = _savedTransporterId == null;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _transporterId.dispose();
    _transporterIdFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final typed = _transporterId.text.trim();
    final scope = AuthorizationSession.scopeKey;
    // A message on screen is out of date once a new save starts, whatever its answer turns out to be.
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // An empty field clears it.
      final response = await api.patch<Map<String, dynamic>>(
          '/v1/pilot/carrier/transporter-id',
          data: {'transporterId': typed.isEmpty ? null : typed});
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final org = response.data?['org'];
      final saved = org is Map ? org['transporterId'] : null;
      _savedTransporterId = saved is String && saved.isNotEmpty ? saved : null;
      DriverSession.transporterId = _savedTransporterId;
      DriverSession.transporterIdLoaded = true;
      _transporterId.text = _savedTransporterId ?? '';
      setState(() => _editing = _savedTransporterId == null);
      // The reply does not say whether one was there before, so an empty save states what is true now.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(_savedTransporterId != null
              ? 'Transporter ID saved.'
              : 'No transporter ID is saved now.')));
    } catch (e) {
      if (mounted) setState(() => _error = refusalSentence(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    if (_saving) return;
    setState(() {
      _transporterId.text = _savedTransporterId ?? '';
      _error = null;
      _editing = false;
    });
  }

  List<Widget> _content() {
    final saved = _savedTransporterId;
    const help = Text(transporterIdHelperText, style: NvText.caption);
    // No field until the saved ID has loaded: an empty one would let Save clear it.
    if (!_loadedWhenOpened) {
      return const [
        Text(
            'Could not load the transporter ID. Leave Profile and open it again to retry.',
            style: NvText.body)
      ];
    }
    if (!AuthorizationSession.can('transporter_id.write')) {
      return [
        saved == null
            ? const Text('Not added yet. The carrier owner can add it.',
                style: NvText.body)
            : SelectableText(saved, style: NvText.id),
        const SizedBox(height: NvSpace.s2),
        help,
      ];
    }
    if (!_editing) {
      return [
        SelectableText(saved!, style: NvText.id),
        const SizedBox(height: NvSpace.s2),
        help,
        const SizedBox(height: NvSpace.s3),
        Align(
          alignment: Alignment.centerLeft,
          child: NvButton(
              label: 'Change transporter ID',
              kind: NvButtonKind.secondary,
              onPressed: () {
                setState(() => _editing = true);
                // Explicit, not autofocus: autofocus is skipped while another Profile field has the cursor.
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _transporterIdFocus.requestFocus());
              }),
        ),
      ];
    }
    return [
      NvField(
        label: 'Transporter ID',
        controller: _transporterId,
        focusNode: _transporterIdFocus,
        identifier: true,
        textCapitalization: TextCapitalization.characters,
        help: transporterIdHelperText,
        errorText: _error,
        readOnly: _saving,
      ),
      const SizedBox(height: NvSpace.s3),
      Wrap(spacing: NvSpace.s2, runSpacing: NvSpace.s2, children: [
        NvButton(
            label: 'Save transporter ID',
            loading: _saving,
            loadingLabel: 'Saving',
            onPressed: _save),
        if (saved != null)
          NvButton(
              label: 'Cancel', kind: NvButtonKind.quiet, onPressed: _cancel),
      ]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Holding trip.assign is what makes a login the carrier office: owner, owner-driver or dispatcher.
    if (!AuthorizationSession.can('trip.assign')) {
      return const SizedBox.shrink();
    }
    return NvSectionCard(title: 'Transporter ID', children: [
      const SizedBox(height: NvSpace.s3),
      ..._content(),
    ]);
  }
}
