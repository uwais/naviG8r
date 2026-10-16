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
  late final _transporterId =
      TextEditingController(text: DriverSession.transporterId ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _transporterId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final typed = _transporterId.text.trim();
    final scope = AuthorizationSession.scopeKey;
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
      DriverSession.transporterId =
          saved is String && saved.isNotEmpty ? saved : null;
      _transporterId.text = DriverSession.transporterId ?? '';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(DriverSession.transporterId == null
              ? 'Transporter ID removed.'
              : 'Transporter ID saved.')));
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Holding trip.assign is what makes a login the carrier office: owner, owner-driver or dispatcher.
    if (!AuthorizationSession.can('trip.assign')) return const SizedBox.shrink();
    final saved = DriverSession.transporterId;
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
              if (!DriverSession.transporterIdLoaded)
                const Text(
                    'Could not load the transporter ID. Leave Profile and open it again to retry.')
              else if (AuthorizationSession.can('transporter_id.write')) ...[
                TextField(
                    controller: _transporterId,
                    enabled: !_saving,
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
              ] else
                Text(saved ?? 'Not added yet. The carrier owner can add it.'),
            ]));
  }
}
