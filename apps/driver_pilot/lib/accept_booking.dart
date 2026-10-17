import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';

/// Accepts [shipment], as every Accept button on the carrier screens does. When the carrier office (a login that
/// may assign trips) accepts a booking whose trip names no truck, it chooses the truck first, so the shipper has
/// it for the e-way bill from acceptance (owner decision, 16 Oct 2026). A driver, or a trip that already names its
/// truck, accepts with one tap as before; for a carrier with no trucks set up yet the sheet says so and offers to
/// accept without one. [onSending] runs just before the request, after any truck choice, so a screen shows it is
/// busy only while the request is out. False when the office cancelled and nothing was sent; a refusal throws. A
/// trip given a truck since the screen loaded (on the trip screen, or by another login) keeps it, as the server
/// ignores the choice then; the office is told which truck that is.
Future<bool> acceptBooking(BuildContext context, Map<String, dynamic> shipment,
    {VoidCallback? onSending}) async {
  final path = '/v1/pilot/carrier/shipments/${shipment['id']}/accept';
  final tripTruck = shipment['assignedTruckNumber'];
  final tripNamesTruck = tripTruck is String && tripTruck.isNotEmpty;
  if (tripNamesTruck || !AuthorizationSession.can('trip.assign')) {
    onSending?.call();
    await api.post<Map<String, dynamic>>(path);
    return true;
  }
  // Up to full height, so large text does not squeeze the trucks or the no-trucks sentence into a small scroll.
  final choice = await showModalBottomSheet<_TruckChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _TruckChoiceSheet());
  if (choice == null) return false;
  onSending?.call();
  final chosenTruck = choice.truck;
  if (chosenTruck == null) {
    await api.post<Map<String, dynamic>>(path);
    return true;
  }
  final response = await api.post<Map<String, dynamic>>(path,
      data: {'vehicleId': chosenTruck['id']});
  final acceptedShipment = response.data?['shipment'];
  final keptTruck = acceptedShipment is Map
      ? acceptedShipment['assignedTruckNumber']
      : null;
  final chosenNumber =
      portalTruckNumber(chosenTruck['registrationNumber']?.toString() ?? '');
  if (keptTruck is! String ||
      keptTruck.isEmpty ||
      portalTruckNumber(keptTruck) == chosenNumber) {
    return true;
  }
  if (!context.mounted) return true;
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              content: Text(
                  'This trip already has truck ${portalTruckNumber(keptTruck)}, so the booking was accepted with it. To change the truck, use Truck and driver on the trip screen.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK')),
              ]));
  return true;
}

/// What the office chose in the sheet. A null truck accepts without one, for a carrier with no trucks set up yet.
typedef _TruckChoice = ({Map<String, dynamic>? truck});

/// "Which truck carries this trip?": one choice per truck of the carrier, in the portal's form, the only one
/// already chosen when there is just one. Closes with the choice, or with nothing on Cancel.
class _TruckChoiceSheet extends StatefulWidget {
  const _TruckChoiceSheet();

  @override
  State<_TruckChoiceSheet> createState() => _TruckChoiceSheetState();
}

class _TruckChoiceSheetState extends State<_TruckChoiceSheet> {
  List<Map<String, dynamic>> _trucks = [];
  String? _chosenVehicleId;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadTrucks();
  }

  Future<void> _loadTrucks() async {
    setState(() => _failed = false);
    try {
      final response =
          await api.get<Map<String, dynamic>>('/v1/pilot/carrier/fleet');
      if (!mounted) return;
      final raw = response.data?['vehicles'];
      final trucks = raw is List
          ? raw
              .whereType<Map<String, dynamic>>()
              .where((truck) => truck['id'] is String)
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _trucks = trucks;
        _chosenVehicleId =
            trucks.length == 1 ? trucks.single['id'] as String : null;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  List<Widget> _choices() {
    if (_failed) {
      return [
        const Text('Could not load your trucks.'),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: _loadTrucks, child: const Text('Try again'))),
      ];
    }
    if (!_loaded) {
      return [
        const Text('Loading your trucks...'),
        const SizedBox(height: 4),
        const LinearProgressIndicator(),
      ];
    }
    if (_trucks.isEmpty) {
      return [
        const Text(
            'No trucks are set up for this carrier yet. You can accept now, but the shipper sees no truck until one is named on the trip screen. Trucks are added by inviting their drivers from Profile.')
      ];
    }
    return [
      for (final truck in _trucks)
        RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: Text(portalTruckNumber(
                truck['registrationNumber']?.toString() ?? '')),
            value: truck['id'] as String,
            groupValue: _chosenVehicleId,
            onChanged: (value) => setState(() => _chosenVehicleId = value)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosenVehicleId;
    return SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Which truck carries this trip?',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Flexible(
                      child: ListView(shrinkWrap: true, children: _choices())),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_trucks.isNotEmpty)
                      FilledButton(
                          onPressed: chosen == null
                              ? null
                              : () => Navigator.pop<_TruckChoice>(context, (
                                    truck: _trucks.firstWhere(
                                        (truck) => truck['id'] == chosen)
                                  )),
                          child: const Text('Accept with this truck')),
                    if (_loaded && _trucks.isEmpty)
                      FilledButton(
                          onPressed: () => Navigator.pop<_TruckChoice>(
                              context, (truck: null)),
                          child: const Text('Accept without a truck')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel')),
                  ]),
                ])));
  }
}
