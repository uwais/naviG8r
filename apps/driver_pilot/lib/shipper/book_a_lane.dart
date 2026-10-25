// Book this trip, one screen: getting a price, paying and booking share its state. The parts that stand
// alone sit beside it: the trip summary (book_lane_summary.dart), the pins check (book_pins_check.dart),
// the far-pin rule (book_far_pin.dart) and the price card (book_price_card.dart).

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
import "book_far_pin.dart";
import "book_lane_summary.dart";
import "book_pins_check.dart";
import "book_price_card.dart";
import "shipment_screen.dart";
import "trip_route.dart";

Object? _apiErrorBody(Object error) =>
    error is DioException ? error.response?.data : null;

String _apiErrorCode(Object error) {
  final body = _apiErrorBody(error);
  return body is Map ? body["error"]?.toString() ?? "" : "";
}

const _couldNotPrice =
    "Could not get a price. Check your connection, then try again.";

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
typedef SearchedPlace = ({String words, LatLng? point, PinAddress? pinAddress});

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({
    required this.laneId,
    this.searchedWeightKg,
    this.searchedPickup,
    this.searchedDrop,
    this.findPlace,
    this.namePin = GoogleGeocodingService.reverseAddress,
    this.mapsApiKey,
    super.key,
  });

  /// From the Book link a lane card builds: the lane and the match search's weight. The search's places
  /// come as the router's [extra], in memory only; a reload has none and opens the empty boxes.
  factory CustomerBookShipmentScreen.fromQuery(Map<String, String> query,
      {Object? extra,
      PlaceFinder? findPlace,
      PinNamer namePin = GoogleGeocodingService.reverseAddress,
      String? mapsApiKey}) {
    final places = extra is SearchedPlaces ? extra : null;
    final weightKg = int.tryParse(query["weightKg"] ?? "");
    return CustomerBookShipmentScreen(
      laneId: query["anchorTripId"] ?? "",
      searchedWeightKg: weightKg != null && weightKg > 0 ? weightKg : null,
      searchedPickup: places?.pickup,
      searchedDrop: places?.drop,
      findPlace: findPlace,
      namePin: namePin,
      mapsApiKey: mapsApiKey,
    );
  }

  final String laneId;
  final int? searchedWeightKg;
  final SearchedPlace? searchedPickup;
  final SearchedPlace? searchedDrop;

  /// Null searches Google, preferring places around the trip's towns.
  final PlaceFinder? findPlace;
  final PinNamer namePin;

  /// A key for Book's own Google search in place of the build's, for tests. Null uses the build's.
  final String? mapsApiKey;

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
  late PinAddress? _pickupPinAddress = widget.searchedPickup?.pinAddress;
  late PinAddress? _dropPinAddress = widget.searchedDrop?.pinAddress;
  bool _namingPickupPin = false;
  bool _namingDropPin = false;
  bool _searchingPickup = false;
  bool _searchingDrop = false;
  String? _weightError;
  bool _tooHeavy = false;
  // The help under Book and pay after the server refused the pins, until the shipper changes something.
  String? _pinsRefusedHelp;
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

  TripEnds? get _tripEnds => _lane == null ? null : tripEnds(_lane!);
  String get _startTown => _lane?["originCity"]?.toString() ?? "the start town";
  String get _endTown => _lane?["destCity"]?.toString() ?? "the end town";
  // The pins the price uses, so an emptied address box asks for a search instead.
  double? get _pickupFarKm => farPinKm(_priceInputs.pickup, _tripEnds?.start);
  double? get _dropFarKm => farPinKm(_priceInputs.drop, _tripEnds?.end);
  String? get _farPinsHelp =>
      farPinsHelp(pickupFar: _pickupFarKm != null, dropFar: _dropFarKm != null);

  PlaceFinder get _findPlace =>
      widget.findPlace ??
      ((place) => GoogleGeocodingService.forwardAddress(place,
          apiKey: widget.mapsApiKey,
          countryOrStateNotFound: true,
          near: _tripEnds == null ? null : areaAround(_tripEnds!)));

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
    // Capacity remaining and the pins check follow every keystroke, even one that leaves the price
    // inputs the same.
    for (final input in [_weightKg, _pickupName, _dropName]) {
      input.addListener(() => setState(() {}));
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
      _pinsRefusedHelp = null;
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
    // A pin far from the route is in the wrong place, so there is no price to ask for until it moves.
    if (_farPinsHelp != null) return;
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
            "Price for ${formatKg(weightKg)}: $spokenRupees rupees. Full price. Nothing is added at payment.");
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
    // The server refuses a payment for a trip that has already left, or a booking that expired unpaid, in its own
    // sentence.
    String? refusal;
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
      } catch (error) {
        final code = _apiErrorCode(error);
        if (code == "trip_already_started" || code == "booking_expired") {
          refusal = plainErrorSentence(error);
        }
      }
    }
    if (!mounted) return;
    if (refusal != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(refusal)));
    }
    if (id != null) {
      _openBookedShipment(id,
          announcement: confirmed
              ? null
              : refusal ??
                  "Booked. We could not confirm the payment yet. The shipment shows whether it went through.");
    } else {
      setState(() => _booking = false);
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
    if (id != null) {
      _openBookedShipment(id, announcement: sentence);
    } else {
      setState(() => _booking = false);
    }
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
    // Once checkout opens, the screen stays busy until checkout ends and the shipment opens: a tap
    // while the payment is confirmed would book and charge a second shipment.
    var checkoutOpened = false;
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
        checkoutOpened = true;
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
      } else if (code == "phase_a_not_eligible") {
        final refusal = farPinsRefusal(_apiErrorBody(error),
            startTown: _startTown, endTown: _endTown);
        setState(() {
          _quote = null;
          _actionError = refusal.sentence;
          _pinsRefusedHelp = refusal.help;
        });
      } else {
        setState(() => _actionError = plainErrorSentence(
            error, "Could not book. Check your connection, then try again."));
      }
      // The room shown is from when the screen opened; after a room refusal, show what is left now. After a
      // pins refusal the trip's town pins may have moved, so its rule here follows.
      if (const ["insufficient_capacity", "anchor_trip_not_open", "phase_a_not_eligible"]
          .contains(code)) {
        unawaited(_loadLane(priceAfter: code == "anchor_trip_not_open"));
      }
    } finally {
      if (mounted && !checkoutOpened) setState(() => _booking = false);
    }
  }

  /// What still has to be filled in before there is a price, or null when nothing is missing.
  String? _missingBeforePrice() {
    // A search still out would move a pin after Book and pay; wait for it.
    if (_searchingPickup || _searchingDrop) return "Searching for the place…";
    // A dragged pin is priced at once but named later; booking before then sends the old name.
    if (_namingPickupPin || _namingDropPin) return "Updating address from pin…";
    if (_farPinsHelp ?? _pinsRefusedHelp case final help?) return help;
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
        ? BookPriceCard(
            pricePaise: _pricePaise!,
            carrier: lane["carrierDisplayName"]?.toString() ?? "The carrier")
        : null;
    return CustomerScaffold(
      title: "Book this trip",
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
            // One Column, so the rule line coming or going never moves the place boxes in the list.
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              BookLaneSummary(
                  lane: lane, typedWeightKg: int.tryParse(_weightKg.text.trim())),
              if (_tripEnds != null) ...[
                const SizedBox(height: NvSpace.s2),
                Text(farPinRule(startTown: _startTown, endTown: _endTown),
                    style: NvText.caption),
              ],
            ]),
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
              if (_placesToCheck case final places?) ...[
                const SizedBox(height: NvSpace.s4),
                // The price card comes and goes above it with each price; the key keeps its map instead of
                // building a new one each time.
                BookPinsCheck(
                    key: const ValueKey("book-pins-check"),
                    pickup: places.pickup,
                    drop: places.drop),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// Both places for the pins check, once both are in: on one map last in the list, and as a Pin line
  /// each just above Book and pay (owner, 21 Oct 2026). The pin decides the place, so the shipper checks it.
  ({BookPlace pickup, BookPlace drop})? get _placesToCheck {
    final (pickup: pickupPin, drop: dropPin, weightKg: _) = _priceInputs;
    if (pickupPin == null || dropPin == null) return null;
    return (
      pickup: (words: _pickupName.text.trim(), pin: pickupPin, pinAddress: _pickupPinAddress, naming: _namingPickupPin),
      drop: (words: _dropName.text.trim(), pin: dropPin, pinAddress: _dropPinAddress, naming: _namingDropPin),
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
      withFarPinLine(farKm: _pickupFarKm, town: _startTown, LocationEndpointEditor(
        title: "Pickup",
        hint: "Address for the driver",
        example: "House or plot, street, area",
        labelController: _pickupName,
        markerId: "book_pickup",
        markerHue: BitmapDescriptor.hueGreen,
        position: _pickupPin ?? pinNotPlacedYet,
        onPositionChanged: (pin) {
          setState(() => _pickupPin = pin);
          _priceInputsChanged();
        },
        onPinNaming: (naming) => setState(() => _namingPickupPin = naming),
        onSearching: (searching) => setState(() => _searchingPickup = searching),
        pinAddress: _pickupPinAddress,
        onPinAddress: (address) =>
            setState(() => _pickupPinAddress = address),
        readOnly: _booking,
        showMap: _pickupPin != null,
        showApiKeyHint: false,
        findPlace: _findPlace,
        namePin: widget.namePin,
        keepsFullAddress: true,
        // A drag naming or a search still out when the box scrolls off screen would be lost.
        staysAliveOffScreen: true,
      )),
      const SizedBox(height: NvSpace.s4),
      withFarPinLine(farKm: _dropFarKm, town: _endTown, LocationEndpointEditor(
        title: "Drop",
        hint: "Address for the driver",
        example: "House or plot, street, area",
        labelController: _dropName,
        markerId: "book_drop",
        markerHue: BitmapDescriptor.hueRed,
        position: _dropPin ?? pinNotPlacedYet,
        onPositionChanged: (pin) {
          setState(() => _dropPin = pin);
          _priceInputsChanged();
        },
        onPinNaming: (naming) => setState(() => _namingDropPin = naming),
        onSearching: (searching) => setState(() => _searchingDrop = searching),
        pinAddress: _dropPinAddress,
        onPinAddress: (address) =>
            setState(() => _dropPinAddress = address),
        readOnly: _booking,
        showMap: _dropPin != null,
        showApiKeyHint: false,
        findPlace: _findPlace,
        namePin: widget.namePin,
        keepsFullAddress: true,
        // A drag naming or a search still out when the box scrolls off screen would be lost.
        staysAliveOffScreen: true,
      )),
      // Last in the list: a row added above the place boxes would rebuild them and lose their search state.
      if (_tooHeavy || _farPinsHelp != null || _pinsRefusedHelp != null) ...[
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
      // The way out and the full price sit beside the button (decisions.md 6): on a phone the price card
      // scrolls away, the button does not. One tap books, so the cancel line is first: at very large text
      // the top of this scroll is the part that shows. A failed payment is said on the shipment screen when
      // it happens (owner, 22 Oct 2026).
      if (price != null) ...[
        const Text("To cancel, contact ${PendingCopy.changeOrCancelContact}.",
            style: NvText.body),
        const Text("Full price. Nothing is added at payment.",
            style: NvText.bodyStrong),
        // The server's UNPAID_BOOKING_EXPIRY_MS; it closes the booking only after a further grace.
        const Text("Pay within 30 minutes, or this booking closes.",
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
          // Owner, 21 Oct 2026: "Pin lines just above Book and pay", outside the scroll so they always show.
          if (_placesToCheck case final places?) ...[
            BookPinLines(pickup: places.pickup, drop: places.drop),
            const SizedBox(height: NvSpace.s2),
          ],
          button,
        ],
      ),
    );
  }
}
