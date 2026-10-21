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

const _priceChangesNote =
    "If you change the weight, pickup or drop, the price changes.";

/// What the price depends on. A place without a name counts as not found, so nothing is booked
/// under an empty name.
typedef _PriceInputs = ({int? weightKg, LatLng? pickup, LatLng? drop});

/// The match search's places, handed to Book as the router's extra and never put in the link: they are
/// street addresses. A class, not a map: go_router 14 writes an extra it can turn into JSON into the
/// browser's history, and drops one it cannot, so these never reach the history.
class SearchedPlaces {
  const SearchedPlaces({required this.pickup, required this.drop});
  final SearchedPlace pickup;
  final SearchedPlace drop;
}

/// A place as the match search left it: the typed words, the pin, and Google's address for the pin.
typedef SearchedPlace = ({String words, LatLng? point, String? pinAddress});

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({
    required this.laneId,
    this.searchedWeightKg,
    this.searchedPickup,
    this.searchedDrop,
    this.findPlace = GoogleGeocodingService.forwardAddress,
    this.namePin = GoogleGeocodingService.reverseAddress,
    super.key,
  });

  /// From the Book link a lane card builds: the lane and the match search's weight. The search's places
  /// come as the router's [extra], in memory only; a reload has none and opens the empty boxes.
  factory CustomerBookShipmentScreen.fromQuery(Map<String, String> query,
      {Object? extra,
      PlaceFinder findPlace = GoogleGeocodingService.forwardAddress,
      PinNamer namePin = GoogleGeocodingService.reverseAddress}) {
    final places = extra is SearchedPlaces ? extra : null;
    final weightKg = int.tryParse(query["weightKg"] ?? "");
    return CustomerBookShipmentScreen(
      laneId: query["anchorTripId"] ?? "",
      searchedWeightKg: weightKg != null && weightKg > 0 ? weightKg : null,
      searchedPickup: places?.pickup,
      searchedDrop: places?.drop,
      findPlace: findPlace,
      namePin: namePin,
    );
  }

  final String laneId;
  final int? searchedWeightKg;
  final SearchedPlace? searchedPickup;
  final SearchedPlace? searchedDrop;
  final PlaceFinder findPlace;
  final PinNamer namePin;

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
  late String? _pickupPinAddress = widget.searchedPickup?.pinAddress;
  late String? _dropPinAddress = widget.searchedDrop?.pinAddress;
  bool _namingPickupPin = false;
  bool _namingDropPin = false;
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
    // Capacity remaining follows every keystroke, even one that leaves the price inputs the same.
    _weightKg.addListener(() => setState(() {}));
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
        "This trip does not have enough capacity for that weight. Enter less weight, or choose another trip.";
    setState(() {
      _quote = null;
      _weightError = sentence;
      _tooHeavy = true;
    });
    announce(context, sentence, assertiveness: Assertiveness.assertive);
  }

  /// Prices the inputs as they are now, once the weight and both places are in. Any change of
  /// input comes here, and the old price goes at once, so Book and pay never shows a price for
  /// other inputs.
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
              : "Booked. We could not confirm the payment yet. The shipment shows whether it went through.");
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

  // The shipment already exists, so the shipper goes to it: Book and pay again would book a second one.
  void _onCheckoutError(String message) {
    final id = _pendingShipmentIdForCheckout;
    _pendingShipmentIdForCheckout = null;
    if (!mounted) return;
    const sentence = "Payment did not go through. This shipment is not paid.";
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(sentence)));
    if (id != null) _openBookedShipment(id, announcement: sentence);
  }

  Future<void> _book() async {
    // A second tap before the button redraws as loading would book a second shipment.
    if (_booking) return;
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
                : "Booked, but payment did not start. This shipment is not paid.");
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
    // A dragged pin is priced at once but named later; booking before then sends the old name.
    if (_namingPickupPin || _namingDropPin) return "Updating address from pin…";
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
    // On a desktop the price and Book and pay sit together in the side column (wb-book).
    final desktop = customerIsDesktop(context);
    final priceCard = laneOpen && _pricePaise != null
        ? _PriceCard(
            pricePaise: _pricePaise!,
            carrier: lane["carrierDisplayName"]?.toString() ?? "The carrier",
            // On a desktop the note sits under the fields it is about, so Pay stays on a 900-high screen.
            withChangesNote: !desktop)
        : null;
    return CustomerScaffold(
      title: "Book this trip",
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
                title: "Could not load this trip.",
                help: "Check your connection, then try again.",
                onRetry: _loadLane)
          else if (lane != null) ...[
            _LaneSummary(
                lane: lane, typedWeightKg: int.tryParse(_weightKg.text.trim())),
            const SizedBox(height: NvSpace.s4),
            if (!laneOpen)
              const NvMessage(
                  "This trip is no longer taking bookings. Choose another trip.",
                  tone: NvMessageTone.attention)
            else ...[
              ..._fields(lane),
              if (!desktop && priceCard != null) ...[
                const SizedBox(height: NvSpace.s4),
                priceCard,
              ],
              if (desktop && priceCard != null) ...[
                const SizedBox(height: NvSpace.s3),
                const Text(_priceChangesNote, style: NvText.caption),
              ],
              if (_pinsCheck() case final pinsCheck?) ...[
                const SizedBox(height: NvSpace.s4),
                pinsCheck,
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// Both pins on one map once both places are in, last above Book and pay (owner, 21 Oct 2026):
  /// the pin decides the place, so the shipper checks it there.
  Widget? _pinsCheck() {
    final (pickup: pickupPin, drop: dropPin, weightKg: _) = _priceInputs;
    if (pickupPin == null || dropPin == null) return null;
    return _PinsCheck(
      pickup: (
          words: _pickupName.text.trim(),
          pin: pickupPin,
          pinAddress: _pickupPinAddress,
          naming: _namingPickupPin),
      drop: (
          words: _dropName.text.trim(),
          pin: dropPin,
          pinAddress: _dropPinAddress,
          naming: _namingDropPin),
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
        help: room == null ? null : "Up to ${formatKg(room)} on this trip.",
        errorText: _weightError,
        readOnly: _booking,
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
        onPinNaming: (naming) => setState(() => _namingPickupPin = naming),
        pinAddress: _pickupPinAddress,
        onPinAddress: (address) =>
            setState(() => _pickupPinAddress = address),
        readOnly: _booking,
        showMap: _pickupPin != null,
        showApiKeyHint: false,
        findPlace: widget.findPlace,
        namePin: widget.namePin,
        keepsFullAddress: true,
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
        onPinNaming: (naming) => setState(() => _namingDropPin = naming),
        pinAddress: _dropPinAddress,
        onPinAddress: (address) =>
            setState(() => _dropPinAddress = address),
        readOnly: _booking,
        showMap: _dropPin != null,
        showApiKeyHint: false,
        findPlace: widget.findPlace,
        namePin: widget.namePin,
        keepsFullAddress: true,
      ),
      // Last in the list: a row added above the place boxes would rebuild them and lose their search state.
      if (_tooHeavy) ...[
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Choose another trip",
            kind: NvButtonKind.secondary,
            fullWidth: true,
            onPressed: () => context.go("/customer/trips")),
      ],
    ];
  }

  Widget _actionBar(bool laneOpen) {
    if (!laneOpen) {
      return NvButton(
          label: "Choose another trip",
          fullWidth: true,
          onPressed: () => context.go("/customer/trips"));
    }
    final price = _pricePaise;
    final missing = _missingBeforePrice();
    final NvButton button;
    if (price != null) {
      button = NvButton(
          label: "Book and pay ${formatRupees(price)}",
          loading: _booking,
          fullWidth: true,
          onPressed: missing == null ? _book : null,
          disabledReason: missing);
    } else if (_pricing) {
      button = const NvButton(
          label: "Book and pay",
          loadingLabel: "Getting the price",
          loading: true,
          fullWidth: true,
          onPressed: null);
    } else if (_actionError != null && missing == null && !_tooHeavy) {
      button = NvButton(
          label: "Try again", fullWidth: true, onPressed: _getPrice);
    } else {
      button = NvButton(
          label: "Book and pay",
          fullWidth: true,
          onPressed: null,
          disabledReason: missing ?? "Enter less weight to see the price.");
    }
    final words = [
      if (_actionError != null)
        NvMessage(_actionError!, tone: NvMessageTone.problem),
      // The full price and the way out sit as close to the button as the button itself
      // (decisions.md 6); one tap books, so the cancel line is the one directly above it.
      if (price != null) ...[
        const Text("This is the full price. Nothing is added at payment.",
            style: NvText.bodyStrong),
        // Owner, 21 Oct 2026: a failed payment is said on screen; the booking stays.
        const Text(
            "If you close the payment screen or the payment does not go through, the shipment stays booked and unpaid. To pay or cancel it, contact ${PendingCopy.changeOrCancelContact}.",
            style: NvText.caption),
        const Text(
            "Booking keeps this capacity for you. To cancel, contact ${PendingCopy.changeOrCancelContact}.",
            style: NvText.body),
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

/// The lane being booked: route, carrier, dates and the capacity remaining once the weight typed so
/// far is taken off. An empty or unreadable weight takes nothing off; it never shows below 0.
class _LaneSummary extends StatelessWidget {
  const _LaneSummary({required this.lane, required this.typedWeightKg});
  final Map<String, dynamic> lane;
  final int? typedWeightKg;

  @override
  Widget build(BuildContext context) {
    final room = roomLeftKg(lane);
    final typed = typedWeightKg;
    final remaining = room == null || typed == null || typed <= 0
        ? room
        : (room - typed < 0 ? 0 : room - typed);
    final tooHeavyByKg =
        room != null && typed != null && typed > room ? typed - room : null;
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
            if (remaining != null)
              Text(
                  tooHeavyByKg != null
                      ? "${formatKg(tooHeavyByKg)} more than the capacity remaining"
                      // A weight that fits exactly leaves 0 kg, a number like the rest, not "None".
                      : "Capacity remaining: ${formatKg(remaining)}",
                  style: NvText.caption.copyWith(
                      fontWeight: FontWeight.w700, color: NvColors.ink)),
          ]),
        ],
      ),
    );
  }
}

/// The price and what happens after Book and pay. With the lane above and the words beside the
/// button, it holds everything the confirm sheet used to show before money moved (sh-book-price).
class _PriceCard extends StatelessWidget {
  const _PriceCard(
      {required this.pricePaise,
      required this.carrier,
      required this.withChangesNote});
  final num pricePaise;
  final String carrier;
  final bool withChangesNote;

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
                "Book and pay opens our payment partner's screen. There you choose how to pay.",
                style: NvText.body),
            if (withChangesNote) ...[
              const SizedBox(height: NvSpace.s2),
              const Text(_priceChangesNote, style: NvText.caption),
            ],
          ],
        ),
      );
}

/// Both pins on one map, each with the words typed for it and Google's address for the pin, so the
/// shipper checks by eye before Book and pay: the pin decides the place and the price, the words are
/// what the driver reads.
class _PinsCheck extends StatelessWidget {
  const _PinsCheck({required this.pickup, required this.drop});
  final _PinToCheck pickup;
  final _PinToCheck drop;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Check the pins before you pay", style: NvText.heading),
            const SizedBox(height: NvSpace.s3),
            // The same pin colours as the place boxes: pickup green, drop red.
            routePreviewMap(a: pickup.pin, b: drop.pin),
            for (final (title, place) in [("Pickup", pickup), ("Drop", drop)]) ...[
              const SizedBox(height: NvSpace.s3),
              Text("$title: ${place.words}", style: NvText.bodyStrong),
              Text(
                  place.naming
                      ? "Updating address from pin…"
                      : pinAddressLine(place.pinAddress),
                  style: NvText.caption),
            ],
          ],
        ),
      );
}

typedef _PinToCheck = ({
  String words,
  LatLng pin,
  String? pinAddress,
  bool naming
});
