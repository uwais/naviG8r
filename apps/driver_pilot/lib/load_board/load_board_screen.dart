// The Load Board (Load Board phase 1, 4 Nov 2026): open loads shippers posted, soonest pickup first, for the office
// of an approved carrier. Never a driver. A load shows its towns, weight, size and pickup days, and nothing else:
// no amount, no shipper, no address. "Add a trip for this load" opens today's Add a trip form, filled in.
import "dart:async";

import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../authorization_session.dart";
import "../pilot_api.dart";
import "../ui/nv_button.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_refresh_button.dart";
import "../ui/nv_section_card.dart";
import "../ui/tokens.dart";
import "posted_load_words.dart";
import "trip_for_load.dart";

/// The office of a carrier: whoever may name a trip's truck and driver, as the server's board audience is.
bool seesLoadBoard() =>
    AuthorizationSession.can("trip.assign") &&
    AuthorizationSession.can("trip.publish");

class LoadBoardScreen extends StatefulWidget {
  const LoadBoardScreen({super.key});

  @override
  State<LoadBoardScreen> createState() => _LoadBoardScreenState();
}

class _LoadBoardScreenState extends State<LoadBoardScreen> {
  List<Map<String, dynamic>> _loads = [];
  bool _loading = true;
  String? _failure;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/load-board");
      final raw = r.data?["loads"];
      if (!mounted) return;
      setState(() => _loads = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[]);
    } catch (error) {
      if (!mounted) return;
      final body = error is DioException ? error.response?.data : null;
      final code = body is Map ? body["error"] : null;
      setState(() {
        _loads = [];
        _failure = code == "carrier_compliance_required"
            ? "NaviG8r must approve your company before you can see the Load Board."
            : code == "forbidden"
                ? "Only owners and dispatchers can see the Load Board."
                : "Could not load the Load Board.";
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTrip(Map<String, dynamic> row) async {
    final load = LoadForTrip.fromBoard(row);
    if (load == null) return;
    await context.push("/driver/load-board/trip", extra: load);
    // A trip added for it, or by someone else, may have changed the board.
    if (mounted) unawaited(_load());
  }

  Widget _loadCard(Map<String, dynamic> load) {
    final facts = [
      if (loadWeightWords(load) case final weight?) ("Weight", weight),
      if (packagesWords(load["packages"]) case final size?) ("Size", size),
      if (pickupDaysWords(load) case final days?) ("Pickup", days),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: NvSectionCard(
        title: postedLoadRoute(load),
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
          const SizedBox(height: NvSpace.s2),
          NvButton(
              label: "Add a trip for this load",
              semanticsLabel:
                  "Add a trip for the load ${postedLoadRoute(load)}",
              kind: NvButtonKind.secondary,
              fullWidth: true,
              onPressed: LoadForTrip.fromBoard(load) == null
                  ? null
                  : () => _addTrip(load),
              disabledReason: LoadForTrip.fromBoard(load) == null
                  ? "This load is missing its details. Refresh the board."
                  : null),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
          children: [
            Row(children: [
              const Expanded(
                child: Text("Open loads, soonest pickup first.",
                    style: NvText.body),
              ),
              NvRefreshButton(loading: _loading, onPressed: _load),
            ]),
            if (_loading && _loads.isEmpty && _failure == null) ...[
              const SizedBox(height: NvSpace.s3),
              const NvListLoadingCard(),
            ] else if (_failure != null) ...[
              const SizedBox(height: NvSpace.s3),
              NvListError(title: _failure!, onRetry: _load),
            ] else if (_loads.isEmpty) ...[
              const SizedBox(height: NvSpace.s3),
              const NvListEmpty(
                  title: "No open loads right now.",
                  help: "New loads show here when shippers post them."),
            ] else
              for (final load in _loads) _loadCard(load),
          ],
        ),
      );
}
