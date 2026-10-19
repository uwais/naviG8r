// Over 500 lines on purpose: one screen. Its state is most of it because getting a price, paying
// and booking share it, and the two cards after it are shown only here.

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
import "../ui/nv_message.dart";
import "../ui/pending_copy.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";
import "announce.dart";
import "shipment_screen.dart";

String _apiErrorCode(Object error) {
  final body = error is DioException ? error.response?.data : null;
  return body is Map ? body["error"]?.toString() ?? "" : "";
}

const _couldNotPrice =
    "Could not get a price. Check your connection, then try again.";

/// What the price depends on. A place without a name counts as not found, so nothing is booked
/// under an empty name.
typedef _PriceInputs = ({int? weightKg, LatLng? pickup, LatLng? drop});

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
      // tryParse takes "NaN" and "Infinity"; without a point on the globe the place is searched again.
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
  late final _pickupName =
      TextEditingController(text: widget.searchedPickup?.words ?? "");
  late final _dropName =
      TextEditingController(text: widget.searchedDrop?.words ?? "");
  late LatLng? _pickupPin = widget.searchedPickup?.point;
  late LatLng? _dropPin = widget.searchedDrop?.point;
  String? _weightError;
  bool _tooHeavy = false;
  Map<String, dynamic>? _lane;
  bool _loadingLane = true;
  bool _laneFailed = false;
  Map<String, dynamic>? _quote;
  int? _pricedWeightKg;
  bool _pricing = false;
  _PriceInputs? _inputsAskedFor;
  // Each price request takes the next number, so an answer that arrives after newer inputs is dropped.
  int _newestPriceRequest = 0;
  bool _booking = false;
  String? _actionError;
  CustomerCheckoutController? _checkout;
  String? _pendingShipmentIdForCheckout;

  num? get _pricePaise => _quote?["grossPaise"] as num?;

  _PriceInputs get _priceInputs => (
        weightKg: int.tryParse(_weightKg.text.trim()),
        pickup: _pickupName.text.trim().isEmpty ? null : _pickupPin,
        drop: _dropName.text.trim().isEmpty ? null : _dropPin,
      );

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
    // The listeners also hear cursor moves, and typing within a name; only a new input asks again.
    for (final input in [_weightKg, _pickupName, _dropName]) {
      input.addListener(_priceInputsChanged);
    }
    scheduleMicrotask(_loadLane);
  }

  @override
  void dispose() {
    _checkout?.dispose();
    _weightKg.dispose();
    _pickupName.dispose();
    _dropName.dispose();
    super.dispose();
  }

  Future<void> _loadLane({bool priceAfter = true}) async {
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
    // The room left decides whether the weight can be priced at all. After a "no room" refusal the
    // refusal stays on screen instead, until the shipper changes something.
    if (mounted && priceAfter) unawaited(_getPrice());
  }

  void _priceInputsChanged() {
    if (_priceInputs != _inputsAskedFor) unawaited(_getPrice());
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

  /// Prices the inputs as they are now, once the weight and both places are in. Any change of
  /// input comes here, and the old price goes at once, so Pay never shows a price for other inputs.
  Future<void> _getPrice() async {
    final inputs = _priceInputs;
    final request = ++_newestPriceRequest;
    _inputsAskedFor = inputs;
    final typedWeight = _weightKg.text.trim();
    final weightKg = inputs.weightKg;
    setState(() {
      _quote = null;
      _pricedWeightKg = null;
      _pricing = false;
      _tooHeavy = false;
      _actionError = null;
      _weightError =
          typedWeight.isNotEmpty && (weightKg == null || weightKg <= 0)
              ? "Enter a weight greater than 0 kg."
              : null;
    });
    final lane = _lane;
    if (lane == null ||
        lane["status"]?.toString() != "OPEN" ||
        weightKg == null ||
        weightKg <= 0 ||
        inputs.pickup == null ||
        inputs.drop == null) {
      return;
    }
    final room = roomLeftKg(lane);
    if (room != null && weightKg > room) {
      _showTooHeavy();
      return;
    }
    setState(() => _pricing = true);
    try {
      final r = await api.post<Map<String, dynamic>>("/shipments/quote",
          data: {
            "weightKg": weightKg,
            "pickup": _placePayload(_pickupName, inputs.pickup!),
            "drop": _placePayload(_dropName, inputs.drop!),
            "anchorTripId": widget.laneId,
          });
      if (!mounted || request != _newestPriceRequest) return;
      final quote = r.data?["quote"];
      final priced = quote is Map<String, dynamic> && quote["grossPaise"] is num;
      setState(() {
        if (priced) {
          _quote = quote;
          _pricedWeightKg = weightKg;
        } else {
          _actionError = _couldNotPrice;
        }
      });
      if (priced) {
        final spokenRupees = formatRupees(_pricePaise!).substring(1);
        announce(context,
            "Price for ${formatKg(weightKg)}: $spokenRupees rupees. This is the full price.");
      }
    } catch (error) {
      if (mounted && request == _newestPriceRequest) {
        setState(() => _actionError = plainErrorSentence(error, _couldNotPrice));
      }
    } finally {
      if (mounted && request == _newestPriceRequest) {
        setState(() => _pricing = false);
      }
    }
  }

  Map<String, dynamic> _placePayload(
          TextEditingController name, LatLng pin) =>
      {
        "lat": pin.latitude,
        "lng": pin.longitude,
        "label": name.text.trim(),
      };

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
    if (id != null) _openBookedShipment(id, announcement: sentence);
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
          "pickupAddress": _pickupName.text.trim(),
          "dropAddress": _dropName.text.trim(),
          "pickup": _placePayload(_pickupName, _pickupPin!),
          "drop": _placePayload(_dropName, _dropPin!),
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
        unawaited(_loadLane(priceAfter: code != "insufficient_capacity"));
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// What still has to be filled in before there is a price, or null when nothing is missing.
  String? _missingBeforePrice() {
    final inputs = _priceInputs;
    final weightMissing = inputs.weightKg == null || inputs.weightKg! <= 0;
    final places = switch ((inputs.pickup == null, inputs.drop == null)) {
      (true, true) => "pickup and drop",
      (true, false) => "pickup",
      (false, true) => "drop",
      (false, false) => null,
    };
    if (weightMissing && places != null) {
      return "To see the price, enter the weight and search for the $places.";
    }
    if (weightMissing) return "To see the price, enter the weight.";
    if (places != null) return "To see the price, search for the $places.";
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lane = _lane;
    final laneOpen = lane != null && lane["status"]?.toString() == "OPEN";
    // On a desktop the price and Pay sit together in the side column (wb-book).
    final desktop = customerIsDesktop(context);
    final priceCard = laneOpen && _pricePaise != null
        ? _PriceCard(
            pricePaise: _pricePaise!,
            carrier: lane["carrierDisplayName"]?.toString() ?? "The carrier")
        : null;
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
                  if (priceCard != null) ...[
                    priceCard,
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
            else ...[
              ..._fields(lane),
              if (!desktop && priceCard != null) ...[
                const SizedBox(height: NvSpace.s4),
                priceCard,
              ],
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _fields(Map<String, dynamic> lane) {
    final room = roomLeftKg(lane);
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
      // Each map shows once its place has a pin; a place from the match search arrives with one.
      LocationEndpointEditor(
        title: "Pickup",
        hint: "City or area",
        labelController: _pickupName,
        markerId: "book_pickup",
        markerHue: BitmapDescriptor.hueGreen,
        position: _pickupPin ?? pinNotPlacedYet,
        onPositionChanged: (pin) {
          setState(() => _pickupPin = pin);
          _priceInputsChanged();
        },
        showMap: _pickupPin != null,
        showApiKeyHint: false,
        findPlace: widget.findPlace,
      ),
      const SizedBox(height: NvSpace.s4),
      LocationEndpointEditor(
        title: "Drop",
        hint: "City or area",
        labelController: _dropName,
        markerId: "book_drop",
        markerHue: BitmapDescriptor.hueRed,
        position: _dropPin ?? pinNotPlacedYet,
        onPositionChanged: (pin) {
          setState(() => _dropPin = pin);
          _priceInputsChanged();
        },
        showMap: _dropPin != null,
        showApiKeyHint: false,
        findPlace: widget.findPlace,
      ),
      // Last in the list: a row added above the place boxes would rebuild them and lose their search state.
      if (_tooHeavy) ...[
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Choose another lane",
            kind: NvButtonKind.secondary,
            fullWidth: true,
            onPressed: () => context.go("/customer/trips")),
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
    final missing = _missingBeforePrice();
    final NvButton button;
    if (price != null) {
      button = NvButton(
          label: "Pay ${formatRupees(price)}",
          loading: _booking,
          fullWidth: true,
          onPressed: _book);
    } else if (_pricing) {
      button = const NvButton(
          label: "Pay",
          loadingLabel: "Getting the price",
          loading: true,
          fullWidth: true,
          onPressed: null);
    } else if (_actionError != null && missing == null && !_tooHeavy) {
      button = NvButton(
          label: "Try again", fullWidth: true, onPressed: _getPrice);
    } else {
      button = NvButton(
          label: "Pay",
          fullWidth: true,
          onPressed: null,
          disabledReason: missing ?? "Enter a lower weight to see the price.");
    }
    final words = [
      if (_actionError != null)
        NvMessage(_actionError!, tone: NvMessageTone.problem),
      // The full price and the way out sit as close to Pay as Pay itself (decisions.md 6).
      if (price != null) ...[
        const Text("This is the full price. Nothing is added at payment.",
            style: NvText.bodyStrong),
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
      ],
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
            Text(dates == null ? carrier : "$carrier · Leaves $dates",
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

/// The price and what happens after Pay. With the lane above and the words beside Pay, it holds
/// everything the confirm sheet used to show before money moved (sh-book-price).
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.pricePaise, required this.carrier});
  final num pricePaise;
  final String carrier;

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
            Text("After you pay, $carrier accepts and names the truck.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s2),
            const Text(
                "Pay opens the payment provider's screen, where you choose how to pay.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s2),
            const Text("Changing weight, pickup or drop gets a new price.",
                style: NvText.caption),
          ],
        ),
      );
}
