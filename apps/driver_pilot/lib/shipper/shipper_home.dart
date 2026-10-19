import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../authorization_session.dart";
import "../customer_session.dart";
import "../pilot_api.dart";
import "../notification_center.dart";
import "../shipment_steps.dart";
import "../sign_in_screen.dart";
import "../ui/format.dart";
import "../ui/nv_button.dart";
import "../ui/nv_list_card.dart";
import "../ui/nv_status_label.dart";
import "../ui/tokens.dart";
import "shipper_scaffold.dart";
import "shipper_words.dart";

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  List<Map<String, dynamic>> _shipments = [];
  Map<String, Map<String, dynamic>> _lanesById = {};
  bool _shipmentsFailed = false;
  int _unreadUpdates = 0;
  String? _loadedForAccount;

  @override
  void initState() {
    super.initState();
    // Home sits under the sign-in page, so it is built signed out and must load once sign-in lands.
    CustomerSession.listenable.addListener(_loadWhenTheAccountChanges);
    CustomerSession.refresh().then((_) {
      if (mounted && _loadedForAccount != AuthorizationSession.scopeKey) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    CustomerSession.listenable.removeListener(_loadWhenTheAccountChanges);
    super.dispose();
  }

  void _loadWhenTheAccountChanges() {
    if (!mounted) return;
    final account =
        CustomerSession.isSignedIn ? AuthorizationSession.scopeKey : null;
    if (account == _loadedForAccount) return;
    // Another account's shipments must not show while this one's load.
    setState(() {
      _shipments = [];
      _lanesById = {};
      _shipmentsFailed = false;
      _unreadUpdates = 0;
    });
    _loadedForAccount = null;
    if (account != null && !AuthorizationSession.switching) _load();
  }

  Future<void> _load() async {
    if (!CustomerSession.isSignedIn || !CustomerSession.hasCustomerOrg) return;
    _loadedForAccount = AuthorizationSession.scopeKey;
    await Future.wait([_loadShipments(), _loadUnreadUpdates(), _loadLanes()]);
  }

  /// A request sent for one account can come back after another signed in; its answer, or its
  /// cancel, must not land on the new account's Home.
  bool _stillShowing(String account) =>
      mounted && AuthorizationSession.scopeKey == account;

  Future<void> _loadShipments() async {
    if (!AuthorizationSession.can("load.read")) return;
    final account = AuthorizationSession.scopeKey;
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments");
      final raw = r.data?["shipments"];
      if (!_stillShowing(account)) return;
      setState(() {
        _shipments =
            raw is List ? raw.whereType<Map<String, dynamic>>().toList() : [];
        _shipmentsFailed = false;
      });
    } catch (_) {
      if (_stillShowing(account)) setState(() => _shipmentsFailed = true);
    }
  }

  Future<void> _loadLanes() async {
    final account = AuthorizationSession.scopeKey;
    final lanesById = await loadLanesById();
    if (_stillShowing(account)) setState(() => _lanesById = lanesById);
  }

  Future<void> _loadUnreadUpdates() async {
    if (!AuthorizationSession.can("notification.read")) return;
    final account = AuthorizationSession.scopeKey;
    try {
      final r =
          await api.get<Map<String, dynamic>>("/v1/notifications/shipments");
      if (_stillShowing(account)) {
        setState(() =>
            _unreadUpdates = (r.data?["unreadCount"] as num?)?.toInt() ?? 0);
      }
    } catch (_) {
      // The Updates row still opens the inbox, which shows its own error.
    }
  }

  // Listens to the session: the router keeps this page when only the session changes.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: CustomerSession.listenable,
      builder: (context, _) => _home(context));

  Widget _home(BuildContext context) {
    if (!CustomerSession.isSignedIn) {
      return const SignInScreen();
    }
    final canWriteBill = AuthorizationSession.can("eway_bill.write");
    final canAddTruck = AuthorizationSession.can("eway_bill.add_truck");
    Map<String, dynamic>? taskShipment;
    String? task;
    for (final shipment in _shipments) {
      task = shipperTaskFor(shipment,
          canWriteBill: canWriteBill,
          canAddTruck: canAddTruck,
          tripStatus:
              laneOfShipment(shipment, _lanesById)?["status"]?.toString());
      if (task != null && (shipment["id"]?.toString() ?? "").isNotEmpty) {
        taskShipment = shipment;
        break;
      }
    }
    final waiting = _shipments
        .where((s) => s["status"] == "PENDING_CARRIER_ACCEPT")
        .length;
    final accepted = _shipments.where((s) => s["status"] == "BOOKED").length;
    final showsUpdates = AuthorizationSession.can("notification.read");

    return CustomerScaffold(
      title: "Home",
      currentPath: "/customer",
      bodyBuilder: (_) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: NvSpace.s2),
          children: [
            if (taskShipment != null) ...[
              _NeedsYouCard(
                  task: task!,
                  shipment: taskShipment,
                  lane: laneOfShipment(taskShipment, _lanesById)),
              const SizedBox(height: NvSpace.s6),
            ],
            if (_shipmentsFailed) ...[
              NvListError(
                  title: "Could not load your shipments.",
                  help: "Check your connection, then try again.",
                  onRetry: _loadShipments),
              const SizedBox(height: NvSpace.s4),
            ],
            if (waiting > 0 || accepted > 0 || showsUpdates) ...[
              Semantics(
                header: true,
                child: Text("Your shipments",
                    style: NvText.heading.copyWith(color: NvColors.ink)),
              ),
              const SizedBox(height: NvSpace.s3),
              _HomeRows(children: [
                if (waiting > 0)
                  _HomeRow(
                    leading: const NvStatusLabel("Waiting for carrier",
                        tone: NvStatusTone.attention),
                    title: shipmentCount(waiting),
                    onTap: () => context.go("/customer/shipments"),
                  ),
                if (accepted > 0)
                  _HomeRow(
                    leading: const NvStatusLabel("Accepted",
                        tone: NvStatusTone.info),
                    title: shipmentCount(accepted),
                    onTap: () => context.go("/customer/shipments"),
                  ),
                if (showsUpdates)
                  _HomeRow(
                    leading: const ExcludeSemantics(
                        child: Icon(Icons.notifications_outlined,
                            color: NvColors.slate)),
                    title: "Updates",
                    caption: _unreadUpdates > 0 ? "$_unreadUpdates new" : null,
                    onTap: () async {
                      await openNotificationInbox(context);
                      if (mounted) unawaited(_loadUnreadUpdates());
                    },
                  ),
              ]),
              const SizedBox(height: NvSpace.s4),
            ],
            NvButton(
              label: "Find a lane for new goods",
              kind: taskShipment == null
                  ? NvButtonKind.primary
                  : NvButtonKind.secondary,
              fullWidth: true,
              onPressed: () => context.go("/customer/trips"),
            ),
            if (CustomerSession.isOrgAdmin) ...[
              const SizedBox(height: NvSpace.s6),
              _HomeRows(children: [
                _HomeRow(
                  title: CustomerSession.customerOrgName ?? "Your org",
                  caption: "Manage who can book and view shipments",
                  onTap: () => context.go("/customer/team"),
                ),
                _HomeRow(
                  title: "ERP integrations",
                  caption: "API keys, webhooks, and sync status for your ERP",
                  onTap: () => context.go("/customer/integrations"),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one task waiting on the shipper, with the button that opens its shipment.
class _NeedsYouCard extends StatelessWidget {
  const _NeedsYouCard(
      {required this.task, required this.shipment, required this.lane});
  final String task;
  final Map<String, dynamic> shipment;
  final Map<String, dynamic>? lane;

  // Who did what, in the shipment step's own words (spec/copy.md).
  String get _whatHappened {
    final bill = shipment["ewayBill"];
    final carrier = carrierOf(shipment);
    if (task == "Fix the e-way bill") return "NaviG8r staff found a difference.";
    if (bill is Map && bill["billNumber"] is String) {
      return "Bill ${formatBillNumber(bill["billNumber"] as String)} saved. The truck is not on it yet.";
    }
    final truck = shipment["assignedTruckNumber"]?.toString() ?? "";
    return truck.isEmpty
        ? "$carrier accepted."
        : "$carrier accepted and named the truck.";
  }

  @override
  Widget build(BuildContext context) {
    final name = shipmentRouteName(shipment, lane: lane);
    final route = name == null ? "" : "$name. ";
    final id = shipment["id"]?.toString() ?? "";
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
        color: NvColors.card,
        borderRadius: BorderRadius.circular(NvRadius.card),
        border: Border.all(color: NvColors.navy, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
              header: true,
              child: const Text("NEEDS YOU", style: NvText.label)),
          const SizedBox(height: NvSpace.s3),
          Text(task, style: NvText.heading),
          const SizedBox(height: NvSpace.s1),
          Text("$route$_whatHappened", style: NvText.body),
          const SizedBox(height: NvSpace.s4),
          NvButton(
            label: "Open shipment",
            fullWidth: true,
            onPressed: () => context.go("/customer/shipments/$id"),
          ),
        ],
      ),
    );
  }
}

/// Rows on one white card, split by thin lines, as on the shipper Home (sh-home).
class _HomeRows extends StatelessWidget {
  const _HomeRows({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: NvColors.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NvRadius.card),
            side: const BorderSide(color: NvColors.line)),
        child: Column(children: [
          for (final (index, row) in children.indexed) ...[
            if (index > 0) const Divider(height: 1, color: NvColors.line),
            row,
          ],
        ]),
      );
}

class _HomeRow extends StatelessWidget {
  const _HomeRow(
      {required this.title, required this.onTap, this.leading, this.caption});
  final Widget? leading;
  final String title;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: onTap,
            highlightColor: NvColors.sunken,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: NvSpace.targetMin),
              child: Padding(
                padding: const EdgeInsets.all(NvSpace.s4),
                child: Row(children: [
                  Expanded(
                    // Wraps, so a long status word and the count stack at large text.
                    child: Wrap(
                      spacing: NvSpace.s3,
                      runSpacing: NvSpace.s1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (leading != null) leading!,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(title, style: NvText.bodyStrong),
                            if (caption != null)
                              Text(caption!, style: NvText.caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const ExcludeSemantics(
                      child: Icon(Icons.chevron_right, color: NvColors.slate)),
                ]),
              ),
            ),
          ),
        ),
      );
}
