import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';
import 'ui/nv_button.dart';
import 'ui/nv_choice.dart';
import 'ui/nv_sheet.dart';
import 'ui/tokens.dart';

/// Accepts [shipment], as every Accept button on the carrier screens does. When the carrier office (a login that
/// may assign trips) accepts a booking whose trip names no truck, it chooses the truck first, so the shipper has
/// it for the e-way bill from acceptance (owner decision, 16 Oct 2026). A driver, or a trip that already names its
/// truck, accepts with one tap as before; for a carrier with no trucks set up yet the sheet says so and offers to
/// accept without one. [tripInWords] names the trip in the sheet, for example "Bengaluru to Chennai, leaves 18 – 19 Oct".
/// [onSending] runs just before the request, after any truck choice, so a screen shows it is busy only while the
/// request is out. False when the office cancelled and nothing was sent; a refusal throws. A trip given a truck
/// since the screen loaded (on the trip screen, or by another login) keeps it, as the server ignores the choice
/// then; the office is told which truck that is.
Future<bool> acceptBooking(BuildContext context, Map<String, dynamic> shipment,
    {String? tripInWords, VoidCallback? onSending}) async {
  final path = '/v1/pilot/carrier/shipments/${shipment['id']}/accept';
  final tripTruck = shipment['assignedTruckNumber'];
  final tripNamesTruck = tripTruck is String && tripTruck.isNotEmpty;
  if (tripNamesTruck || !AuthorizationSession.can('trip.assign')) {
    onSending?.call();
    await api.post<Map<String, dynamic>>(path);
    return true;
  }
  final shipper = shipment['customerOrgName'] is String &&
          (shipment['customerOrgName'] as String).isNotEmpty
      ? shipment['customerOrgName'] as String
      : 'The shipper';
  final sheetMessage = [
    if (tripInWords != null) '$tripInWords.',
    '$shipper puts this truck number on the e-way bill.',
  ].join(' ');
  final choice = await showNvSheet<_TruckChoice>(
      context: context,
      builder: (_) => _TruckChoiceSheet(message: sheetMessage));
  if (choice == null) return false;
  onSending?.call();
  final chosenTruck = choice.truck;
  if (chosenTruck == null) {
    await api.post<Map<String, dynamic>>(path);
    return true;
  }
  final response = await api
      .post<Map<String, dynamic>>(path, data: {'vehicleId': chosenTruck['id']});
  final acceptedShipment = response.data?['shipment'];
  final keptTruck =
      acceptedShipment is Map ? acceptedShipment['assignedTruckNumber'] : null;
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
                  'This trip already has truck ${portalTruckNumber(keptTruck)}, so the booking was accepted with it. To change the truck, use Truck and driver on the trip screen.',
                  style: NvText.body),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('OK')),
              ]));
  return true;
}

/// What the office chose in the sheet. A null truck accepts without one, for a carrier with no trucks set up yet.
typedef _TruckChoice = ({Map<String, dynamic>? truck});

const _chooseFirstReason = 'Choose a truck first.';
// With no truck list there is nothing to choose, so the reason says how to get the list.
const _trucksDidNotLoadReason = 'Tap Try again to load your trucks.';

/// "Which truck carries this trip?": one row per truck of the carrier, in the portal's form, none chosen until the
/// office chooses (spec: nothing preselected). Closes with the choice, or with nothing on Cancel.
class _TruckChoiceSheet extends StatefulWidget {
  const _TruckChoiceSheet({required this.message});
  final String message;

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
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _truckNumber(Map<String, dynamic> truck) =>
      portalTruckNumber(truck['registrationNumber']?.toString() ?? '');

  // Only the three sizes the app knows get words; anything else shows no size rather than a code.
  String? _sizeWords(Map<String, dynamic> truck) {
    final size = truck['vehicleClass'];
    return const ['SMALL', 'MEDIUM', 'LARGE'].contains(size)
        ? vehicleClassLabel(size as String)
        : null;
  }

  List<Widget> _choices() {
    if (_failed) {
      return [
        Align(
            alignment: Alignment.centerLeft,
            child: NvButton(
                label: 'Try again',
                kind: NvButtonKind.quiet,
                onPressed: _loadTrucks)),
      ];
    }
    if (!_loaded) {
      return [
        const Text('Loading your trucks...', style: NvText.body),
        const LinearProgressIndicator(),
      ];
    }
    if (_trucks.isEmpty) {
      return [
        const Text(
            'No trucks are set up for this carrier yet. You can accept now, but the shipper sees no truck until you name one on the trip screen. To add a truck, invite its driver from Profile.',
            style: NvText.body)
      ];
    }
    return [
      NvChoiceRows<String>(
        options: [
          for (final truck in _trucks)
            NvChoice(truck['id'] as String, _truckNumber(truck),
                caption: _sizeWords(truck), labelIsIdentifier: true),
        ],
        selected: _chosenVehicleId,
        onChanged: (value) => setState(() => _chosenVehicleId = value),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _trucks.where((truck) => truck['id'] == _chosenVehicleId);
    final noTrucks = _loaded && _trucks.isEmpty;
    final String primaryLabel;
    final VoidCallback? onPrimary;
    if (noTrucks) {
      primaryLabel = 'Accept without a truck';
      onPrimary = () => Navigator.pop<_TruckChoice>(context, (truck: null));
    } else if (chosen.isEmpty) {
      primaryLabel = 'Accept with this truck';
      onPrimary = null;
    } else {
      primaryLabel = 'Accept with ${_truckNumber(chosen.first)}';
      onPrimary =
          () => Navigator.pop<_TruckChoice>(context, (truck: chosen.first));
    }
    return NvSheet(
      title: 'Which truck carries this trip?',
      message: widget.message,
      errorText: _failed ? 'Could not load your trucks.' : null,
      choices: _choices(),
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      disabledReason: onPrimary != null
          ? null
          : _failed
              ? _trucksDidNotLoadReason
              : _chooseFirstReason,
    );
  }
}
