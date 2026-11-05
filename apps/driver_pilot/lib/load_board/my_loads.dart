// My loads (Load Board phase 1, 4 Nov 2026): every load the shipper's company posted, closed ones too, with the
// trips carriers added for each. Book opens today's booking for that trip, which is the first place a price shows.
import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../authorization_session.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "../shipper/announce.dart";
import "../shipper/book_a_lane.dart" show SearchedPlaces;
import "../shipper/shipper_scaffold.dart";
import "../shipper/shipper_words.dart";
import "../ui/nv_button.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_refresh_button.dart";
import "../ui/nv_section_card.dart";
import "../ui/tokens.dart";
import "posted_load_words.dart";

/// Why a trip has no Book button, from the server's reason (features/loadBoard/postedLoadViews.ts).
String _notBookableSentence(Object? reason) => switch (reason) {
      "YOU_BOOKED_IT" => "You booked this trip.",
      "LOAD_CLOSED" =>
        "This load is closed. You can still book this trip from Book a trip.",
      "TRIP_CLOSED" => "This trip is no longer taking bookings.",
      "NOT_ENOUGH_ROOM" => "Not enough room left on this trip for this load.",
      _ => "Not open for booking.",
    };

class MyLoadsScreen extends StatefulWidget {
  const MyLoadsScreen({super.key});

  @override
  State<MyLoadsScreen> createState() => _MyLoadsScreenState();
}

class _MyLoadsScreenState extends State<MyLoadsScreen> {
  List<Map<String, dynamic>> _loads = [];
  bool _loading = true;
  bool _failed = false;
  // The load being withdrawn, and the sentence for a withdraw that failed, by load id.
  String? _withdrawing;
  final _withdrawErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/posted-loads");
      final raw = r.data?["loads"];
      if (!mounted) return;
      setState(() => _loads = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _withdraw(String loadId) async {
    if (_withdrawing != null) return;
    setState(() {
      _withdrawing = loadId;
      _withdrawErrors.remove(loadId);
    });
    try {
      await api.post<Map<String, dynamic>>(
          "/v1/posted-loads/${Uri.encodeComponent(loadId)}/withdraw");
      if (mounted) announce(context, "Load withdrawn.");
    } catch (error) {
      if (mounted) {
        setState(() => _withdrawErrors[loadId] = plainErrorSentence(error,
            "Could not withdraw. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _withdrawing = null);
    }
    // Withdrawn, or already closed elsewhere: either way the list shows what is true now.
    if (mounted) await _load();
  }

  /// Today's booking for [route]'s trip, with the load's weight and its two map points. The town stands in for
  /// the address until the shipper types the address for the driver there.
  void _book(Map<String, dynamic> load, Map<String, dynamic> route) {
    final from = load["from"];
    final to = load["to"];
    final weight = load["weightKg"];
    if (from is! Map || to is! Map || weight is! num) return;
    LatLng? point(Map place) => place["lat"] is num && place["lng"] is num
        ? LatLng((place["lat"] as num).toDouble(), (place["lng"] as num).toDouble())
        : null;
    context.go(
        Uri(path: "/customer/book", queryParameters: {
          "anchorTripId": route["tripId"]?.toString() ?? "",
          "weightKg": "${weight.round()}",
        }).toString(),
        extra: SearchedPlaces(
            pickup: (words: "${from["city"] ?? ""}", point: point(from), pinAddress: null),
            drop: (words: "${to["city"] ?? ""}", point: point(to), pinAddress: null)));
  }

  Widget _route(Map<String, dynamic> load, Map<String, dynamic> route) {
    final trip = route["trip"] is Map<String, dynamic>
        ? route["trip"] as Map<String, dynamic>
        : const <String, dynamic>{};
    final carrier = trip["carrierDisplayName"]?.toString() ?? "Carrier";
    final leaves = laneLeaves(trip);
    final truck = vehicleClassLabel(trip["vehicleClass"]?.toString());
    final canBook = route["canBook"] == true &&
        AuthorizationSession.can("load.create");
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: Container(
        padding: const EdgeInsets.all(NvSpace.s3),
        decoration: BoxDecoration(
            color: NvColors.sunken,
            borderRadius: BorderRadius.circular(NvRadius.sm)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(carrier, style: NvText.bodyStrong),
                  Text([if (leaves != null) leaves, truck].join(" · "),
                      style: NvText.body),
                ],
              ),
            ),
            const SizedBox(height: NvSpace.s2),
            if (canBook)
              NvButton(
                  label: "Book",
                  semanticsLabel: "Book $carrier",
                  fullWidth: true,
                  onPressed: () => _book(load, route))
            else
              Text(_notBookableSentence(route["whyNotBookable"]),
                  style: NvText.caption),
          ],
        ),
      ),
    );
  }

  Widget _loadCard(Map<String, dynamic> load) {
    final id = load["id"]?.toString() ?? "";
    final state = load["state"]?.toString() ?? "";
    final routes = load["routes"] is List
        ? (load["routes"] as List).whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    final booking = load["booking"];
    final shipmentId =
        booking is Map ? booking["shipmentId"]?.toString() ?? "" : "";
    final facts = [
      if (loadWeightWords(load) case final weight?) ("Weight", weight),
      if (packagesWords(load["packages"]) case final size?) ("Size", size),
      if (pickupDaysWords(load) case final days?) ("Pickup", days),
    ];
    final withdrawError = _withdrawErrors[id];
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: NvSectionCard(
        title: postedLoadRoute(load),
        action: postedLoadStateLabel(state),
        children: [
          const SizedBox(height: NvSpace.s2),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: NvSpace.s1),
              child: MergeSemantics(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: "$label ", style: NvText.caption),
                  TextSpan(text: value, style: NvText.body),
                ])),
              ),
            ),
          if (state == "BOOKED" && shipmentId.isNotEmpty) ...[
            const SizedBox(height: NvSpace.s2),
            NvButton(
                label: "Open shipment",
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: () => context.go(
                    "/customer/shipments/${Uri.encodeComponent(shipmentId)}")),
          ],
          if (state == "OPEN" || routes.isNotEmpty) ...[
            const SizedBox(height: NvSpace.s3),
            Semantics(
                header: true,
                child: Text(
                    routes.isEmpty
                        ? "Trips for this load"
                        : "Trips for this load (${routes.length})",
                    style: NvText.label)),
            if (routes.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: NvSpace.s2),
                child: Text(
                    "No carrier has added a trip yet. We tell you when one does.",
                    style: NvText.body),
              )
            else
              for (final route in routes) _route(load, route),
          ],
          if (state == "OPEN" && AuthorizationSession.can("load.create")) ...[
            const SizedBox(height: NvSpace.s3),
            if (withdrawError != null) ...[
              Text(withdrawError, style: NvText.body),
              const SizedBox(height: NvSpace.s2),
            ],
            NvButton(
                label: "Withdraw",
                kind: NvButtonKind.quiet,
                semanticsLabel: "Withdraw the load ${postedLoadRoute(load)}",
                loading: _withdrawing == id,
                fullWidth: true,
                onPressed: () => _withdraw(id)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CustomerScaffold(
        title: "My loads",
        subtitle: "Loads your company posted for carriers.",
        currentPath: "/customer/loads",
        titleAction: NvRefreshButton(loading: _loading, onPressed: _load),
        bodyBuilder: (_) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
            children: [
              if (_loading && _loads.isEmpty)
                const NvListLoadingCard()
              else if (_failed && _loads.isEmpty)
                NvListError(
                    title: "Could not load your loads.",
                    help: "Check your connection, then try again.",
                    onRetry: _load)
              else if (_loads.isEmpty)
                const NvListEmpty(
                    title: "No loads posted yet.",
                    help:
                        "When Search by route finds no trip, you can post your load from there.")
              else
                for (final load in _loads) _loadCard(load),
              const SizedBox(height: NvSpace.s4),
              NvButton(
                  label: "Book a trip",
                  kind: NvButtonKind.secondary,
                  fullWidth: true,
                  onPressed: () => context.go("/customer/trips?tab=match")),
            ],
          ),
        ),
      );
}
