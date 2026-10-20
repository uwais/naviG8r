// Over 500 lines on purpose: one screen with one state of about 570 lines, holding the load,
// refresh, polling and every step's panel; splitting it would pass that state between files.

import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../authorization_session.dart";
import "../shipment_payment_status.dart";
import "../eway_bill_card.dart";
import "../eway_bill_portal_link.dart";
import "../customer_layout.dart";
import "../location_editor.dart";
import "../pilot_api.dart";
import "../notification_center.dart";
import "../plain_error_sentence.dart";
import "../shipment_steps.dart";
import "../ui/format.dart";
import "../ui/nv_action_bar.dart";
import "../ui/nv_button.dart";
import "../ui/nv_map.dart";
import "../ui/nv_message.dart";
import "../ui/nv_status_label.dart";
import "../ui/nv_step_list.dart";
import "../ui/pending_copy.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";

// Book sets it just before opening the new shipment, so this screen moves focus to its title.
String? lastBookedShipmentId;

DateTime? _momentFromUtcMs(Object? value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
    : null;

/// "18 Oct, 06:10 IST".
String _dateAndTime(DateTime moment) =>
    "${formatDate(moment)}, ${formatTimeIst(moment)}";

class CustomerShipmentDetailScreen extends StatefulWidget {
  const CustomerShipmentDetailScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<CustomerShipmentDetailScreen> createState() =>
      _CustomerShipmentDetailScreenState();
}

class _CustomerShipmentDetailScreenState
    extends State<CustomerShipmentDetailScreen> {
  bool _loading = false;
  bool _refreshing = false;
  String? _error;
  String? _trackingError;
  Map<String, dynamic>? _shipment;
  Map<String, dynamic>? _payment;
  Map<String, dynamic>? _trip;
  Map<String, dynamic>? _liveLocation;
  bool _isLive = false;
  bool _refreshFailed = false;
  DateTime? _lastLoadedAt;
  num _savedAtUtcMs = 0;
  Timer? _poll;
  final _titleFocus = FocusNode();

  // Only a refresh the server never answered keeps what was loaded, so a half-typed e-way bill form
  // survives weak signal. An answered refusal (401, 403, 404) means this person may no longer see it.
  void _showLoadFailure(Object e) {
    if (_shipment != null && serverNeverAnswered(e)) {
      _refreshFailed = true;
      return;
    }
    _shipment = null;
    _refreshFailed = false;
    _payment = null;
    _trip = null;
    _liveLocation = null;
    _error = plainErrorSentence(e,
        "Could not load this shipment. Check your connection and pull down to try again.");
  }

  String get _refreshFailedLine {
    const sentence =
        "Could not refresh, so this may be out of date. Pull down to try again.";
    final at = _lastLoadedAt;
    if (at == null) return sentence;
    return "$sentence Last updated ${formatTimeIst(at)}";
  }

  String _signedInIdentity() =>
      "${AuthorizationSession.identityGeneration}:${AuthorizationSession.scopeKey}";

  // A response, or a failure, for whoever was signed in before must not show to whoever is now.
  void _forgetEarlierIdentity() {
    _shipment = null;
    _payment = null;
    _trip = null;
    _liveLocation = null;
    _refreshFailed = false;
    _error = null;
  }

  // A refresh that started before an e-way bill save can land after it; the saved shipment wins.
  void _takeShipment(Map<String, dynamic>? data) {
    final shipment = data?["shipment"];
    final payment = data?["payment"];
    final time =
        shipment is Map<String, dynamic> ? shipment["updatedAtUtcMs"] : null;
    if (!(time is num && time < _savedAtUtcMs && _shipment != null)) {
      _shipment = shipment is Map<String, dynamic> ? shipment : null;
    }
    _payment = payment is Map<String, dynamic> ? payment : null;
    _refreshFailed = false;
    _lastLoadedAt = DateTime.now();
  }

  void _takeSavedShipment(Map<String, dynamic> shipment) => setState(() {
        _shipment = shipment;
        final time = shipment["updatedAtUtcMs"];
        if (time is num) _savedAtUtcMs = time;
      });

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final identity = _signedInIdentity();
    try {
      final r = await api
          .get<Map<String, dynamic>>("/shipments/${widget.shipmentId}");
      if (!mounted) return;
      if (identity != _signedInIdentity()) {
        setState(_forgetEarlierIdentity);
        return;
      }
      setState(() => _takeShipment(r.data));
      await _loadTracking();
    } catch (e) {
      if (!mounted) return;
      if (identity != _signedInIdentity()) {
        setState(_forgetEarlierIdentity);
      } else {
        setState(() => _showLoadFailure(e));
      }
    } finally {
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTracking() async {
    final identity = _signedInIdentity();
    try {
      final r = await api.get<Map<String, dynamic>>(
          "/shipments/${widget.shipmentId}/tracking");
      if (!mounted || identity != _signedInIdentity()) return;
      setState(() {
        _trip = r.data?["trip"] is Map<String, dynamic>
            ? r.data!["trip"] as Map<String, dynamic>
            : null;
        _liveLocation = r.data?["liveLocation"] is Map<String, dynamic>
            ? r.data!["liveLocation"] as Map<String, dynamic>
            : null;
        _isLive = r.data?["isLive"] == true;
        _trackingError = null;
      });
    } catch (e) {
      if (!mounted || identity != _signedInIdentity()) return;
      setState(() => _trackingError = plainErrorSentence(e,
          "Could not load the trip. Check your connection and pull down to try again."));
    }
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final identity = _signedInIdentity();
    try {
      final r = await api
          .get<Map<String, dynamic>>("/shipments/${widget.shipmentId}");
      if (!mounted) return;
      if (identity != _signedInIdentity()) {
        setState(_forgetEarlierIdentity);
        return;
      }
      setState(() {
        _takeShipment(r.data);
        _error = null;
      });
      await _loadTracking();
    } catch (e) {
      if (!mounted) return;
      if (identity != _signedInIdentity()) {
        setState(_forgetEarlierIdentity);
      } else {
        setState(() => _showLoadFailure(e));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    final st = _shipment?["status"]?.toString() ?? "";
    if (st == "DELIVERED" || st == "FAILED_CARRIER_REFUNDED") return;
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _refreshAll();
    });
  }

  LatLng? _latLngFromGeo(Object? g) {
    if (g is! Map) return null;
    final lat = g["lat"];
    final lng = g["lng"];
    if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted) _schedulePoll();
    });
    // After Pay and book, a screen reader starts on the new shipment's title (accessibility.md).
    if (widget.shipmentId == lastBookedShipmentId) {
      lastBookedShipmentId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _titleFocus.dispose();
    super.dispose();
  }

  String get _title {
    final shipment = _shipment;
    if (shipment == null) return "Shipment";
    return shipmentRouteName(shipment, lane: _trip, withDate: false) ??
        "Shipment";
  }

  /// The booking's amount: the payment's own amount, else the booking's price.
  num? get _amountPaise {
    final amount = _payment?["amountPaise"] ?? _shipment?["grossPaise"];
    return amount is num ? amount : null;
  }

  String? get _paymentStatus => _payment?["status"]?.toString();

  /// Only an authorized or captured payment holds the shipper's money.
  bool get _paymentHeld =>
      _paymentStatus == "AUTHORIZED" || _paymentStatus == "CAPTURED";

  String _notPaidSentence(String carrier) =>
      "${_paymentStatus == "FAILED" ? "Payment did not go through. " : ""}"
      "This booking is not paid, so $carrier cannot accept it yet. "
      "To pay or cancel it, contact ${PendingCopy.changeOrCancelContact}.";

  NvStep _step(ShipmentStep step, Map<String, dynamic> shipment,
      ShipmentProgress progress) {
    final carrier = carrierOf(shipment);
    switch (step.name) {
      case ShipmentStepName.booked:
        final booked = _momentFromUtcMs(shipment["createdAtUtcMs"]);
        final amount = _amountPaise;
        final facts = [
          if (booked != null) formatDate(booked),
          if (amount != null && _paymentHeld && !progress.delivered)
            "${formatRupees(amount)} held until delivery",
        ];
        return NvStep(
            title: step.title,
            state: step.state,
            who: facts.isEmpty ? null : facts.join(" · "),
            panel: paymentNotTaken(_paymentStatus)
                ? Text(_notPaidSentence(carrier), style: NvText.body)
                : null);
      case ShipmentStepName.carrierAccepts:
        final truck = shipment["assignedTruckNumber"]?.toString() ?? "";
        final String waiting;
        if (_paymentHeld) {
          waiting =
              "Waiting for $carrier to accept. Your payment is on hold; it is collected after delivery.";
        } else if (paymentNotTaken(_paymentStatus)) {
          waiting = "$carrier can accept once this booking is paid.";
        } else {
          waiting = "Waiting for $carrier to accept.";
        }
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.state == NvStepState.done && truck.isNotEmpty
                ? "$carrier · Truck $truck"
                : step.who,
            panel: Text(waiting, style: NvText.body));
      case ShipmentStepName.ewayBill:
        final partOne = step.state == NvStepState.yours &&
            progress.ewayBill == EwayBillStage.none;
        return NvStep(
            title: step.title,
            state: step.state,
            who: partOne ? "You · Part 1 of 2" : step.who,
            panelAlwaysShown: true,
            panel: EwayBillCard(
                key: const ValueKey("eway-bill-card"),
                shipment: shipment,
                portalButtonInPanel: customerIsDesktop(context),
                onSaved: _takeSavedShipment));
      case ShipmentStepName.billCheck:
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.who,
            panel: const Text(
                "NaviG8r staff check the bill on the portal by hand. If they find a problem, this shipment and your Home screen show what to fix.",
                style: NvText.body));
      case ShipmentStepName.onTheWay:
        final started = _momentFromUtcMs(_trip?["startedAtUtcMs"]);
        final laneDays = _trip == null ? null : laneDates(_trip!);
        final pickup = shipment["pickupAddress"]?.toString() ?? "";
        final String sentence;
        if (progress.inTransit) {
          sentence = started == null || pickup.isEmpty
              ? "$carrier confirms when it is delivered."
              : "Left $pickup on ${formatDate(started)} at ${formatTimeIst(started)}. $carrier confirms when it is delivered.";
        } else {
          sentence = laneDays == null
              ? "Nothing for you to do now. $carrier starts the trip."
              : "Nothing for you to do now. $carrier starts the trip. The truck leaves $laneDays.";
        }
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.state == NvStepState.done && started != null
                ? _dateAndTime(started)
                : step.who,
            panel: Text(sentence, style: NvText.body));
      case ShipmentStepName.delivered:
        final deliveredAt = _momentFromUtcMs(shipment["podAtUtcMs"]);
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.state == NvStepState.done && deliveredAt != null
                ? _dateAndTime(deliveredAt)
                : step.who);
    }
  }

  Widget _summary(Map<String, dynamic> shipment, ShipmentProgress progress) {
    final facts = [
      shipmentRouteName(shipment, withDate: false),
      weightWords(shipment),
      laneLeaves(_trip),
      carrierOf(shipment),
    ].whereType<String>().join(" · ");
    final externalId = shipment["externalLoadId"]?.toString() ?? "";
    final open = !progress.delivered && !progress.cancelled;
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NvStatusLabel(progress.statusWord, tone: progress.statusTone),
          const SizedBox(height: NvSpace.s2),
          Text(facts, style: NvText.caption),
          if (externalId.isNotEmpty)
            Text("Synced from ERP · $externalId", style: NvText.caption),
          if (AuthorizationSession.can("conversation.read")) ...[
            const SizedBox(height: NvSpace.s3),
            NvButton(
                label: "Messages",
                kind: NvButtonKind.secondary,
                onPressed: () =>
                    openShipmentConversation(context, widget.shipmentId)),
          ],
          // Shippers cannot cancel in the app (owner decision); the contact is the way to change one.
          if (open) ...[
            const SizedBox(height: NvSpace.s3),
            const Text(
                "Booked shipments cannot be cancelled in the app; to change one, contact ${PendingCopy.changeOrCancelContact}.",
                style: NvText.caption),
          ],
        ],
      ),
    );
  }

  Widget _delivered(Map<String, dynamic> shipment) {
    final paid = _paymentHeld ? _amountPaise : null;
    final released = shipment["status"] == "DELIVERED";
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              "${carrierOf(shipment)} confirmed delivery and added proof of delivery."
              // Until the payment is released the hold line below says what happens to it.
              "${released && paid != null ? " Your payment of ${formatRupees(paid)} is collected now." : ""}",
              style: NvText.body),
          const SizedBox(height: NvSpace.s3),
          NvButton(
              label: "Book another shipment",
              kind: NvButtonKind.secondary,
              fullWidth: true,
              onPressed: () => context.go("/customer/trips")),
        ],
      ),
    );
  }

  Widget _cancelled() {
    final amount = _amountPaise;
    // A booking never paid is also marked refunded on cancel, and the shipper's payment record
    // does not say which it was, so a refund is told without claiming the shipper paid.
    final refunded = _paymentStatus == "REFUNDED";
    final nothingPaid = paymentNotTaken(_paymentStatus);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: NvSpace.s1),
          child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: NvSpace.s3,
              children: [
                Text(label, style: NvText.caption),
                Text(value,
                    style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
              ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(NvSpace.s4),
          decoration: BoxDecoration(
              color: NvColors.card,
              borderRadius: BorderRadius.circular(NvRadius.card),
              border: Border.all(color: NvColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text("This shipment was cancelled",
                    style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
              ),
              const SizedBox(height: NvSpace.s2),
              if (nothingPaid)
                const Text("Nothing was paid for this booking.",
                    style: NvText.body)
              else ...[
                if (_paymentHeld && amount != null)
                  row("You paid", formatRupees(amount)),
                if (refunded)
                  Text(
                      amount == null
                          ? "If you paid for this booking, all of it is refunded."
                          : "If you paid the ${formatRupees(amount)} for this booking, all of it is refunded.",
                      style: NvText.body),
                const SizedBox(height: NvSpace.s2),
                const Text(
                    "Refunds reach your account in the time your bank or payment app takes.",
                    style: NvText.caption),
              ],
            ],
          ),
        ),
        const SizedBox(height: NvSpace.s3),
        Container(
          padding: const EdgeInsets.all(NvSpace.s4),
          decoration: BoxDecoration(
              color: NvColors.sunken,
              borderRadius: BorderRadius.circular(NvRadius.card)),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: nothingPaid
                      ? "Questions about this booking? "
                      : "Questions about this refund? ",
                  style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
              const TextSpan(
                  text: "Contact ${PendingCopy.changeOrCancelContact}."),
            ]),
            style: NvText.body,
          ),
        ),
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Find a lane",
            fullWidth: true,
            onPressed: () => context.go("/customer/trips")),
      ],
    );
  }

  Widget? _trackingMap(Map<String, dynamic> shipment) {
    final origin = _latLngFromGeo(_trip?["origin"]);
    final destination = _latLngFromGeo(_trip?["destination"]);
    if (origin == null || destination == null) return null;
    return NvMap(
      map: tripTrackingMap(
        origin: origin,
        destination: destination,
        pickup: _latLngFromGeo(shipment["pickup"]),
        drop: _latLngFromGeo(shipment["drop"]),
        driver: _isLive ? _latLngFromGeo(_liveLocation) : null,
      ),
    );
  }

  List<Widget> _content(
      Map<String, dynamic> shipment, ShipmentProgress progress, bool desktop) {
    final map = progress.cancelled ? null : _trackingMap(shipment);
    return [
      if (!desktop) ...[
        _summary(shipment, progress),
        const SizedBox(height: NvSpace.s5),
      ] else
        const SizedBox(height: NvSpace.s2),
      if (progress.cancelled)
        _cancelled()
      else ...[
        NvStepList(listName: "Steps for this shipment", steps: [
          for (final step in progress.steps) _step(step, shipment, progress),
        ]),
        const SizedBox(height: NvSpace.s4),
        if (progress.delivered) ...[
          _delivered(shipment),
          const SizedBox(height: NvSpace.s3),
        ],
        ShipmentPaymentStatus(shipment: shipment, onAccepted: () => _load()),
        if (map != null) ...[
          const SizedBox(height: NvSpace.s3),
          map,
          if (_isLive)
            const Padding(
              padding: EdgeInsets.only(top: NvSpace.s1),
              child: Text("Live tracking — updates every ~30 seconds.",
                  style: NvText.caption),
            ),
        ],
        if (_trackingError != null) ...[
          const SizedBox(height: NvSpace.s2),
          Text(_trackingError!, style: NvText.caption),
        ],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final desktop = customerIsDesktop(context);
    final progress = shipment == null
        ? null
        : shipmentProgress(shipment,
            tripStatus: _trip?["status"]?.toString(),
            paymentStatus: _paymentStatus);
    // Part 1 of the e-way bill: the portal is the shipper's one primary action, kept in view. On a
    // desktop it sits in the e-way bill step instead (wb-shipment).
    final portalIsPrimary = shipment != null &&
        shipment["status"] == "BOOKED" &&
        ewayBillStageOf(shipment) == EwayBillStage.none &&
        shipperCanWriteEwayBill(shipment);
    return CustomerScaffold(
      title: _title,
      titleFocus: _titleFocus,
      currentPath: "/customer/shipments/${widget.shipmentId}",
      actionBar: portalIsPrimary && !desktop
          ? const NvActionBar(
              child: EwayBillPortalButton(
                  label: "Open the e-way bill portal",
                  kind: NvButtonKind.primary))
          : null,
      sideBuilder: desktop && shipment != null
          ? (_) => _summary(shipment, progress!)
          : null,
      bodyBuilder: (_) => _loading && shipment == null
          ? const NvStepList(
              listName: "Steps for this shipment",
              steps: [],
              loading: true,
              loadingWords: "Loading this shipment's steps.")
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.only(top: NvSpace.s2, bottom: NvSpace.s6),
                children: [
                  // Always one child here, so the steps below keep their place and their state.
                  if (_error != null)
                    NvMessage(_error!, tone: NvMessageTone.problem)
                  else if (_refreshFailed)
                    Text(_refreshFailedLine, style: NvText.caption)
                  else
                    const SizedBox.shrink(),
                  if (shipment != null)
                    ..._content(shipment, progress!, desktop),
                ],
              ),
            ),
    );
  }
}
