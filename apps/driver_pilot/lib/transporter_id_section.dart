import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'driver_session.dart';
import 'pilot_api.dart';

/// Under the transporter ID field at sign-up and on Profile.
const transporterIdHelperText =
    'Your GSTIN, or the TRANSIN from the e-way bill portal. Shippers use it on the e-way bill.';

/// The carrier's transporter ID on Profile. The owner and owner-driver add, change or clear it; a dispatcher
/// reads it; a driver does not see it, and the server does not send it to one. Shippers put it on the e-way
/// bill, which assigns the bill to this carrier.
class TransporterIdSection extends StatefulWidget {
  const TransporterIdSection({super.key});

  @override
  State<TransporterIdSection> createState() => _TransporterIdSectionState();
}

class _TransporterIdSectionState extends State<TransporterIdSection> {
  // Read once, when Profile opens the section: a refresh started elsewhere on Profile (Save vehicle) empties the
  // session's copy while it runs, and must not swap the field out mid-edit.
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
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() => setState(() {
        _transporterId.text = _savedTransporterId ?? '';
        _error = null;
        _editing = false;
      });

  @override
  Widget build(BuildContext context) {
    // Holding trip.assign is what makes a login the carrier office: owner, owner-driver or dispatcher.
    if (!AuthorizationSession.can('trip.assign')) return const SizedBox.shrink();
    final saved = _savedTransporterId;
    return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Transporter ID',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(transporterIdHelperText,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              // No field until the saved ID has loaded: an empty one would let Save clear it.
              if (!_loadedWhenOpened)
                const Text(
                    'Could not load the transporter ID. Leave Profile and open it again to retry.')
              else if (AuthorizationSession.can('transporter_id.write') &&
                  !_editing) ...[
                SelectableText(saved!,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: () {
                      setState(() => _editing = true);
                      // Explicit, not autofocus: autofocus is skipped while another Profile field has the cursor.
                      WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _transporterIdFocus.requestFocus());
                    },
                    child: const Text('Change transporter ID')),
              ] else if (AuthorizationSession.can('transporter_id.write')) ...[
                TextField(
                    controller: _transporterId,
                    enabled: !_saving,
                    focusNode: _transporterIdFocus,
                    textCapitalization: TextCapitalization.characters,
                    decoration:
                        const InputDecoration(labelText: 'Transporter ID')),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save transporter ID')),
                if (saved != null)
                  TextButton(
                      onPressed: _saving ? null : _cancel,
                      child: const Text('Cancel')),
              ] else
                Text(saved ?? 'Not added yet. The carrier owner can add it.'),
            ]));
  }
}
