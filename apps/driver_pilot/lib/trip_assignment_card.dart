import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';
import 'ui/nv_button.dart';
import 'ui/nv_choice.dart';
import 'ui/nv_message.dart';
import 'ui/nv_section_card.dart';
import 'ui/nv_sheet.dart';
import 'ui/tokens.dart';

/// The truck and the driver on one trip (ca-trip). The carrier owner, owner-driver or dispatcher assigns them in
/// the "Who drives this trip?" sheet (ca-assign); everyone else, drivers included, only reads them.
class TripAssignmentCard extends StatefulWidget {
  const TripAssignmentCard(
      {required this.trip,
      this.tripInWords,
      this.onAssigned,
      this.onAddDriver,
      super.key});
  final Map<String, dynamic> trip;

  /// "Bengaluru to Chennai, 18 – 19 Oct", to name the trip in the sheet.
  final String? tripInWords;

  /// The trip as the server saved it, so the screen can offer Start once a driver is named.
  final ValueChanged<Map<String, dynamic>>? onAssigned;

  /// Opens the screen that adds a driver to the company. Null hides the sheet's link to it.
  final VoidCallback? onAddDriver;

  @override
  State<TripAssignmentCard> createState() => _TripAssignmentCardState();
}

typedef _Assignment = ({Map<String, dynamic>? trip, bool driverBusy});

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

List<Map<String, dynamic>> _maps(Object? raw) => raw is List
    ? raw.whereType<Map<String, dynamic>>().toList()
    : <Map<String, dynamic>>[];

String _truckNumber(Map<String, dynamic> vehicle) =>
    portalTruckNumber(vehicle['registrationNumber']?.toString() ?? '');

class _TripAssignmentCardState extends State<TripAssignmentCard> {
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _drivers = [];
  Map<String, dynamic>? _savedTrip;
  bool _fleetLoaded = false;
  bool _fleetFailed = false;
  bool _driverBusy = false;
  // True from a successful save until the next one starts or the card shows a different trip, so a refused save
  // never shows "Saved.".
  bool _justSaved = false;

  Map<String, dynamic> get _trip => _savedTrip ?? widget.trip;

  bool get _canAssign =>
      AuthorizationSession.can('trip.assign') && _trip['status'] != 'COMPLETED';

  @override
  void initState() {
    super.initState();
    if (_canAssign) _loadFleet();
  }

  @override
  void didUpdateWidget(TripAssignmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trip['id'] == oldWidget.trip['id']) {
      // The screen sends the trip it now has, which is at least as new as the one saved here.
      if (!identical(widget.trip, oldWidget.trip)) _savedTrip = null;
      return;
    }
    setState(() {
      _savedTrip = null;
      _driverBusy = false;
      _justSaved = false;
    });
  }

  Future<void> _loadFleet() async {
    setState(() => _fleetFailed = false);
    try {
      final response =
          await api.get<Map<String, dynamic>>('/v1/pilot/carrier/fleet');
      if (!mounted) return;
      setState(() {
        _vehicles = _maps(response.data?['vehicles'])
            .where((vehicle) => vehicle['id'] is String)
            .toList();
        _drivers = _maps(response.data?['drivers'])
            .where((driver) => driver['userId'] is String)
            .toList();
        _fleetLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _fleetFailed = true);
    }
  }

  Future<void> _openSheet() async {
    // Both lines were about the last save; a new attempt starts here.
    setState(() {
      _justSaved = false;
      _driverBusy = false;
    });
    final assignment = await showNvSheet<_Assignment>(
        context: context,
        builder: (_) => _AssignSheet(
            trip: _trip,
            tripInWords: widget.tripInWords,
            vehicles: _vehicles,
            drivers: _drivers,
            onAddDriver: widget.onAddDriver));
    if (assignment == null || !mounted) return;
    final trip = assignment.trip;
    setState(() {
      if (trip != null) _savedTrip = trip;
      _driverBusy = assignment.driverBusy;
      _justSaved = true;
    });
    if (trip != null) widget.onAssigned?.call(trip);
  }

  String? get _truckWords {
    final named = _text(_trip['assignedTruckNumber']);
    if (named != null) return portalTruckNumber(named);
    final vehicle = _vehicles
        .where((vehicle) => vehicle['id'] == _trip['assignedVehicleId']);
    return vehicle.isEmpty ? null : _truckNumber(vehicle.first);
  }

  String? get _driverWords {
    final named = _text(_trip['assignedDriverName']);
    if (named != null) return named;
    final driver = _drivers
        .where((driver) => driver['userId'] == _trip['assignedDriverUserId']);
    return driver.isEmpty ? null : _text(driver.first['displayName']);
  }

  Widget _row(String label, String? value, {bool identifier = false}) {
    final valueStyle = value == null
        ? NvText.bodyStrong.copyWith(color: NvColors.attention)
        : (identifier
            ? NvText.id.copyWith(fontWeight: FontWeight.w600)
            : NvText.bodyStrong);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: NvText.body.copyWith(color: NvColors.slate)),
          const SizedBox(width: NvSpace.s3),
          Expanded(
              child: Text(value ?? 'Not assigned',
                  textAlign: TextAlign.end, style: valueStyle)),
        ]),
      ),
    );
  }

  List<Widget> _assigning() {
    if (_fleetFailed) {
      return [
        const Text('Could not load your trucks and drivers.',
            style: NvText.body),
        const SizedBox(height: NvSpace.s2),
        NvButton(
            label: 'Try again',
            kind: NvButtonKind.secondary,
            onPressed: _loadFleet),
      ];
    }
    if (!_fleetLoaded) {
      return [
        Semantics(
            liveRegion: true,
            child: const Text('Loading trucks and drivers...',
                style: NvText.caption)),
        const SizedBox(height: NvSpace.s1),
        const LinearProgressIndicator(),
      ];
    }
    // Saving needs both, so with either list empty there is nothing to choose.
    if (_vehicles.isEmpty || _drivers.isEmpty) {
      return [
        const Text('No trucks or drivers are set up for this carrier yet.',
            style: NvText.body)
      ];
    }
    return [
      NvButton(
        label: 'Assign driver',
        // Once a driver is named, Start trip below is the screen's main action.
        kind: _driverWords == null
            ? NvButtonKind.primary
            : NvButtonKind.secondary,
        onPressed: _openSheet,
        fullWidth: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return NvSectionCard(title: 'Truck and driver', children: [
      _row('Truck', _truckWords, identifier: true),
      const Divider(height: 1, color: NvColors.line),
      _row('Driver', _driverWords),
      if (_canAssign) ...[
        const SizedBox(height: NvSpace.s2),
        ..._assigning(),
      ],
      if (_justSaved) ...[
        const SizedBox(height: NvSpace.s3),
        const NvMessage(
            'Saved. The driver is not sent a message. The trip shows on their Loads screen when they pull down to refresh.',
            tone: NvMessageTone.good),
      ],
      if (_driverBusy) ...[
        const SizedBox(height: NvSpace.s3),
        const NvMessage(
            'This driver is already on another trip that is in progress.',
            tone: NvMessageTone.attention),
      ],
    ]);
  }
}

/// "Who drives this trip?": the drivers with none chosen (spec: nothing preselected), then the trucks with the
/// trip's own truck chosen, so the truck can still be changed here as before. Saves, then closes with the result;
/// a refusal keeps the sheet open with the choices kept.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet(
      {required this.trip,
      required this.tripInWords,
      required this.vehicles,
      required this.drivers,
      required this.onAddDriver});
  final Map<String, dynamic> trip;
  final String? tripInWords;
  final List<Map<String, dynamic>> vehicles;
  final List<Map<String, dynamic>> drivers;
  final VoidCallback? onAddDriver;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  String? _driverUserId;
  // A truck no longer in the fleet (a deactivated one, say) shows as unchosen, so it is not sent.
  late String? _vehicleId = widget.vehicles
          .any((vehicle) => vehicle['id'] == widget.trip['assignedVehicleId'])
      ? widget.trip['assignedVehicleId'] as String
      : null;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? get _chosenDriver {
    final chosen =
        widget.drivers.where((driver) => driver['userId'] == _driverUserId);
    return chosen.isEmpty ? null : chosen.first;
  }

  Map<String, dynamic>? get _chosenVehicle {
    final chosen =
        widget.vehicles.where((vehicle) => vehicle['id'] == _vehicleId);
    return chosen.isEmpty ? null : chosen.first;
  }

  String _driverName(Map<String, dynamic> driver) =>
      _text(driver['displayName']) ?? 'Driver';

  // Only the three sizes the app knows get words; anything else shows no size rather than a code.
  String? _sizeWords(Map<String, dynamic> vehicle) {
    final size = vehicle['vehicleClass'];
    return const ['SMALL', 'MEDIUM', 'LARGE'].contains(size)
        ? vehicleClassLabel(size as String)
        : null;
  }

  Future<void> _save() async {
    final vehicle = _chosenVehicle;
    final driver = _chosenDriver;
    if (_saving || vehicle == null || driver == null) return;
    final scope = AuthorizationSession.scopeKey;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(
          '/v1/pilot/anchor-trips/${widget.trip['id']}/assignment',
          data: {'vehicleId': vehicle['id'], 'driverUserId': driver['userId']});
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final trip = response.data?['trip'];
      closeNvSheetAfterSuccess<_Assignment>(context,
          announcement:
              '${_driverName(driver)} assigned. You can start the trip on loading day.',
          result: (
            trip: trip is Map<String, dynamic> ? trip : null,
            driverBusy: response.data?['driverBusy'] == true,
          ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _saveRefusalSentence(e);
        });
      }
    }
  }

  /// 403 means this login may no longer assign trips and 404 that it can no longer see this one; trying
  /// again here fixes neither, while the trip screen reloads when pulled down. A truck or driver that stopped
  /// being valid is refused with the server's sentence while the stale lists still offer it, so a reload is
  /// asked for there too. Any other refusal, a completed trip say, is the server's own sentence.
  static String _saveRefusalSentence(Object e) {
    final response = e is DioException ? e.response : null;
    final status = response?.statusCode;
    if (status == 403 || status == 404) {
      return 'This trip, or your trucks and drivers, changed. Pull down to reload this screen.';
    }
    final body = response?.data;
    if (status == 400 &&
        body is Map &&
        body['error'] == 'invalid_trip_assignment') {
      return '${ewayBillErrorSentence(e)} Pull down to reload your trucks and drivers.';
    }
    return ewayBillErrorSentence(e);
  }

  String get _message {
    final vehicle = _chosenVehicle;
    final what = [
      if (widget.tripInWords != null) widget.tripInWords!,
      if (vehicle != null) 'truck ${_truckNumber(vehicle)}',
    ].join(', ');
    const driverSees =
        'The driver sees the trip and the e-way bill, never the payment.';
    return what.isEmpty ? driverSees : '$what. $driverSees';
  }

  @override
  Widget build(BuildContext context) {
    final assignedDriver = _text(widget.trip['assignedDriverUserId']);
    final replacingDriver = assignedDriver != null &&
        _driverUserId != null &&
        _driverUserId != assignedDriver;
    // On the road with no driver named: started before assignments existed, or by the office without naming one.
    // A driver who started it keeps it only while no one is assigned.
    final onTheRoadWithNoDriverAssigned =
        widget.trip['status'] == 'IN_PROGRESS' && assignedDriver == null;
    final driver = _chosenDriver;
    final ready = driver != null && _chosenVehicle != null;
    return NvSheet(
      title: 'Who drives this trip?',
      message: _message,
      errorText: _error,
      choices: [
        NvChoiceRows<String>(
          options: [
            for (final driver in widget.drivers)
              NvChoice(driver['userId'] as String, _driverName(driver)),
          ],
          selected: _driverUserId,
          onChanged: (value) => setState(() => _driverUserId = value),
        ),
        if (replacingDriver)
          const Text('A driver who is replaced stops seeing this trip.',
              style: NvText.body),
        if (onTheRoadWithNoDriverAssigned)
          const Text(
              'This trip is already on the road with no driver assigned. If a driver started it, they stop seeing it once you choose someone else.',
              style: NvText.body),
        const SizedBox(height: NvSpace.s2),
        NvChoiceRows<String>(
          label: 'Truck',
          options: [
            for (final vehicle in widget.vehicles)
              NvChoice(vehicle['id'] as String, _truckNumber(vehicle),
                  caption: _sizeWords(vehicle), labelIsIdentifier: true),
          ],
          selected: _vehicleId,
          onChanged: (value) => setState(() => _vehicleId = value),
        ),
      ],
      primaryLabel: ready ? 'Assign ${_driverName(driver)}' : 'Assign driver',
      onPrimary: ready ? _save : null,
      disabledReason: ready
          ? null
          : (driver == null
              ? 'Choose a driver first.'
              : 'Choose a truck first.'),
      loading: _saving,
      loadingLabel: 'Assigning',
      footer: widget.onAddDriver == null
          ? null
          : NvButton(
              label: 'Add a driver to your company',
              kind: NvButtonKind.quiet,
              fullWidth: true,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onAddDriver!();
              }),
    );
  }
}
