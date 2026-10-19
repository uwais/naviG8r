import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../authorization_session.dart";
import "../customer_layout.dart";
import "../customer_session.dart";
import "../pilot_api.dart";
import "../shipment_steps.dart";
import "../ui/nv_button.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_status_label.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";
import "announce.dart";

typedef _ShipmentRow = ({
  String route,
  String? date,
  String? weight,
  String carrier,
  NvStatusLabel status,
  String? next,
  bool needsYou,
  VoidCallback open,
});

class CustomerShipmentsScreen extends StatefulWidget {
  const CustomerShipmentsScreen({super.key});

  @override
  State<CustomerShipmentsScreen> createState() =>
      _CustomerShipmentsScreenState();
}

class _CustomerShipmentsScreenState extends State<CustomerShipmentsScreen> {
  bool _loading = true;
  bool _failed = false;
  bool _needsAuth = false;
  List<Map<String, dynamic>> _shipments = [];
  Map<String, Map<String, dynamic>> _lanesById = {};

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _needsAuth = false;
    });
    announce(context, "Loading shipments.");
    await CustomerSession.refresh();
    if (!mounted) return;
    final lanes = loadLanesById();
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments");
      final raw = r.data?["shipments"];
      final list = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final lanesById = await lanes;
      if (!mounted) return;
      setState(() {
        _shipments = list;
        _lanesById = lanesById;
      });
      announce(context, shipmentCount(list.length));
    } catch (e) {
      await lanes;
      if (!mounted) return;
      setState(() {
        _failed = true;
        _needsAuth = !CustomerSession.isSignedIn ||
            (e is DioException && e.response?.statusCode == 401);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  bool _needsYou(Map<String, dynamic> shipment) =>
      shipperTaskFor(shipment,
          canWriteBill: AuthorizationSession.can("eway_bill.write"),
          canAddTruck: AuthorizationSession.can("eway_bill.add_truck"),
          canAcceptDelivery: AuthorizationSession.can("pod.accept"),
          tripStatus:
              laneOfShipment(shipment, _lanesById)?["status"]?.toString()) !=
      null;

  /// What a card or a table row says about [shipment], the same on a phone and a desktop.
  _ShipmentRow _row(Map<String, dynamic> shipment) {
    final lane = laneOfShipment(shipment, _lanesById);
    final tripStatus = lane?["status"]?.toString();
    final progress = shipmentProgress(shipment, tripStatus: tripStatus);
    final needsYou = _needsYou(shipment);
    final id = shipment["id"]?.toString() ?? "";
    return (
      route: shipmentRouteName(shipment, lane: lane, withDate: false) ??
          "Shipment",
      date: laneStartWords(lane),
      weight: weightWords(shipment),
      carrier: carrierOf(shipment),
      status: needsYou
          ? const NvStatusLabel("Needs you", tone: NvStatusTone.attention)
          : NvStatusLabel(progress.statusWord, tone: progress.statusTone),
      next: progress.next,
      needsYou: needsYou,
      open: () {
        if (id.isNotEmpty) context.go("/customer/shipments/$id");
      },
    );
  }

  Widget _card(Map<String, dynamic> shipment) {
    final row = _row(shipment);
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: NvListCard(
        title: row.route,
        status: row.status,
        subtitle:
            [row.date, row.weight, row.carrier].whereType<String>().join(" · "),
        next: row.next == null ? null : "${row.next}.",
        needsYou: row.needsYou,
        onOpen: row.open,
      ),
    );
  }

  /// The desktop list (wb-shipments): one row per shipment, its route the link that opens it.
  /// A window narrower than the columns scrolls the table sideways inside its own box.
  Widget _table(List<Map<String, dynamic>> shipments) {
    Widget cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: NvSpace.s3, vertical: NvSpace.s2),
        child: child);
    Widget words(String? text) => cell(Text(text ?? "", style: NvText.body));
    Widget columnName(String text) => cell(Semantics(
        header: true,
        child: Text(text,
            style: NvText.caption
                .copyWith(fontWeight: FontWeight.w700, color: NvColors.ink))));
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            width: constraints.maxWidth < CustomerBreakpoints.tableMin
                ? CustomerBreakpoints.tableMin
                : constraints.maxWidth,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: NvColors.card,
                borderRadius: BorderRadius.circular(NvRadius.card),
                border: Border.all(color: NvColors.line)),
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.2),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
                5: FlexColumnWidth(3.5),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: NvColors.sunken),
                  children: [
                    for (final name in [
                      "Route",
                      "Date",
                      "Weight",
                      "Carrier",
                      "Status",
                      "Next"
                    ])
                      columnName(name),
                  ],
                ),
                for (final row in shipments.map(_row))
                  TableRow(
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: NvColors.line))),
                    children: [
                      cell(Semantics(
                        link: true,
                        child: InkWell(
                          onTap: row.open,
                          borderRadius: BorderRadius.circular(NvRadius.sm),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                minHeight: NvSpace.targetMin),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(row.route,
                                  style: NvText.bodyStrong.copyWith(
                                      color: NvColors.navyInk,
                                      decoration: TextDecoration.underline)),
                            ),
                          ),
                        ),
                      )),
                      words(row.date),
                      words(row.weight),
                      words(row.carrier),
                      cell(Align(
                          alignment: Alignment.centerLeft, child: row.status)),
                      words(row.next),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _list() {
    if (_needsAuth) {
      return [
        const NvListEmpty(
            title:
                "Sign in and select your organization to see its shipments."),
        const SizedBox(height: NvSpace.s3),
        NvButton(
            label: "Sign in",
            fullWidth: true,
            onPressed: () => context.go("/customer/login")),
      ];
    }
    if (_failed) {
      return [
        NvListError(
            title: "Could not load your shipments.",
            help: "Check your connection, then try again.",
            onRetry: _load),
      ];
    }
    if (_loading && _shipments.isEmpty) {
      return const [
        NvListLoadingCard(),
        SizedBox(height: NvSpace.s3),
        NvListLoadingCard(),
      ];
    }
    if (_shipments.isEmpty) {
      return [
        const NvListEmpty(
            title: "No shipments yet.",
            help: "Browse carrier lanes and book your first shipment."),
        const SizedBox(height: NvSpace.s3),
        NvButton(
            label: "Find a lane",
            fullWidth: true,
            onPressed: () => context.go("/customer/trips")),
      ];
    }
    // A delivery still waiting for the shipper's acceptance stays under Active, where its task is.
    bool isDone(Map<String, dynamic> shipment) {
      final status = shipment["status"];
      return (status == "DELIVERED" ||
              status == "PENDING_RELEASE" ||
              status == "FAILED_CARRIER_REFUNDED") &&
          !_needsYou(shipment);
    }

    final active = _shipments.where((s) => !isDone(s)).toList();
    final done = _shipments.where(isDone).toList();
    Widget heading(String words) => Padding(
          padding: const EdgeInsets.only(top: NvSpace.s4),
          child: Semantics(
              header: true,
              child: Text(words,
                  style: NvText.heading.copyWith(color: NvColors.ink))),
        );
    final desktop = customerIsDesktop(context);
    return [
      if (active.isNotEmpty) ...[
        heading("Active (${active.length})"),
        if (desktop)
          _table(active)
        else
          for (final shipment in active) _card(shipment),
      ],
      if (done.isNotEmpty) ...[
        heading("Done"),
        if (desktop)
          _table(done)
        else
          for (final shipment in done) _card(shipment),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Shipments",
      currentPath: "/customer/shipments",
      bodyBuilder: (_) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: NvSpace.s6),
          children: _list(),
        ),
      ),
    );
  }
}
