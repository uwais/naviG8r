import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'driver_theme.dart';
import 'eway_bill_words.dart';
import 'pilot_api.dart';

/// The truck and the driver on one trip. The carrier owner, owner-driver or dispatcher picks them; everyone
/// else, drivers included, only reads them. Nothing is preselected except what the trip already has assigned.
class TripAssignmentCard extends StatefulWidget {
  const TripAssignmentCard({required this.trip, super.key});
  final Map<String, dynamic> trip;

  @override
  State<TripAssignmentCard> createState() => _TripAssignmentCardState();
}

class _TripAssignmentCardState extends State<TripAssignmentCard> {
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _drivers = [];
  late String? _vehicleId = _text(widget.trip['assignedVehicleId']);
  late String? _driverUserId = _text(widget.trip['assignedDriverUserId']);
  Map<String, dynamic>? _savedTrip;
  bool _fleetLoaded = false;
  bool _fleetFailed = false;
  bool _saving = false;
  bool _driverBusy = false;
  // True from a successful save until a choice changes, the next save starts or the card shows a different
  // trip, so a refused save never shows "Saved." (starting the save already cleared it).
  bool _justSaved = false;
  String? _error;

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

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
    if (widget.trip['id'] == oldWidget.trip['id']) return;
    setState(() {
      _savedTrip = null;
      _vehicleId = _text(widget.trip['assignedVehicleId']);
      _driverUserId = _text(widget.trip['assignedDriverUserId']);
      if (_fleetLoaded) _forgetChoicesOutsideFleet();
      _driverBusy = false;
      _justSaved = false;
      _error = null;
    });
  }

  /// A truck or driver no longer in the fleet (a deactivated truck, say) shows as unchosen, so it is not
  /// sent either. A dropdown also refuses a value none of its items carry.
  void _forgetChoicesOutsideFleet() {
    if (!_vehicles.any((vehicle) => vehicle['id'] == _vehicleId)) {
      _vehicleId = null;
    }
    if (!_drivers.any((driver) => driver['userId'] == _driverUserId)) {
      _driverUserId = null;
    }
  }

  static List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw.whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];

  Future<void> _loadFleet() async {
    setState(() => _fleetFailed = false);
    try {
      final response =
          await api.get<Map<String, dynamic>>('/v1/pilot/carrier/fleet');
      if (!mounted) return;
      setState(() {
        _vehicles = _maps(response.data?['vehicles']);
        _drivers = _maps(response.data?['drivers']);
        _forgetChoicesOutsideFleet();
        _fleetLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _fleetFailed = true);
    }
  }

  Future<void> _save() async {
    final vehicleId = _vehicleId;
    final driverUserId = _driverUserId;
    if (_saving || vehicleId == null || driverUserId == null) return;
    final scope = AuthorizationSession.scopeKey;
    setState(() {
      _saving = true;
      _error = null;
      _justSaved = false;
      _driverBusy = false;
    });
    try {
      final response = await api.post<Map<String, dynamic>>(
          '/v1/pilot/anchor-trips/${widget.trip['id']}/assignment',
          data: {'vehicleId': vehicleId, 'driverUserId': driverUserId});
      if (!mounted || scope != AuthorizationSession.scopeKey) return;
      final trip = response.data?['trip'];
      setState(() {
        if (trip is Map<String, dynamic>) _savedTrip = trip;
        _driverBusy = response.data?['driverBusy'] == true;
        _justSaved = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _saveRefusalSentence(e));
    } finally {
      if (mounted) setState(() => _saving = false);
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

  String _assignmentWords() {
    final truck = _text(_trip['assignedTruckNumber']);
    final driver = _text(_trip['assignedDriverName']);
    if (truck == null && driver == null) {
      return 'No truck or driver is assigned to this trip yet.';
    }
    return 'Truck: ${truck ?? 'not assigned'}. Driver: ${driver ?? 'not assigned'}.';
  }

  Widget _picker(
      {required String label,
      required String hint,
      required String? value,
      required List<DropdownMenuItem<String>> items,
      required ValueChanged<String?> onChanged}) {
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: value,
                    hint: Text(hint),
                    items: items,
                    onChanged: _saving ? null : onChanged))));
  }

  List<Widget> _pickers() {
    if (_fleetFailed) {
      return [
        const Text('Could not load your trucks and drivers.'),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: _loadFleet, child: const Text('Try again'))),
      ];
    }
    if (!_fleetLoaded) {
      return [
        const Text('Loading trucks and drivers...'),
        const SizedBox(height: 4),
        const LinearProgressIndicator(),
      ];
    }
    // Saving needs both, so with either list empty there is nothing to choose.
    if (_vehicles.isEmpty || _drivers.isEmpty) {
      return [const Text('No trucks or drivers are set up for this carrier yet.')];
    }
    final assignedDriver = _text(_trip['assignedDriverUserId']);
    final anythingAssigned =
        _text(_trip['assignedVehicleId']) != null || assignedDriver != null;
    final replacingDriver = assignedDriver != null &&
        _driverUserId != null &&
        _driverUserId != assignedDriver;
    // Started before assignments existed: the driver who started it keeps it only while no one is assigned.
    final onTheRoadWithNoDriverAssigned =
        _trip['status'] == 'IN_PROGRESS' && assignedDriver == null;
    return [
      _picker(
          label: 'Truck',
          hint: 'Choose a truck',
          value: _vehicleId,
          items: [
            for (final vehicle in _vehicles)
              DropdownMenuItem(
                  value: vehicle['id']?.toString(),
                  // The same form as the Truck line above, however the number was typed.
                  child: Text(plainTruckNumber(
                      vehicle['registrationNumber']?.toString() ?? '')))
          ],
          onChanged: (value) => setState(() {
                _vehicleId = value;
                _justSaved = false;
              })),
      _picker(
          label: 'Driver',
          hint: 'Choose a driver',
          value: _driverUserId,
          items: [
            for (final driver in _drivers)
              DropdownMenuItem(
                  value: driver['userId']?.toString(),
                  child: Text(driver['displayName']?.toString() ?? ''))
          ],
          onChanged: (value) => setState(() {
                _driverUserId = value;
                // The warning was about the driver chosen before.
                _driverBusy = false;
                _justSaved = false;
              })),
      if (replacingDriver)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('A driver who is replaced stops seeing this trip.')),
      if (onTheRoadWithNoDriverAssigned)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'This trip is already on the road. If you choose a different driver, the driver who started it stops seeing it.')),
      if (_driverBusy)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'This driver is already on another trip that is in progress.')),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      const SizedBox(height: 8),
      Text(
          anythingAssigned
              ? 'Saving replaces the truck and driver assigned now. You can change them until the trip is complete.'
              : 'Choose a truck and a driver, then tap Save. You can change them until the trip is complete.',
          style: const TextStyle(color: DriverTheme.muted)),
      const SizedBox(height: 8),
      Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
              onPressed: _saving || _vehicleId == null || _driverUserId == null
                  ? null
                  : _save,
              child: Text(_saving ? 'Saving...' : 'Save'))),
      if (_justSaved && !_saving)
        const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Saved. The driver is not sent a message. The trip shows on their Loads screen when they pull down to refresh.')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Truck and driver',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(_assignmentWords(),
                      style: const TextStyle(color: DriverTheme.navy)),
                  if (_canAssign) ..._pickers(),
                ])));
  }
}
