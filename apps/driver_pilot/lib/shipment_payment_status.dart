import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'pilot_api.dart';

class ShipmentPaymentStatus extends StatefulWidget {
  const ShipmentPaymentStatus(
      {required this.shipment, this.onAccepted, super.key});
  final Map<String, dynamic> shipment;
  final Future<void> Function()? onAccepted;

  @override
  State<ShipmentPaymentStatus> createState() => _ShipmentPaymentStatusState();
}

class _ShipmentPaymentStatusState extends State<ShipmentPaymentStatus> {
  bool _busy = false;
  String? _error;
  bool get _canAccept =>
      AuthorizationSession.hasRole('SHIPPER') &&
      AuthorizationSession.can('pod.accept') &&
      widget.shipment['customerOrgId'] == AuthorizationSession.organizationId &&
      widget.shipment['status'] == 'PENDING_RELEASE' &&
      widget.shipment['podAtUtcMs'] is num &&
      widget.shipment['podAcceptedAtUtcMs'] == null;

  Future<void> _accept() async {
    final scope = AuthorizationSession.scopeKey;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Accept delivery?'),
              content: const Text(
                  'Confirm that this shipment was delivered. Acceptance allows Finance to release payment before the 48-hour hold ends.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Accept delivery')),
              ],
            ));
    if (!mounted ||
        confirmed != true ||
        !_canAccept ||
        scope != AuthorizationSession.scopeKey) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
          '/shipments/${widget.shipment['id']}/accept-pod');
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      await widget.onAccepted?.call();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shipment = widget.shipment;
    if (shipment['podAtUtcMs'] == null) return const SizedBox.shrink();
    final accepted = shipment['podAcceptedAtUtcMs'] != null;
    final ready = shipment['paymentReady'] == true;
    final hold = shipment['paymentHoldUntilUtcMs'];
    final until = hold is num
        ? DateTime.fromMillisecondsSinceEpoch(hold.toInt()).toLocal().toString()
        : null;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    accepted
                        ? 'Delivery accepted'
                        : 'Proof of delivery submitted',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(shipment['status'] == 'DELIVERED'
                    ? 'Payment released.'
                    : ready
                        ? 'Ready for Finance review and payment release.'
                        : 'Payment on hold${until == null ? '' : ' until $until'}. Shipper acceptance can end the hold earlier.'),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_canAccept)
                  FilledButton(
                      onPressed: _busy ? null : _accept,
                      child: Text(_busy ? 'Accepting…' : 'Accept delivery')),
              ],
            )));
  }
}
