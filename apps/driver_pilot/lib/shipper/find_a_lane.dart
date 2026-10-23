// Just over 500 lines on purpose: one screen, Find a lane, with its two views sharing the lane
// cards. The two place boxes in the Match form are most of the growth; splitting the views apart
// would put the shared cards in a third file for no reader's gain.
import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../google_geocoding.dart";
import "../customer_layout.dart";
import "../location_editor.dart";
import "../pilot_api.dart";
import "../ui/format.dart";
import "../ui/nv_button.dart";
import "../ui/nv_field.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_message.dart";
import "../ui/nv_status_label.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";
import "search_summary.dart";
import "announce.dart";
import "book_a_lane.dart";

NvStatusLabel _laneStatusLabel(String status) {
  final word = tripStatusLabel(status);
  return switch (status) {
    "OPEN" => NvStatusLabel(word, tone: NvStatusTone.good),
    "IN_PROGRESS" => NvStatusLabel(word, tone: NvStatusTone.info),
    _ => NvStatusLabel(word, tone: NvStatusTone.ended),
  };
}

/// One lane on a list; the whole card opens Book for it.
Widget _laneCard(Map<String, dynamic> lane, {required VoidCallback onOpen}) {
  final room = roomLeftKg(lane);
  final dates = laneDates(lane);
  final carrier = lane["carrierDisplayName"]?.toString() ?? "Carrier";
  return Padding(
    padding: const EdgeInsets.only(top: NvSpace.s3),
    child: NvListCard(
      title: laneRoute(lane),
      status: _laneStatusLabel(lane["status"]?.toString() ?? ""),
      subtitle:
          "$carrier · ${vehicleClassLabel(lane["vehicleClass"]?.toString())}",
      facts: [
        if (dates != null) NvFact("Leaves", dates),
        if (room != null) NvFact("Capacity remaining", roomLeftWords(room)),
      ],
      onOpen: onOpen,
    ),
  );
}

/// Lane cards in a grid on a desktop (wb-lanes), one under another on a phone.
List<Widget> _laneCards(BuildContext context, List<Map<String, dynamic>> lanes,
    {required void Function(Map<String, dynamic> lane) onOpen}) {
  final cards = [
    for (final lane in lanes) _laneCard(lane, onOpen: () => onOpen(lane))
  ];
  if (!customerIsDesktop(context)) return cards;
  return [
    LayoutBuilder(builder: (context, constraints) {
      const gap = NvSpace.s4;
      final fit = ((constraints.maxWidth + gap) /
              (CustomerBreakpoints.laneCardMin + gap))
          .floor();
      final columns = fit < 1 ? 1 : fit;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, children: [
        for (final card in cards) SizedBox(width: width, child: card),
      ]);
    }),
  ];
}

String _laneCount(int count) => count == 1 ? "1 trip" : "$count trips";

enum _LaneView { browse, match }

class CustomerTripsScreen extends StatefulWidget {
  const CustomerTripsScreen(
      {this.startWithMatch = false,
      this.findPlace = GoogleGeocodingService.forwardAddress,
      this.namePin = GoogleGeocodingService.reverseAddress,
      super.key});

  final bool startWithMatch;
  final PlaceFinder findPlace;
  final PinNamer namePin;

  @override
  State<CustomerTripsScreen> createState() => _CustomerTripsScreenState();
}

class _CustomerTripsScreenState extends State<CustomerTripsScreen> {
  late _LaneView _view =
      widget.startWithMatch ? _LaneView.match : _LaneView.browse;

  @override
  Widget build(BuildContext context) {
    final viewSwitch = SegmentedButton<_LaneView>(
      segments: const [
        ButtonSegment(value: _LaneView.browse, label: Text("All trips")),
        ButtonSegment(value: _LaneView.match, label: Text("Search by route")),
      ],
      selected: {_view},
      showSelectedIcon: false,
      onSelectionChanged: (chosen) => setState(() => _view = chosen.first),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, NvSpace.targetMin)),
        textStyle: const WidgetStatePropertyAll(NvText.bodyStrong),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NvColors.card
                : NvColors.sunken),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NvColors.navyInk
                : NvColors.slate),
        side: const WidgetStatePropertyAll(
            BorderSide(color: NvColors.controlBorder)),
      ),
    );
    return CustomerScaffold(
      title: "Book a trip",
      subtitle: "Pick a trip going your way.",
      currentPath: "/customer/trips",
      bodyBuilder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NvSpace.s2),
          // On a desktop the switch keeps to the width of the Match search column.
          if (customerIsDesktop(context))
            Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: CustomerBreakpoints.sideColumn, child: viewSwitch))
          else
            viewSwitch,
          Expanded(
            // Both views stay alive, so a match search survives a look at Browse. Offstage, unlike
            // IndexedStack, also hides the other view from screen readers and finders.
            child: Stack(fit: StackFit.expand, children: [
              Offstage(
                  offstage: _view != _LaneView.browse,
                  child: const _CustomerBrowseTripsTab()),
              Offstage(
                offstage: _view != _LaneView.match,
                child: _CustomerMatchTripsTab(
                  findPlace: widget.findPlace,
                  namePin: widget.namePin,
                  onBrowseAll: () => setState(() => _view = _LaneView.browse),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CustomerBrowseTripsTab extends StatefulWidget {
  const _CustomerBrowseTripsTab();

  @override
  State<_CustomerBrowseTripsTab> createState() =>
      _CustomerBrowseTripsTabState();
}

class _CustomerBrowseTripsTabState extends State<_CustomerBrowseTripsTab> {
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _lanes = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    announce(context, "Loading trips.");
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips");
      final raw = r.data?["trips"];
      if (!mounted) return;
      final lanes = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      setState(() => _lanes = lanes);
      announce(
          context,
          lanes.isEmpty
              ? "No trips are open right now."
              : _laneCount(lanes.length));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
        children: [
          const Text(
              "All trips, open or not. Not sorted by distance. To see the closest to your route first, use Search by route.",
              style: NvText.caption),
          if (_loading) ...[
            const SizedBox(height: NvSpace.s3),
            const NvListLoadingCard(),
            const SizedBox(height: NvSpace.s3),
            const NvListLoadingCard(),
          ] else if (_failed) ...[
            const SizedBox(height: NvSpace.s3),
            NvListError(
                title: "Could not load trips.",
                help: "Check your connection, then try again.",
                onRetry: _load),
          ] else if (_lanes.isEmpty) ...[
            const SizedBox(height: NvSpace.s3),
            const NvListEmpty(
                title: "No trips are open right now.",
                help: "New trips show here when carriers add them."),
          ] else
            ..._laneCards(context, _lanes,
                onOpen: (lane) => context.go(Uri(
                        path: "/customer/book",
                        queryParameters: {
                          "anchorTripId": lane["id"]?.toString() ?? ""
                        }).toString())),
        ],
      ),
    );
  }
}

class _CustomerMatchTripsTab extends StatefulWidget {
  const _CustomerMatchTripsTab(
      {required this.findPlace,
      required this.namePin,
      required this.onBrowseAll});
  final PlaceFinder findPlace;
  final PinNamer namePin;
  final VoidCallback onBrowseAll;

  @override
  State<_CustomerMatchTripsTab> createState() => _CustomerMatchTripsTabState();
}

class _CustomerMatchTripsTabState extends State<_CustomerMatchTripsTab> {
  final _pickupName = TextEditingController();
  final _dropName = TextEditingController();
  LatLng? _pickupPin;
  LatLng? _dropPin;
  PinAddress? _pickupPinAddress;
  PinAddress? _dropPinAddress;
  bool _namingPickupPin = false;
  bool _namingDropPin = false;
  bool _searchingPickup = false;
  bool _searchingDrop = false;
  String? _pickupError;
  String? _dropError;
  final _weightKg = TextEditingController();
  String? _weightError;
  bool _editing = true;
  bool _searching = false;
  bool _failed = false;
  List<Map<String, dynamic>> _lanes = [];
  // The search these results answer; a lane card carries it to Book, not whatever the fields say now.
  int? _searchedWeightKg;
  SearchedPlace? _searchedPickup;
  SearchedPlace? _searchedDrop;

  @override
  void dispose() {
    _pickupName.dispose();
    _dropName.dispose();
    _weightKg.dispose();
    super.dispose();
  }

  /// Why a place cannot be searched from yet, or null when it has a name and a pin.
  static String? _placeMissing(
      String which, TextEditingController name, LatLng? pin) {
    if (name.text.trim().isEmpty) return "Enter the $which place.";
    if (pin == null) return "Search for the $which place.";
    return null;
  }

  /// Why Find trips cannot run yet, or null: a place search still out (it would move a pin after the
  /// trips were found), or a dragged pin still being named (a lane card would carry the old name, or
  /// no name, to Book).
  String? get _searchBlockedBy => _searchingPickup || _searchingDrop
      ? "Searching for the place…"
      : _namingPickupPin || _namingDropPin
          ? "Updating address from pin…"
          : null;

  Future<void> _search() async {
    // Try again stays tappable, so it checks too.
    if (_searchBlockedBy != null) return;
    final weightKg = int.tryParse(_weightKg.text.trim()) ?? 0;
    final pickupPoint = _pickupPin;
    final dropPoint = _dropPin;
    // A lane card carries the places as they were sent to Book.
    final pickupPlace = (
        words: _pickupName.text.trim(),
        point: pickupPoint,
        pinAddress: _pickupPinAddress);
    final dropPlace = (
        words: _dropName.text.trim(),
        point: dropPoint,
        pinAddress: _dropPinAddress);
    setState(() {
      _weightError =
          weightKg <= 0 ? "Enter a weight greater than 0 kg." : null;
      _pickupError = _placeMissing("pickup", _pickupName, pickupPoint);
      _dropError = _placeMissing("drop", _dropName, dropPoint);
      _failed = false;
    });
    if (_pickupError != null || _dropError != null || weightKg <= 0) return;
    setState(() => _searching = true);
    try {
      final r = await api.get<Map<String, dynamic>>(
          "/v1/customer/eligible-anchor-trips",
          query: {
            "pickupLat": pickupPoint!.latitude.toString(),
            "pickupLng": pickupPoint.longitude.toString(),
            "dropLat": dropPoint!.latitude.toString(),
            "dropLng": dropPoint.longitude.toString(),
            "weightKg": weightKg.toString(),
          });
      final raw = r.data?["trips"];
      final lanes = <Map<String, dynamic>>[];
      // The server keeps its closest-first order; rows failing its distance test are left out.
      for (final row in raw is List ? raw : const []) {
        final lane = row is Map ? row["trip"] : null;
        final eligibility = row is Map ? row["eligibility"] : null;
        if (lane is Map<String, dynamic> &&
            eligibility is Map &&
            eligibility["eligible"] == true) {
          lanes.add(lane);
        }
      }
      if (!mounted) return;
      setState(() {
        _lanes = lanes;
        _searchedWeightKg = weightKg;
        _searchedPickup = pickupPlace;
        _searchedDrop = dropPlace;
        _editing = false;
      });
      announce(context,
          lanes.isEmpty ? _emptyTitle(weightKg) : _resultLine(lanes.length));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _resultLine(int count) =>
      "$count ${count == 1 ? "trip" : "trips"} with capacity for ${formatKg(_searchedWeightKg!)}, closest to your route first.";

  String _emptyTitle(int weightKg) =>
      "No trips pass near this route with capacity for ${formatKg(weightKg)}.";

  String _bookPath(Map<String, dynamic> lane) =>
      Uri(path: "/customer/book", queryParameters: {
        "anchorTripId": lane["id"]?.toString() ?? "",
        "weightKg": "$_searchedWeightKg",
      }).toString();

  /// The searched places go to Book in memory, never in the link: see [SearchedPlaces].
  SearchedPlaces get _searchedPlaces =>
      SearchedPlaces(pickup: _searchedPickup!, drop: _searchedDrop!);

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(vertical: NvSpace.s3);
    if (!customerIsDesktop(context)) {
      return ListView(
        padding: padding,
        children: _editing ? _form() : [..._searchSummary(), ..._laneResults()],
      );
    }
    // On a desktop the search sits beside its results (wb-lanes).
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: CustomerBreakpoints.sideColumn,
        child: ListView(
            padding: padding, children: _editing ? _form() : _searchSummary()),
      ),
      const SizedBox(width: NvSpace.s6),
      Expanded(
        child: ListView(
            padding: padding,
            children: _searchedWeightKg == null ? const [] : _laneResults()),
      ),
    ]);
  }

  /// The place box with its error under it, in one row of the list: an error added as a row of its
  /// own would move the boxes below it, which rebuilds them and loses their search state.
  Widget _placeWithError(Widget placeBox, String? error) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          placeBox,
          if (error != null) ...[
            const SizedBox(height: NvSpace.s2),
            NvMessage(error, tone: NvMessageTone.problem),
          ],
        ],
      );

  List<Widget> _form() => [
        // Each map shows once its place has a pin, so the form stays short while typing.
        _placeWithError(
          LocationEndpointEditor(
            title: "Pickup",
            hint: "Address for the driver",
            example: "House or plot, street, area",
            labelController: _pickupName,
            markerId: "match_pickup",
            markerHue: BitmapDescriptor.hueGreen,
            position: _pickupPin ?? pinNotPlacedYet,
            onPositionChanged: (pin) => setState(() {
              _pickupPin = pin;
              _pickupError = null;
            }),
            onPinNaming: (naming) => setState(() => _namingPickupPin = naming),
            onSearching: (searching) =>
                setState(() => _searchingPickup = searching),
            pinAddress: _pickupPinAddress,
            onPinAddress: (address) =>
                setState(() => _pickupPinAddress = address),
            readOnly: _searching,
            showMap: _pickupPin != null,
            showApiKeyHint: false,
            findPlace: widget.findPlace,
            namePin: widget.namePin,
            keepsFullAddress: true,
            // A drag naming or a search still out when the box scrolls off screen would be lost.
            staysAliveOffScreen: true,
          ),
          _pickupError,
        ),
        const SizedBox(height: NvSpace.s4),
        _placeWithError(
          LocationEndpointEditor(
            title: "Drop",
            hint: "Address for the driver",
            example: "House or plot, street, area",
            labelController: _dropName,
            markerId: "match_drop",
            markerHue: BitmapDescriptor.hueRed,
            position: _dropPin ?? pinNotPlacedYet,
            onPositionChanged: (pin) => setState(() {
              _dropPin = pin;
              _dropError = null;
            }),
            onPinNaming: (naming) => setState(() => _namingDropPin = naming),
            onSearching: (searching) =>
                setState(() => _searchingDrop = searching),
            pinAddress: _dropPinAddress,
            onPinAddress: (address) =>
                setState(() => _dropPinAddress = address),
            readOnly: _searching,
            showMap: _dropPin != null,
            showApiKeyHint: false,
            findPlace: widget.findPlace,
            namePin: widget.namePin,
            keepsFullAddress: true,
            // A drag naming or a search still out when the box scrolls off screen would be lost.
            staysAliveOffScreen: true,
          ),
          _dropError,
        ),
        const SizedBox(height: NvSpace.s4),
        NvField(
            label: "Weight",
            controller: _weightKg,
            unit: "kg",
            keyboardType: TextInputType.number,
            errorText: _weightError),
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Find trips",
            fullWidth: true,
            loading: _searching,
            onPressed: _searchBlockedBy == null ? _search : null,
            disabledReason: _searchBlockedBy),
        if (_failed) ...[
          const SizedBox(height: NvSpace.s3),
          NvListError(
              title: "Could not load trips.",
              help: "Check your connection, then try again.",
              onRetry: _search),
        ],
      ];

  List<Widget> _searchSummary() => [
        SearchSummary(
          rows: [
            ("Pickup", _searchedPickup!.words),
            ("Drop", _searchedDrop!.words),
            ("Weight", formatKg(_searchedWeightKg!)),
          ],
          changeLabel: "Change",
          onChange: () => setState(() => _editing = true),
        ),
        const SizedBox(height: NvSpace.s3),
      ];

  List<Widget> _laneResults() => [
        if (_lanes.isEmpty)
          _NoMatchBox(
            title: _emptyTitle(_searchedWeightKg!),
            onChangeWeight: () => setState(() => _editing = true),
            onBrowseAll: widget.onBrowseAll,
          )
        else ...[
          Semantics(
              liveRegion: true,
              child:
                  Text(_resultLine(_lanes.length), style: NvText.caption)),
          ..._laneCards(context, _lanes,
              onOpen: (lane) =>
                  context.go(_bookPath(lane), extra: _searchedPlaces)),
        ],
      ];
}

/// Match found nothing: say so, and offer a lower weight or every lane (sh-lanes-empty).
class _NoMatchBox extends StatelessWidget {
  const _NoMatchBox(
      {required this.title,
      required this.onChangeWeight,
      required this.onBrowseAll});
  final String title;
  final VoidCallback onChangeWeight;
  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.sunken,
            borderRadius: BorderRadius.circular(NvRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: ExcludeSemantics(
                  child:
                      Icon(Icons.local_shipping_outlined, color: NvColors.slate)),
            ),
            const SizedBox(height: NvSpace.s3),
            Semantics(
                liveRegion: true,
                child: Text(title,
                    style: NvText.bodyStrong.copyWith(color: NvColors.navyInk))),
            const SizedBox(height: NvSpace.s2),
            const Text("Try less weight, or see all trips.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s4),
            NvButton(
                label: "Change weight",
                fullWidth: true,
                onPressed: onChangeWeight),
            const SizedBox(height: NvSpace.s2),
            NvButton(
                label: "See all trips",
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: onBrowseAll),
          ],
        ),
      );
}
