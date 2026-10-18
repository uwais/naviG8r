// Over 500 lines on purpose: one screen. Its state is about 450 lines because getting a price,
// paying and booking share it, and the three cards after it are shown only here.

import "dart:async";

import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../authorization_session.dart";
import "../google_geocoding.dart";
import "../customer_checkout.dart";
import "../customer_layout.dart";
import "../customer_session.dart";
import "../location_editor.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "../ui/format.dart";
import "../ui/nv_action_bar.dart";
import "../ui/nv_button.dart";
import "../ui/nv_field.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_map.dart";
import "../ui/nv_message.dart";
import "../ui/nv_sheet.dart";
import "../ui/pending_copy.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";
import "place_input.dart";
import "search_summary.dart";
import "announce.dart";
import "shipment_screen.dart";

String _apiErrorCode(Object error) {
  final body = error is DioException ? error.response?.data : null;
  return body is Map ? body["error"]?.toString() ?? "" : "";
}

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({
    required this.laneId,
    this.searchedWeightKg,
    this.searchedPickup,
    this.searchedDrop,
    this.findPlace = GoogleGeocodingService.forwardAddress,
    super.key,
  });

  /// From the Book link a lane card builds: the lane, and the match search's weight and places.
  factory CustomerBookShipmentScreen.fromQuery(Map<String, String> query,
      {PlaceFinder findPlace = GoogleGeocodingService.forwardAddress}) {
    ({String words, LatLng? point})? place(String name) {
      final words = query[name] ?? "";
      if (words.isEmpty) return null;
      final lat = double.tryParse(query["${name}Lat"] ?? "");
      final lng = double.tryParse(query["${name}Lng"] ?? "");
      // tryParse takes "NaN" and "Infinity"; without a point on the globe the words are looked up.
      final onTheGlobe = lat != null &&
          lng != null &&
          lat >= -90 &&
          lat <= 90 &&
          lng >= -180 &&
          lng <= 180;
      return (words: words, point: onTheGlobe ? LatLng(lat, lng) : null);
    }

    final weightKg = int.tryParse(query["weightKg"] ?? "");
    return CustomerBookShipmentScreen(
      laneId: query["anchorTripId"] ?? "",
      searchedWeightKg: weightKg != null && weightKg > 0 ? weightKg : null,
      searchedPickup: place("pickup"),
      searchedDrop: place("drop"),
      findPlace: findPlace,
    );
  }

  final String laneId;
  final int? searchedWeightKg;
  final ({String words, LatLng? point})? searchedPickup;
  final ({String words, LatLng? point})? searchedDrop;
  final PlaceFinder findPlace;

  @override
  State<CustomerBookShipmentScreen> createState() =>
      _CustomerBookShipmentScreenState();
}

class _CustomerBookShipmentScreenState
    extends State<CustomerBookShipmentScreen> {
  late final _weightKg =
      TextEditingController(text: widget.searchedWeightKg?.toString() ?? "");
  late final _pickup = PlaceInput(
      words: widget.searchedPickup?.words ?? "",
      point: widget.searchedPickup?.point);
  late final _drop = PlaceInput(
      words: widget.searchedDrop?.words ?? "",
      point: widget.searchedDrop?.point);
  String? _weightError;
  bool _tooHeavy = false;
  Map<String, dynamic>? _lane;
  bool _loadingLane = true;
  bool _laneFailed = false;
  Map<String, dynamic>? _quote;
  int? _pricedWeightKg;
  bool _pricing = false;
  bool _booking = false;
  String? _actionError;
  CustomerCheckoutController? _checkout;
  String? _pendingShipmentIdForCheckout;

  num? get _pricePaise => _quote?["grossPaise"] as num?;

  @override
  void initState() {
    super.initState();
    _checkout = CustomerCheckoutController(
      onSuccess: ({required orderId, required paymentId, required signature}) {
        _onCheckoutSuccess(
            orderId: orderId, paymentId: paymentId, signature: signature);
      },
      onError: _onCheckoutError,
    )..init();
    scheduleMicrotask(_loadLane);
  }

  @override
  void dispose() {
    _checkout?.dispose();
    _weightKg.dispose();
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _loadLane() async {
    setState(() {
      _loadingLane = true;
      _laneFailed = false;
    });
    try {
      final r = await api.get<Map<String, dynamic>>(
          "/anchor-trips/${Uri.encodeComponent(widget.laneId)}");
      final lane = r.data?["trip"];
      if (!mounted) return;
      setState(() {
        _lane = lane is Map<String, dynamic> ? lane : null;
        _laneFailed = _lane == null;
      });
    } catch (_) {
      if (mounted) setState(() => _laneFailed = true);
    } finally {
      if (mounted) setState(() => _loadingLane = false);
    }
  }

  void _clearPrice() {
    if (_quote == null) return;
    setState(() {
      _quote = null;
      _pricedWeightKg = null;
    });
    announce(context, "Price cleared. Get a new price before paying.");
  }

  void _showTooHeavy() {
    const sentence =
        "This lane does not have room for that weight. Enter a lower weight, or choose another lane.";
    setState(() {
      _quote = null;
      _weightError = sentence;
      _tooHeavy = true;
    });
    announce(context, sentence, assertiveness: Assertiveness.assertive);
  }

  Future<void> _getPrice() async {
    final weightKg = int.tryParse(_weightKg.text.trim()) ?? 0;
    setState(() {
      _weightError =
          weightKg <= 0 ? "Enter a weight greater than 0 kg." : null;
      _tooHeavy = false;
      _actionError = null;
    });
    final room = _lane == null ? null : roomLeftKg(_lane!);
    if (weightKg > 0 && room != null && weightKg > room) {
      _showTooHeavy();
      return;
    }
    setState(() => _pricing = true);
    try {
      const notFound =
          "Could not find this place. Check the name and try again.";
      final pickupPlaced = await _pickup.place(widget.findPlace,
          emptyError: "Enter the pickup place.", notFoundError: notFound);
      final dropPlaced = await _drop.place(widget.findPlace,
          emptyError: "Enter the drop place.", notFoundError: notFound);
      if (!mounted || !pickupPlaced || !dropPlaced || weightKg <= 0) return;
      final r = await api.post<Map<String, dynamic>>("/shipments/quote",
          data: {
            "weightKg": weightKg,
            "pickup": _placePayload(_pickup),
            "drop": _placePayload(_drop),
            "anchorTripId": widget.laneId,
          });
      final quote = r.data?["quote"];
      if (!mounted || quote is! Map<String, dynamic>) return;
      setState(() {
        _quote = quote;
        _pricedWeightKg = weightKg;
      });
      final spokenRupees = formatRupees(_pricePaise ?? 0).substring(1);
      announce(context,
          "Price for ${formatKg(weightKg)}: $spokenRupees rupees. This is the full price.");
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = plainErrorSentence(
            error, "Could not get a price. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _pricing = false);
    }
  }

  Map<String, dynamic> _placePayload(PlaceInput place) => {
        "lat": place.point!.latitude,
        "lng": place.point!.longitude,
        "label": place.text,
      };

  Future<void> _confirmAndBook() async {
    final lane = _lane;
    final price = _pricePaise;
    if (lane == null || price == null) return;
    final goAhead = await showNvSheet<bool>(
      context: context,
      builder: (_) => _ConfirmBookingSheet(
          lane: lane, weightKg: _pricedWeightKg!, pricePaise: price),
    );
    if (goAhead == true && mounted) await _book();
  }

  Future<void> _onCheckoutSuccess({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final id = _pendingShipmentIdForCheckout;
    var confirmed = false;
    if (id != null && id.isNotEmpty) {
      try {
        await api.post<Map<String, dynamic>>(
          "/v1/payments/razorpay/confirm",
          data: {
            "shipmentId": id,
            "razorpayOrderId": orderId,
            "razorpayPaymentId": paymentId,
            "razorpaySignature": signature,
          },
        );
        confirmed = true;
      } catch (_) {}
    }
    if (!mounted) return;
    if (id != null) {
      _openBookedShipment(id,
          announcement: confirmed
              ? null
              : "Booked, but the payment could not be confirmed yet. The shipment shows whether it went through.");
    }
    _pendingShipmentIdForCheckout = null;
  }

  /// [announcement] replaces "Booked. Waiting for the carrier" when the booking is not known to be paid.
  void _openBookedShipment(String shipmentId, {String? announcement}) {
    lastBookedShipmentId = shipmentId;
    final carrier = _lane?["carrierDisplayName"]?.toString() ?? "the carrier";
    announce(
        context, announcement ?? "Booked. Waiting for $carrier to accept.");
    context.go("/customer/shipments/$shipmentId");
  }

  // The shipment already exists, so the shipper goes to it: Pay again here would book a second one.
  void _onCheckoutError(String message) {
    final id = _pendingShipmentIdForCheckout;
    _pendingShipmentIdForCheckout = null;
    if (!mounted) return;
    const sentence = "Payment did not go through. This booking is not paid.";
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(sentence)));
    if (id != null) {
      _openBookedShipment(id, announcement: sentence);
    } else {
      _clearPrice();
    }
  }

  Future<void> _book() async {
    if (!AuthorizationSession.can("load.create") ||
        !CustomerSession.hasCustomerOrg) return;
    setState(() {
      _booking = true;
      _actionError = null;
    });
    try {
      final phone = CustomerSession.userPhone?.trim() ?? "";
      final r = await api.post<Map<String, dynamic>>(
        "/shipments/book",
        data: {
          "anchorTripId": widget.laneId,
          "customerOrgName": CustomerSession.customerOrgName?.trim() ?? "",
          if (phone.isNotEmpty) "customerPhone": phone,
          "weightKg": _pricedWeightKg,
          "pickupAddress": _pickup.text,
          "dropAddress": _drop.text,
          "pickup": _placePayload(_pickup),
          "drop": _placePayload(_drop),
        },
      );
      final shipment = r.data?["shipment"];
      final pay = r.data?["payment"];
      final shipmentId =
          shipment is Map<String, dynamic> ? shipment["id"]?.toString() : null;
      final keyId = r.data?["razorpayKeyId"]?.toString();
      final orderId = pay is Map<String, dynamic>
          ? pay["razorpayOrderId"]?.toString()
          : null;
      final payStatus =
          pay is Map<String, dynamic> ? pay["status"]?.toString() : null;
      final amountPaise =
          pay is Map<String, dynamic> && pay["amountPaise"] is num
              ? (pay["amountPaise"] as num).toInt()
              : 0;

      if (shipmentId != null &&
          keyId != null &&
          orderId != null &&
          payStatus == "CREATED" &&
          amountPaise > 0 &&
          _checkout != null) {
        lastBookedShipmentId = shipmentId;
        _pendingShipmentIdForCheckout = shipmentId;
        _checkout!.open(
          keyId: keyId,
          orderId: orderId,
          amountPaise: amountPaise,
          shipmentId: shipmentId,
        );
      } else if (shipmentId != null && mounted) {
        final held = payStatus == "AUTHORIZED" || payStatus == "CAPTURED";
        _openBookedShipment(shipmentId,
            announcement: held
                ? null
                : "Booked, but payment did not start. This booking is not paid.");
      }
    } catch (error) {
      if (!mounted) return;
      final code = _apiErrorCode(error);
      if (code == "insufficient_capacity") {
        _showTooHeavy();
      } else if (code == "anchor_trip_not_open") {
        setState(() => _quote = null);
      } else {
        setState(() => _actionError = plainErrorSentence(
            error, "Could not book. Check your connection, then try again."));
      }
      // The room shown is from when the screen opened; after a room refusal, show what is left now.
      if (code == "insufficient_capacity" || code == "anchor_trip_not_open") {
        unawaited(_loadLane());
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lane = _lane;
    final laneOpen = lane != null && lane["status"]?.toString() == "OPEN";
    // On a desktop the price and Pay sit together in the side column (wb-book).
    final desktop = customerIsDesktop(context);
    return CustomerScaffold(
      title: "Book space",
      subtitle: "Check the price, then pay.",
      currentPath: "/customer/book",
      actionBar: desktop
          ? null
          : lane == null
              ? const SizedBox.shrink()
              : NvActionBar(child: _actionBar(laneOpen)),
      sideBuilder: desktop && lane != null
          ? (_) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (laneOpen && _pricePaise != null) ...[
                    _PriceCard(pricePaise: _pricePaise!),
                    const SizedBox(height: NvSpace.s4),
                  ],
                  _actionBar(laneOpen),
                ],
              )
          : null,
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
        children: [
          if (_loadingLane && lane == null)
            const NvListLoadingCard()
          else if (_laneFailed && lane == null)
            NvListError(
                title: "Could not load this lane.",
                help: "Check your connection, then try again.",
                onRetry: _loadLane)
          else if (lane != null) ...[
            _LaneSummary(lane: lane),
            const SizedBox(height: NvSpace.s4),
            if (!laneOpen)
              const NvMessage(
                  "This lane is no longer taking bookings. Choose another lane.",
                  tone: NvMessageTone.attention)
            else if (_quote == null)
              ..._fields(lane)
            else ...[
              SearchSummary(
                rows: [
                  ("Weight", formatKg(_pricedWeightKg!)),
                  ("Pickup", _pickup.text),
                  ("Drop", _drop.text),
                ],
                changeLabel: "Change weight, pickup or drop",
                onChange: _clearPrice,
              ),
              if (!desktop) ...[
                const SizedBox(height: NvSpace.s4),
                _PriceCard(pricePaise: _pricePaise!),
              ],
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _fields(Map<String, dynamic> lane) {
    final room = roomLeftKg(lane);
    final hasPoint = _pickup.point != null ||
        _drop.point != null ||
        (latLngFromTripField(lane, "origin") != null &&
            latLngFromTripField(lane, "destination") != null);
    return [
      NvField(
        label: "Weight",
        controller: _weightKg,
        unit: "kg",
        keyboardType: TextInputType.number,
        help: room == null ? null : "Up to ${formatKg(room)} on this lane.",
        errorText: _weightError,
      ),
      const SizedBox(height: NvSpace.s4),
      NvField(
          label: "Pickup",
          controller: _pickup.words,
          errorText: _pickup.error),
      const SizedBox(height: NvSpace.s4),
      NvField(label: "Drop", controller: _drop.words, errorText: _drop.error),
      if (_tooHeavy) ...[
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Choose another lane",
            kind: NvButtonKind.secondary,
            fullWidth: true,
            onPressed: () => context.go("/customer/trips")),
      ],
      if (hasPoint) ...[
        const SizedBox(height: NvSpace.s4),
        NvMap(
          map: bookShipmentRouteMap(
            shipmentPickup: _pickup.point,
            shipmentDrop: _drop.point,
            anchorOrigin: latLngFromTripField(lane, "origin"),
            anchorDestination: latLngFromTripField(lane, "destination"),
            onPickupMoved: (pin) => setState(() => _pickup.pinnedAt(pin)),
            onDropMoved: (pin) => setState(() => _drop.pinnedAt(pin)),
          ),
        ),
      ],
    ];
  }

  Widget _actionBar(bool laneOpen) {
    if (!laneOpen) {
      return NvButton(
          label: "Choose another lane",
          fullWidth: true,
          onPressed: () => context.go("/customer/trips"));
    }
    final price = _pricePaise;
    final button = price == null
        ? NvButton(
            label: "Get price",
            loadingLabel: "Getting price",
            loading: _pricing,
            fullWidth: true,
            onPressed: _getPrice)
        : NvButton(
            label: "Pay ${formatRupees(price)} and book",
            loading: _booking,
            fullWidth: true,
            onPressed: _confirmAndBook);
    final words = [
      if (_actionError != null)
        NvMessage(_actionError!, tone: NvMessageTone.problem),
      // The way out sits as close to Pay as Pay itself (decisions.md 6).
      if (price != null)
        Text.rich(
          TextSpan(children: [
            const TextSpan(
                text:
                    "Your payment is held when you book and collected after delivery. Booked shipments cannot be cancelled in the app; to change one, contact "),
            TextSpan(
                text: PendingCopy.changeOrCancelContact,
                style: NvText.body.copyWith(fontWeight: FontWeight.w700)),
            const TextSpan(text: "."),
          ]),
          style: NvText.body,
        ),
    ];
    // At very large text the words above the button scroll inside the bar, so the bar never
    // takes more than half the screen and the button never leaves it.
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height / 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (words.isNotEmpty) ...[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (index, line) in words.indexed) ...[
                      if (index > 0) const SizedBox(height: NvSpace.s3),
                      line,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: NvSpace.s3),
          ],
          button,
        ],
      ),
    );
  }
}

/// The lane being booked: route, carrier, dates and the room left.
class _LaneSummary extends StatelessWidget {
  const _LaneSummary({required this.lane});
  final Map<String, dynamic> lane;

  @override
  Widget build(BuildContext context) {
    final room = roomLeftKg(lane);
    final dates = laneDates(lane);
    final carrier = lane["carrierDisplayName"]?.toString() ?? "Carrier";
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(laneRoute(lane),
              style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
          const SizedBox(height: NvSpace.s1),
          Wrap(spacing: NvSpace.s1, children: [
            Text(dates == null ? carrier : "$carrier · $dates",
                style: NvText.caption),
            if (room != null)
              Text("Room left: ${roomLeftWords(room)}",
                  style: NvText.caption.copyWith(
                      fontWeight: FontWeight.w700, color: NvColors.ink)),
          ]),
        ],
      ),
    );
  }
}

/// The full price, shown before Pay with the promise that nothing is added.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.pricePaise});
  final num pricePaise;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.navy, width: 1.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NvSpace.s3,
              children: [
                const Text("Price", style: NvText.heading),
                Text(formatRupees(pricePaise), style: NvText.title),
              ],
            ),
            const SizedBox(height: NvSpace.s2),
            const Text("This is the full price. Nothing is added at payment.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s2),
            const Text(
                "Changing weight, pickup or drop clears this price, and you get a new one.",
                style: NvText.caption),
          ],
        ),
      );
}

/// The last look before money moves: the lane, the weight and the full price, and that the
/// booking cannot be cancelled in the app (sh-book-confirm).
class _ConfirmBookingSheet extends StatelessWidget {
  const _ConfirmBookingSheet(
      {required this.lane, required this.weightKg, required this.pricePaise});
  final Map<String, dynamic> lane;
  final int weightKg;
  final num pricePaise;

  @override
  Widget build(BuildContext context) {
    final price = formatRupees(pricePaise);
    final carrier = lane["carrierDisplayName"]?.toString() ?? "The carrier";
    final dates = laneDates(lane);
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: NvSpace.s2),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: NvSpace.s3,
            children: [
              Text(label,
                  style: strong
                      ? NvText.bodyStrong.copyWith(color: NvColors.navyInk)
                      : NvText.body.copyWith(color: NvColors.slate)),
              Text(value,
                  style: strong
                      ? NvText.bodyStrong.copyWith(color: NvColors.navyInk)
                      : NvText.body),
            ],
          ),
        );
    return NvSheet(
      title: "Pay $price to book?",
      primaryLabel: "Continue to payment",
      onPrimary: () => Navigator.of(context).pop(true),
      cancelLabel: "Go back",
      onCancel: () => Navigator.of(context).pop(false),
      footer: const Text(
          "Next, you choose how to pay on the payment provider's screen.",
          style: NvText.caption),
      choices: [
        row("Lane", laneRoute(lane)),
        row("Carrier", carrier),
        if (dates != null) row("Dates", dates),
        row("Weight", formatKg(weightKg)),
        row("You pay", price, strong: true),
        const SizedBox(height: NvSpace.s2),
        const Text("The payment is held now and collected after delivery.",
            style: NvText.body),
        Text("$carrier then accepts and names the truck.", style: NvText.body),
        const Text(
            "You cannot cancel in the app. To change the booking, contact ${PendingCopy.changeOrCancelContact}.",
            style: NvText.body),
      ],
    );
  }
}
