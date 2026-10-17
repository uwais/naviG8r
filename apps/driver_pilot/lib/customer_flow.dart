import "dart:async";

import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "access_refresh.dart";
import "authorization_session.dart";
import "shipment_payment_status.dart";
import "eway_bill_card.dart";
import "eway_bill_portal_link.dart";
import "google_geocoding.dart";
import "customer_checkout.dart";
import "customer_layout.dart";
import "customer_session.dart";
import "driver_theme.dart";
import "location_editor.dart";
import "pilot_api.dart";
import "notification_center.dart";
import "shipment_steps.dart";
import "signed_in_header.dart";
import "start_screen.dart";
import "ui/format.dart";
import "ui/nv_action_bar.dart";
import "ui/nv_button.dart";
import "ui/nv_field.dart";
import "ui/nv_header.dart";
import "ui/nv_list_card.dart";
import "ui/nv_map.dart";
import "ui/nv_message.dart";
import "ui/nv_sheet.dart";
import "ui/nv_status_label.dart";
import "ui/nv_step_list.dart";
import "ui/pending_copy.dart";
import "ui/sign_in_code_page.dart";
import "ui/sign_in_phone_page.dart";
import "ui/tokens.dart";

String? lastBookedShipmentId;

List<RouteBase> customerFlowRoutes() {
  return [
    GoRoute(
      path: "/customer",
      builder: (_, __) => const CustomerHomeScreen(),
      routes: [
        GoRoute(path: "login", builder: (_, __) => const CustomerLoginScreen()),
        GoRoute(
            path: "register",
            builder: (_, __) => const CustomerRegisterScreen()),
        GoRoute(
            path: "register-user",
            builder: (_, __) => const CustomerRegisterUserScreen()),
        GoRoute(path: "team", builder: (_, __) => const CustomerTeamScreen()),
        GoRoute(
            path: "integrations",
            builder: (_, __) => const CustomerIntegrationsScreen()),
        GoRoute(
            path: "trips",
            builder: (_, state) => CustomerTripsScreen(
                startWithMatch: state.uri.queryParameters["tab"] == "match")),
        // Booking starts from a lane card: a Book screen with no lane is how stale prices and
        // guessed weights happened (spec/decisions.md).
        GoRoute(
            path: "book",
            redirect: (_, state) =>
                (state.uri.queryParameters["anchorTripId"] ?? "").isEmpty
                    ? "/customer/trips"
                    : null,
            builder: (_, state) =>
                CustomerBookShipmentScreen.fromQuery(state.uri.queryParameters)),
        GoRoute(
          path: "eligible",
          redirect: (_, __) => "/customer/trips?tab=match",
        ),
        GoRoute(
            path: "shipments",
            builder: (_, __) => const CustomerShipmentsScreen()),
        GoRoute(
          path: "shipments/:shipmentId",
          builder: (_, state) => CustomerShipmentDetailScreen(
              shipmentId: state.pathParameters["shipmentId"] ?? ""),
        ),
      ],
    ),
  ];
}

class CustomerScaffold extends StatelessWidget {
  const CustomerScaffold({
    required this.title,
    required this.currentPath,
    required this.bodyBuilder,
    this.subtitle,
    this.actionBar,
    super.key,
  });

  final String title;
  final String currentPath;
  final WidgetBuilder bodyBuilder;

  /// One line under the title, such as "Check the price, then pay."
  final String? subtitle;

  /// The screen's primary action, held at the bottom in place of the tabs (NvActionBar).
  final Widget? actionBar;

  // Book has no tab: it opens from a lane card, so it sits under Find a lane.
  int _indexForPath(String path) {
    if (path.startsWith("/customer/trips") ||
        path.startsWith("/customer/eligible") ||
        path.startsWith("/customer/book")) return 1;
    if (path.startsWith("/customer/shipments")) return 2;
    return 0;
  }

  static const _tabPaths = [
    "/customer",
    "/customer/trips",
    "/customer/shipments"
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CustomerSession.listenable,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final selected = _indexForPath(currentPath);
            final tabRoot = _tabPaths[selected];
            final useRail = customerUseRail(constraints.maxWidth);
            final page = CustomerPageFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        top: NvSpace.s4, bottom: NvSpace.s2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                            header: true,
                            child: Text(title, style: NvText.title)),
                        if (subtitle != null) ...[
                          const SizedBox(height: NvSpace.s1),
                          Text(subtitle!, style: NvText.body),
                        ],
                      ],
                    ),
                  ),
                  Expanded(child: bodyBuilder(context)),
                ],
              ),
            );

            void goToIndex(int index) {
              final target = _tabPaths[index];
              if (target != currentPath) context.go(target);
            }

            if (!CustomerSession.isSignedIn) {
              // Signed out: no account header and no tabs, only a way back to the start screen.
              return Scaffold(
                backgroundColor: DriverTheme.background,
                appBar: NvHeader.task(
                    backLabel: "Back", onBack: () => context.go("/customer")),
                body: SafeArea(child: page),
              );
            }

            final appBar = signedInHeader(
              context,
              backLabel: currentPath == tabRoot
                  ? null
                  : kCustomerNavDestinations[selected].label,
              onBack: currentPath == tabRoot ? null : () => context.go(tabRoot),
            );

            if (useRail) {
              return Scaffold(
                backgroundColor: DriverTheme.background,
                appBar: appBar,
                bottomNavigationBar: actionBar,
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    NavigationRail(
                      extended: constraints.maxWidth >= 1080,
                      selectedIndex: selected,
                      onDestinationSelected: goToIndex,
                      leading: const CustomerBrandHeader(),
                      destinations: customerRailDestinations(),
                      labelType: constraints.maxWidth >= 1080
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                        child: SafeArea(
                            left: false, child: AccessRefresh(child: page))),
                  ],
                ),
              );
            }

            return Scaffold(
              backgroundColor: DriverTheme.background,
              appBar: appBar,
              body: SafeArea(child: AccessRefresh(child: page)),
              bottomNavigationBar: actionBar ??
                  NavigationBar(
                    selectedIndex: selected,
                    onDestinationSelected: goToIndex,
                    destinations: kCustomerNavDestinations,
                  ),
            );
          },
        );
      },
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    CustomerSession.refresh().then((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!CustomerSession.isSignedIn) return;
    await Future.wait([_loadShipments(), _loadUnreadUpdates(), _loadLanes()]);
  }

  Future<void> _loadShipments() async {
    if (!AuthorizationSession.can("load.read")) return;
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments");
      final raw = r.data?["shipments"];
      if (!mounted) return;
      setState(() {
        _shipments =
            raw is List ? raw.whereType<Map<String, dynamic>>().toList() : [];
        _shipmentsFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _shipmentsFailed = true);
    }
  }

  Future<void> _loadLanes() async {
    final lanesById = await loadLanesById();
    if (mounted) setState(() => _lanesById = lanesById);
  }

  Future<void> _loadUnreadUpdates() async {
    if (!AuthorizationSession.can("notification.read")) return;
    try {
      final r =
          await api.get<Map<String, dynamic>>("/v1/notifications/shipments");
      if (mounted) {
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
      return const Scaffold(body: SafeArea(child: StartScreen()));
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
                    title: _shipmentCount(waiting),
                    onTap: () => context.go("/customer/shipments"),
                  ),
                if (accepted > 0)
                  _HomeRow(
                    leading: const NvStatusLabel("Accepted",
                        tone: NvStatusTone.info),
                    title: _shipmentCount(accepted),
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

String _shipmentCount(int count) =>
    count == 1 ? "1 shipment" : "$count shipments";

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
    final carrier = _carrierOf(shipment);
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
      );
}

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _debugCode;
  String? _challengeId;
  String? _challengePhone;
  bool _sending = false;
  bool _verifying = false;
  Timer? _otpCooldownTimer;
  int _otpCooldownSeconds = 0;
  String? _error;

  void _startOtpCooldown(dynamic rawMs) {
    _otpCooldownTimer?.cancel();
    final ms = rawMs is num ? rawMs.toInt() : 0;
    final seconds = ms > 0 ? (ms / 1000).ceil() : 0;
    if (mounted) setState(() => _otpCooldownSeconds = seconds);
    if (seconds > 0) {
      _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() => _otpCooldownSeconds =
            (_otpCooldownSeconds - 1).clamp(0, 1 << 30).toInt());
        if (_otpCooldownSeconds == 0) timer.cancel();
      });
    }
  }

  void _phoneChanged(String value) {
    final phone = digitsOnly(value.trim());
    if (_challengePhone == null || phone == _challengePhone) return;
    setState(() {
      _challengeId = null;
      _challengePhone = null;
      _debugCode = null;
      _code.clear();
      _otpCooldownSeconds = 0;
      _otpCooldownTimer?.cancel();
      _otpCooldownTimer = null;
    });
  }

  @override
  void initState() {
    super.initState();
    CustomerSession.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _otpCooldownTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final phone = digitsOnly(_phone.text.trim());
    if (phone.length != 10) {
      setState(() {
        _error = "Enter a 10-digit mobile number.";
        _sending = false;
      });
      return;
    }
    try {
      final previousChallengeId = _challengeId;
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start",
          data: {"phone": phone});
      if (!mounted) return;
      _challengeId = r.data?["challengeId"] as String?;
      _challengePhone = phone;
      _startOtpCooldown(r.data?["retryAfterMs"]);
      SemanticsService.announce(
          "Code sent to ${formatPhone(phone)}.", Directionality.of(context));
      final dc = r.data?["debugCode"];
      if (dc is String && dc.isNotEmpty) {
        _debugCode = dc;
        _code.text = dc;
      } else if (_challengeId != previousChallengeId) {
        _debugCode = null;
        _code.clear();
      }
    } catch (e) {
      final retry = otpRetryAfterMs(e);
      if (retry != null) _startOtpCooldown(retry);
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _error = null;
    });
    final phone = digitsOnly(_phone.text.trim());
    try {
      final challengeId = _challengeId;
      if (challengeId == null || phone != _challengePhone)
        throw Exception("Request a code for this phone number first.");
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {
          "phone": phone,
          "challengeId": challengeId,
          "code": _code.text.trim()
        },
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      await CustomerSession.refresh();
      if (!mounted) return;
      context.go(AuthorizationSession.hasRole("SHIPPER")
          ? "/customer/shipments"
          : AuthorizationSession.home);
    } catch (e) {
      if (mounted) {
        final error = formatApiError(e);
        setState(() => _error = error);
        SemanticsService.announce(error, Directionality.of(context),
            assertiveness: Assertiveness.assertive);
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  // Back to the phone step; the code request for the old number no longer applies.
  void _changeNumber() => setState(() {
        _challengeId = null;
        _challengePhone = null;
        _debugCode = null;
        _error = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    final challengePhone = _challengePhone;
    if (_challengeId == null || challengePhone == null) {
      return SignInPhonePage(
        phone: _phone,
        sending: _sending,
        errorText: _error,
        onSend: _sendOtp,
        onPhoneChanged: _phoneChanged,
        onBack: () => context.go("/customer"),
        shipping: true,
        onOtherSide: () => context.go("/driver/onboarding/phone"),
        newAccountLinks: {
          "Register business": () => context.go("/customer/register"),
          "Register as teammate": () => context.go("/customer/register-user"),
        },
      );
    }
    return SignInCodePage(
      phone: formatPhone(challengePhone),
      code: _code,
      verifying: _verifying,
      sendingNewCode: _sending,
      secondsUntilNewCode: _otpCooldownSeconds,
      errorText: _error,
      debugCode: _debugCode,
      onSignIn: _verify,
      onSendNewCode: _sendOtp,
      onChangeNumber: _changeNumber,
      onBack: _changeNumber,
    );
  }
}

class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class CustomerRegisterUserScreen extends StatefulWidget {
  const CustomerRegisterUserScreen({super.key});

  @override
  State<CustomerRegisterUserScreen> createState() =>
      _CustomerRegisterUserScreenState();
}

class _CustomerRegisterUserScreenState
    extends State<CustomerRegisterUserScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/users/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": digitsOnly(_phone.text.trim()),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Account created — ask your admin to invite you, then sign in.")),
      );
      context.go("/customer/login");
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Join your team",
      currentPath: "/customer/register-user",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your personal account. Your business admin will invite your phone to the org so you can book and track shared shipments.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your name")),
          TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: "Phone (10 digits)"),
              keyboardType: TextInputType.phone),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
        ],
      ),
    );
  }
}

class CustomerTeamScreen extends StatefulWidget {
  const CustomerTeamScreen({super.key});

  @override
  State<CustomerTeamScreen> createState() => _CustomerTeamScreenState();
}

class _CustomerTeamScreenState extends State<CustomerTeamScreen> {
  final _phone = TextEditingController();
  bool _loading = false;
  bool _inviting = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await CustomerSession.refresh();
    if (!mounted) return;
    if (!mounted) return;
    if (!CustomerSession.isSignedIn) {
      context.go("/customer/login");
      return;
    }
    if (!CustomerSession.isOrgAdmin) {
      setState(() => _error = "Only org admins can manage team members.");
      return;
    }
    await _loadMembers();
  }

  Future<void> _loadMembers() async {
    final orgId = CustomerSession.customerOrgId;
    if (orgId == null || orgId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api
          .get<Map<String, dynamic>>("/v1/pilot/customer/members?orgId=$orgId");
      final raw = r.data?["members"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _members = list);
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final orgId = CustomerSession.customerOrgId;
    if (orgId == null) return;
    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/members/invite",
        data: {"orgId": orgId, "phone": digitsOnly(_phone.text.trim())},
      );
      _phone.clear();
      await _loadMembers();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Teammate invited.")));
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Team",
      currentPath: "/customer/team",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            CustomerSession.customerOrgName ?? "Your organization",
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: DriverTheme.navy,
                fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Invite colleagues who have already registered their phone. They will see all org shipments after joining.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          if (!CustomerSession.isOrgAdmin) ...[
            const SizedBox(height: 12),
            Text(_error ?? "Admin access required.",
                style: const TextStyle(color: Colors.red)),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: "Teammate phone (10 digits)"),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _inviting ? null : _invite,
              child: _inviting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Invite to org"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            const Text("Members",
                style: TextStyle(fontWeight: FontWeight.w600)),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator()),
            ..._members.map((row) {
              final user = row["user"];
              final membership = row["membership"];
              if (user is! Map<String, dynamic>) return const SizedBox.shrink();
              final role = membership is Map<String, dynamic>
                  ? membership["role"]?.toString() ?? ""
                  : "";
              return Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  title: Text(user["fullName"]?.toString() ?? "—"),
                  subtitle: Text(
                      "${user["phone"]} · ${customerMemberRoleLabel(role)}"),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class CustomerIntegrationsScreen extends StatefulWidget {
  const CustomerIntegrationsScreen({super.key});

  @override
  State<CustomerIntegrationsScreen> createState() =>
      _CustomerIntegrationsScreenState();
}

class _CustomerIntegrationsScreenState
    extends State<CustomerIntegrationsScreen> {
  final _webhookUrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  bool _creatingKey = false;
  bool _testingWebhook = false;
  String? _error;
  Map<String, dynamic>? _connection;
  List<Map<String, dynamic>> _apiKeys = [];
  List<Map<String, dynamic>> _deliveries = [];
  String _paymentPolicy = "portal_checkout";

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _webhookUrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await CustomerSession.refresh();
    if (!mounted) return;
    if (!CustomerSession.isSignedIn) {
      context.go("/customer/login");
      return;
    }
    if (!CustomerSession.canManageIntegrations) {
      setState(() => _error = "Only org admins can manage ERP integrations.");
      return;
    }
    await _load();
  }

  String get _orgQuery {
    final orgId = CustomerSession.customerOrgId;
    return orgId != null && orgId.isNotEmpty ? "?orgId=$orgId" : "";
  }

  Future<void> _load() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations$_orgQuery");
      final conn = r.data?["connection"];
      if (conn is Map<String, dynamic>) {
        _connection = conn;
        _webhookUrl.text = conn["webhookUrl"]?.toString() ?? "";
        _paymentPolicy = conn["paymentPolicy"]?.toString() ?? "portal_checkout";
      }
      _apiKeys = _mapList(r.data?["apiKeys"]);
      _deliveries = _mapList(r.data?["recentDeliveries"]);
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) list.add(item);
      }
    }
    return list;
  }

  Future<void> _saveConnection({bool regenerateWebhookSecret = false}) async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await api.patch<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/connection$_orgQuery",
        data: {
          "webhookUrl": _webhookUrl.text.trim(),
          "paymentPolicy": _paymentPolicy,
          "regenerateWebhookSecret": regenerateWebhookSecret,
        },
      );
      final conn = r.data?["connection"];
      if (conn is Map<String, dynamic>) {
        _connection = conn;
        if (regenerateWebhookSecret && conn["webhookSecret"] != null) {
          await _showSecretDialog(
            title: "Webhook secret (copy now)",
            secret: conn["webhookSecret"]?.toString() ?? "",
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Integration settings saved.")));
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createApiKey() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _creatingKey = true;
      _error = null;
    });
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/keys$_orgQuery",
        data: {
          "scopes": ["loads:read", "loads:write", "webhooks:manage"]
        },
      );
      final token = r.data?["token"]?.toString() ?? "";
      if (token.isNotEmpty) {
        await _showSecretDialog(title: "API token (shown once)", secret: token);
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _creatingKey = false);
    }
  }

  Future<void> _revokeKey(String keyId) async {
    if (_orgQuery.isEmpty || keyId.isEmpty) return;
    setState(() => _error = null);
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/keys/revoke$_orgQuery",
        data: {"keyId": keyId},
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("API key revoked.")));
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  Future<void> _testWebhook() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _testingWebhook = true;
      _error = null;
    });
    try {
      final r = await api.post<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations/webhooks/test$_orgQuery");
      final ok = r.data?["ok"] == true;
      final status = r.data?["httpStatus"];
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok
                ? "Test webhook delivered (HTTP $status)."
                : "Test webhook failed (HTTP $status).")),
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _testingWebhook = false);
    }
  }

  Future<void> _retryDelivery(String deliveryId) async {
    if (_orgQuery.isEmpty) return;
    try {
      await api.post<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations/deliveries/$deliveryId/retry$_orgQuery");
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Delivery queued for retry.")));
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    }
  }

  Future<void> _showSecretDialog(
      {required String title, required String secret}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(secret,
            style: const TextStyle(fontFamily: "monospace", fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Done"))
        ],
      ),
    );
  }

  String _deliveryStatusLabel(String? status) {
    switch (status) {
      case "DELIVERED":
        return "Delivered";
      case "DEAD":
        return "Failed (dead letter)";
      case "PENDING":
      default:
        return "Pending";
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWebhookSecret = _connection?["hasWebhookSecret"] == true;

    return CustomerScaffold(
      title: "Integrations",
      currentPath: "/customer/integrations",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            CustomerSession.customerOrgName ?? "Your organization",
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: DriverTheme.navy,
                fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Connect your ERP to create loads automatically and receive carrier, tracking, and payment updates via webhooks.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            "See docs/erp-integration.md in the NaviG8r repo for field mapping and authentication details.",
            style:
                TextStyle(fontSize: 12, color: DriverTheme.muted, height: 1.35),
          ),
          if (!CustomerSession.canManageIntegrations) ...[
            const SizedBox(height: 12),
            Text(_error ?? "Admin access required.",
                style: const TextStyle(color: Colors.red)),
          ] else ...[
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
            if (!_loading) ...[
              const SizedBox(height: 16),
              const Text("Webhook callback",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _webhookUrl,
                decoration: const InputDecoration(
                  labelText: "HTTPS callback URL",
                  hintText: "https://erp.example.com/navig8r/webhook",
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _paymentPolicy,
                decoration: const InputDecoration(labelText: "Payment policy"),
                items: const [
                  DropdownMenuItem(
                      value: "portal_checkout",
                      child:
                          Text("Portal checkout (Razorpay in customer web)")),
                  DropdownMenuItem(
                      value: "erp_preauthorized",
                      child: Text(
                          "ERP pre-authorized (book without portal checkout)")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paymentPolicy = v);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _saveConnection(),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("Save settings"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _saveConnection(regenerateWebhookSecret: true),
                    child: const Text("Rotate secret"),
                  ),
                ],
              ),
              if (hasWebhookSecret)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      "Webhook HMAC secret is configured. Rotate to reveal a new secret.",
                      style: TextStyle(fontSize: 11, color: DriverTheme.muted)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testingWebhook || _webhookUrl.text.trim().isEmpty
                    ? null
                    : _testWebhook,
                icon: _testingWebhook
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 18),
                label: const Text("Send test ping"),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                      child: Text("API keys",
                          style: TextStyle(fontWeight: FontWeight.w600))),
                  FilledButton.tonal(
                    onPressed: _creatingKey ? null : _createApiKey,
                    child: _creatingKey
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Create key"),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                "Use Bearer nvg8r_{keyId}_{secret} or X-Api-Key + X-Api-Secret headers. The full token is shown only once at creation.",
                style: TextStyle(
                    fontSize: 12, color: DriverTheme.muted, height: 1.35),
              ),
              ..._apiKeys.map((k) {
                final keyId = k["keyId"]?.toString() ?? "—";
                final scopes = (k["scopes"] as List?)
                        ?.map((s) => s.toString())
                        .join(", ") ??
                    "";
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(keyId,
                        style: const TextStyle(
                            fontFamily: "monospace", fontSize: 13)),
                    subtitle: Text(scopes.isEmpty ? "—" : scopes),
                    trailing: IconButton(
                      tooltip: "Revoke",
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _revokeKey(keyId),
                    ),
                  ),
                );
              }),
              if (_apiKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("No API keys yet.",
                      style: TextStyle(color: DriverTheme.muted)),
                ),
              const SizedBox(height: 24),
              const Text("Recent webhook deliveries",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ..._deliveries.map((d) {
                final id = d["id"]?.toString() ?? "";
                final status = d["status"]?.toString();
                final attempts = d["attempts"];
                final httpStatus = d["lastHttpStatus"];
                final eventId = d["eventId"]?.toString() ?? "";
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(eventId, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      "${_deliveryStatusLabel(status)} · attempts: $attempts · HTTP: ${httpStatus ?? "—"}",
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: status != "DELIVERED"
                        ? TextButton(
                            onPressed:
                                id.isEmpty ? null : () => _retryDelivery(id),
                            child: const Text("Retry"))
                        : null,
                  ),
                );
              }),
              if (_deliveries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("No deliveries yet.",
                      style: TextStyle(color: DriverTheme.muted)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": digitsOnly(_phone.text.trim()),
          "orgDisplayName": _org.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Account created — sign in with your phone.")));
      context.go("/customer/login");
    } catch (e) {
      if (mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Register",
      currentPath: "/customer/register",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your business org. You become the admin and can invite teammates later.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your name")),
          TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: "Phone (10 digits)"),
              keyboardType: TextInputType.phone),
          TextField(
              controller: _org,
              decoration:
                  const InputDecoration(labelText: "Business / org name")),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
        ],
      ),
    );
  }
}

/// Turns typed place words into a map point. Screens take it as a parameter so tests can stand
/// in for the geocoding service.
typedef PlaceFinder = Future<GeocodeOutcome> Function(String place);

/// A pickup or drop: the words the shipper typed and the map point the price and the match use.
/// A point counts only for the words it was found for, unless the shipper dragged its pin.
class _PlaceInput {
  _PlaceInput({String words = "", this.point})
      : words = TextEditingController(text: words),
        _pointFor = point == null ? null : words.trim();

  final TextEditingController words;
  LatLng? point;
  String? _pointFor;
  bool _pinnedByHand = false;
  String? error;

  String get text => words.text.trim();
  bool get placed => point != null && (_pinnedByHand || _pointFor == text);

  void foundAt(LatLng found) {
    point = found;
    _pointFor = text;
  }

  void pinnedAt(LatLng pin) {
    point = pin;
    _pinnedByHand = true;
  }

  /// Looks up the words when they have no point yet. Sets [error] and returns false when the
  /// place cannot be used.
  Future<bool> place(PlaceFinder findPlace,
      {required String emptyError, required String notFoundError}) async {
    error = null;
    if (text.isEmpty) {
      error = emptyError;
      return false;
    }
    if (placed) return true;
    final outcome = await findPlace(text);
    if (!outcome.isOk) {
      error = notFoundError;
      return false;
    }
    foundAt(outcome.position!);
    return true;
  }

  void dispose() => words.dispose();
}

String _laneRoute(Map<String, dynamic> lane) =>
    "${lane["originCity"]} to ${lane["destCity"]}";

/// Capacity minus what is already booked, or null when the lane does not say.
num? _roomLeftKg(Map<String, dynamic> lane) {
  final capacity = lane["capacityKg"];
  final reserved = lane["reservedKg"];
  if (capacity is! num || reserved is! num) return null;
  final room = capacity - reserved;
  return room < 0 ? 0 : room;
}

String _roomLeftWords(num room) => room == 0 ? "None" : formatKg(room);

String? _laneDates(Map<String, dynamic> lane) {
  final start = DateTime.tryParse(lane["windowStart"]?.toString() ?? "");
  final end = DateTime.tryParse(lane["windowEnd"]?.toString() ?? "");
  if (start == null && end == null) return null;
  return formatDateRange(start ?? end!, end ?? start!);
}

NvStatusLabel _laneStatusLabel(String status) {
  final word = tripStatusLabel(status);
  return switch (status) {
    "OPEN" => NvStatusLabel(word, tone: NvStatusTone.good),
    "IN_PROGRESS" => NvStatusLabel(word, tone: NvStatusTone.info),
    _ => NvStatusLabel(word, tone: NvStatusTone.ended),
  };
}

/// formatApiError's own sentences, but never its "HTTP n" or server-address fallbacks.
String _plainError(Object error, String fallback) {
  if (error is! DioException || serverNeverAnswered(error)) return fallback;
  final sentence = formatApiError(error);
  return sentence.startsWith("HTTP ") || sentence.startsWith("Cannot reach")
      ? fallback
      : sentence;
}

String _apiErrorCode(Object error) {
  final body = error is DioException ? error.response?.data : null;
  return body is Map ? body["error"]?.toString() ?? "" : "";
}

void _announce(BuildContext context, String words,
        {Assertiveness assertiveness = Assertiveness.polite}) =>
    SemanticsService.announce(words, Directionality.of(context),
        assertiveness: assertiveness);

/// One lane on a list; the whole card opens Book for it.
Widget _laneCard(Map<String, dynamic> lane, {required VoidCallback onOpen}) {
  final room = _roomLeftKg(lane);
  final dates = _laneDates(lane);
  final carrier = lane["carrierDisplayName"]?.toString() ?? "Carrier";
  return Padding(
    padding: const EdgeInsets.only(top: NvSpace.s3),
    child: NvListCard(
      title: _laneRoute(lane),
      status: _laneStatusLabel(lane["status"]?.toString() ?? ""),
      subtitle:
          "$carrier · ${vehicleClassLabel(lane["vehicleClass"]?.toString())}",
      facts: [
        if (dates != null) NvFact("Dates", dates),
        if (room != null) NvFact("Room left", _roomLeftWords(room)),
      ],
      onOpen: onOpen,
    ),
  );
}

enum _LaneView { browse, match }

class CustomerTripsScreen extends StatefulWidget {
  const CustomerTripsScreen(
      {this.startWithMatch = false,
      this.findPlace = GoogleGeocodingService.forwardAddress,
      super.key});

  final bool startWithMatch;
  final PlaceFinder findPlace;

  @override
  State<CustomerTripsScreen> createState() => _CustomerTripsScreenState();
}

class _CustomerTripsScreenState extends State<CustomerTripsScreen> {
  late _LaneView _view =
      widget.startWithMatch ? _LaneView.match : _LaneView.browse;

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Find a lane",
      subtitle: "Pick a lane going your way.",
      currentPath: "/customer/trips",
      bodyBuilder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NvSpace.s2),
          SegmentedButton<_LaneView>(
            segments: const [
              ButtonSegment(value: _LaneView.browse, label: Text("Browse all")),
              ButtonSegment(
                  value: _LaneView.match, label: Text("Match my route")),
            ],
            selected: {_view},
            showSelectedIcon: false,
            onSelectionChanged: (chosen) =>
                setState(() => _view = chosen.first),
            style: ButtonStyle(
              minimumSize:
                  const WidgetStatePropertyAll(Size(0, NvSpace.targetMin)),
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
          ),
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
    _announce(context, "Loading lanes.");
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips");
      final raw = r.data?["trips"];
      if (!mounted) return;
      setState(() => _lanes =
          raw is List ? raw.whereType<Map<String, dynamic>>().toList() : []);
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
              "Every open lane, not sorted by distance. To see the closest to your route first, use Match my route.",
              style: NvText.caption),
          if (_loading) ...[
            const SizedBox(height: NvSpace.s3),
            const NvListLoadingCard(),
            const SizedBox(height: NvSpace.s3),
            const NvListLoadingCard(),
          ] else if (_failed) ...[
            const SizedBox(height: NvSpace.s3),
            NvListError(
                title: "Could not load lanes.",
                help: "Check your connection, then try again.",
                onRetry: _load),
          ] else if (_lanes.isEmpty) ...[
            const SizedBox(height: NvSpace.s3),
            const NvListEmpty(
                title: "No lanes are open right now.",
                help: "New lanes appear here when carriers publish them."),
          ] else
            for (final lane in _lanes)
              _laneCard(lane,
                  onOpen: () => context.go(Uri(
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
      {required this.findPlace, required this.onBrowseAll});
  final PlaceFinder findPlace;
  final VoidCallback onBrowseAll;

  @override
  State<_CustomerMatchTripsTab> createState() => _CustomerMatchTripsTabState();
}

class _CustomerMatchTripsTabState extends State<_CustomerMatchTripsTab> {
  final _pickup = _PlaceInput();
  final _drop = _PlaceInput();
  final _weightKg = TextEditingController();
  String? _weightError;
  bool _editing = true;
  bool _searching = false;
  bool _failed = false;
  List<Map<String, dynamic>> _lanes = [];
  // The search these results answer; a lane card carries it to Book, not whatever the fields say now.
  int? _searchedWeightKg;
  ({String words, LatLng point})? _searchedPickup;
  ({String words, LatLng point})? _searchedDrop;

  @override
  void dispose() {
    _pickup.dispose();
    _drop.dispose();
    _weightKg.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final weightKg = int.tryParse(_weightKg.text.trim()) ?? 0;
    setState(() {
      _weightError =
          weightKg <= 0 ? "Enter a weight greater than 0 kg." : null;
      _searching = true;
      _failed = false;
    });
    try {
      const notFound = "Could not find this place. Check the name and add the city.";
      final pickupPlaced = await _pickup.place(widget.findPlace,
          emptyError: "Enter the pickup place.", notFoundError: notFound);
      final dropPlaced = await _drop.place(widget.findPlace,
          emptyError: "Enter the drop place.", notFoundError: notFound);
      if (!mounted || !pickupPlaced || !dropPlaced || weightKg <= 0) return;
      final pickupPoint = _pickup.point!;
      final dropPoint = _drop.point!;
      final r = await api.get<Map<String, dynamic>>(
          "/v1/customer/eligible-anchor-trips",
          query: {
            "pickupLat": pickupPoint.latitude.toString(),
            "pickupLng": pickupPoint.longitude.toString(),
            "dropLat": dropPoint.latitude.toString(),
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
        _searchedPickup = (words: _pickup.text, point: pickupPoint);
        _searchedDrop = (words: _drop.text, point: dropPoint);
        _editing = false;
      });
      _announce(context,
          lanes.isEmpty ? _emptyTitle(weightKg) : _resultLine(lanes.length));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _resultLine(int count) =>
      "$count ${count == 1 ? "lane" : "lanes"} with room for ${formatKg(_searchedWeightKg!)}, closest to your route first.";

  String _emptyTitle(int weightKg) =>
      "No lanes pass near this route with room for ${formatKg(weightKg)}.";

  String _bookPath(Map<String, dynamic> lane) =>
      Uri(path: "/customer/book", queryParameters: {
        "anchorTripId": lane["id"]?.toString() ?? "",
        "weightKg": "$_searchedWeightKg",
        "pickup": _searchedPickup!.words,
        "pickupLat": "${_searchedPickup!.point.latitude}",
        "pickupLng": "${_searchedPickup!.point.longitude}",
        "drop": _searchedDrop!.words,
        "dropLat": "${_searchedDrop!.point.latitude}",
        "dropLng": "${_searchedDrop!.point.longitude}",
      }).toString();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
      children: _editing ? _form() : _results(),
    );
  }

  List<Widget> _form() => [
        NvField(
            label: "Pickup",
            controller: _pickup.words,
            errorText: _pickup.error),
        const SizedBox(height: NvSpace.s4),
        NvField(
            label: "Drop", controller: _drop.words, errorText: _drop.error),
        const SizedBox(height: NvSpace.s4),
        NvField(
            label: "Weight",
            controller: _weightKg,
            unit: "kg",
            keyboardType: TextInputType.number,
            errorText: _weightError),
        const SizedBox(height: NvSpace.s4),
        NvButton(
            label: "Find matching lanes",
            fullWidth: true,
            loading: _searching,
            onPressed: _search),
        if (_failed) ...[
          const SizedBox(height: NvSpace.s3),
          NvListError(
              title: "Could not load lanes.",
              help: "Check your connection, then try again.",
              onRetry: _search),
        ],
      ];

  List<Widget> _results() => [
        _SearchSummary(
          rows: [
            ("Pickup", _searchedPickup!.words),
            ("Drop", _searchedDrop!.words),
            ("Weight", formatKg(_searchedWeightKg!)),
          ],
          changeLabel: "Change",
          onChange: () => setState(() => _editing = true),
        ),
        const SizedBox(height: NvSpace.s3),
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
          for (final lane in _lanes)
            _laneCard(lane, onOpen: () => context.go(_bookPath(lane))),
        ],
      ];
}

/// What a match search or a price was for, with the one way to change it.
class _SearchSummary extends StatelessWidget {
  const _SearchSummary(
      {required this.rows, required this.changeLabel, required this.onChange});
  final List<(String, String)> rows;
  final String changeLabel;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: NvSpace.s2),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: "$label ", style: NvText.caption),
                  TextSpan(text: value, style: NvText.bodyStrong),
                ])),
              ),
            NvButton(
                label: changeLabel,
                kind: NvButtonKind.secondary,
                onPressed: onChange),
          ],
        ),
      );
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
            const Text("Try a lower weight, or browse all lanes.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s4),
            NvButton(
                label: "Change weight",
                fullWidth: true,
                onPressed: onChangeWeight),
            const SizedBox(height: NvSpace.s2),
            NvButton(
                label: "Browse all lanes",
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: onBrowseAll),
          ],
        ),
      );
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
    ({String words, LatLng point})? place(String name) {
      final words = query[name] ?? "";
      final lat = double.tryParse(query["${name}Lat"] ?? "");
      final lng = double.tryParse(query["${name}Lng"] ?? "");
      if (words.isEmpty || lat == null || lng == null) return null;
      return (words: words, point: LatLng(lat, lng));
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
  final ({String words, LatLng point})? searchedPickup;
  final ({String words, LatLng point})? searchedDrop;
  final PlaceFinder findPlace;

  @override
  State<CustomerBookShipmentScreen> createState() =>
      _CustomerBookShipmentScreenState();
}

class _CustomerBookShipmentScreenState
    extends State<CustomerBookShipmentScreen> {
  late final _weightKg =
      TextEditingController(text: widget.searchedWeightKg?.toString() ?? "");
  late final _pickup = _PlaceInput(
      words: widget.searchedPickup?.words ?? "",
      point: widget.searchedPickup?.point);
  late final _drop = _PlaceInput(
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
    _announce(context, "Price cleared. Get a new price before paying.");
  }

  void _showTooHeavy() {
    const sentence =
        "This lane does not have room for that weight. Enter a lower weight, or choose another lane.";
    setState(() {
      _quote = null;
      _weightError = sentence;
      _tooHeavy = true;
    });
    _announce(context, sentence, assertiveness: Assertiveness.assertive);
  }

  Future<void> _getPrice() async {
    final weightKg = int.tryParse(_weightKg.text.trim()) ?? 0;
    setState(() {
      _weightError =
          weightKg <= 0 ? "Enter a weight greater than 0 kg." : null;
      _tooHeavy = false;
      _actionError = null;
    });
    final room = _lane == null ? null : _roomLeftKg(_lane!);
    if (weightKg > 0 && room != null && weightKg > room) {
      _showTooHeavy();
      return;
    }
    setState(() => _pricing = true);
    try {
      const notFound =
          "Could not find this place. Check the name, or drag its pin on the map.";
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
      _announce(context,
          "Price for ${formatKg(weightKg)}: $spokenRupees rupees. This is the full price.");
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _plainError(
            error, "Could not get a price. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _pricing = false);
    }
  }

  Map<String, dynamic> _placePayload(_PlaceInput place) => {
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
      } catch (_) {}
    }
    if (!mounted) return;
    if (id != null) _openBookedShipment(id);
    _pendingShipmentIdForCheckout = null;
  }

  void _openBookedShipment(String shipmentId) {
    lastBookedShipmentId = shipmentId;
    final carrier = _lane?["carrierDisplayName"]?.toString() ?? "the carrier";
    _announce(context, "Booked. Waiting for $carrier to accept.");
    context.go("/customer/shipments/$shipmentId");
  }

  void _onCheckoutError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Payment did not go through. $message")),
    );
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
        _openBookedShipment(shipmentId);
      }
    } catch (error) {
      if (!mounted) return;
      final code = _apiErrorCode(error);
      if (code == "insufficient_capacity") {
        _showTooHeavy();
      } else if (code == "anchor_trip_not_open") {
        setState(() => _quote = null);
      } else {
        setState(() => _actionError = _plainError(
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
    return CustomerScaffold(
      title: "Book space",
      subtitle: "Check the price, then pay.",
      currentPath: "/customer/book",
      actionBar: lane == null
          ? const SizedBox.shrink()
          : NvActionBar(child: _actionBar(laneOpen)),
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
              _SearchSummary(
                rows: [
                  ("Weight", formatKg(_pricedWeightKg!)),
                  ("Pickup", _pickup.text),
                  ("Drop", _drop.text),
                ],
                changeLabel: "Change weight, pickup or drop",
                onChange: _clearPrice,
              ),
              const SizedBox(height: NvSpace.s4),
              _PriceCard(pricePaise: _pricePaise!),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _fields(Map<String, dynamic> lane) {
    final room = _roomLeftKg(lane);
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
    final room = _roomLeftKg(lane);
    final dates = _laneDates(lane);
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
          Text(_laneRoute(lane),
              style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
          const SizedBox(height: NvSpace.s1),
          Wrap(spacing: NvSpace.s1, children: [
            Text(dates == null ? carrier : "$carrier · $dates",
                style: NvText.caption),
            if (room != null)
              Text("Room left: ${_roomLeftWords(room)}",
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
    final dates = _laneDates(lane);
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
      footnote:
          "Next, you choose how to pay on the payment provider's screen.",
      choices: [
        row("Lane", _laneRoute(lane)),
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

/// Every lane the trips list returns, by id, so a list of shipments can name each by its lane's
/// route and date and tell a started trip apart: one request, not one per shipment. A lane the
/// list no longer has leaves its shipment named by the pickup and drop as typed.
Future<Map<String, Map<String, dynamic>>> loadLanesById() async {
  try {
    final r = await api.get<Map<String, dynamic>>("/anchor-trips");
    final raw = r.data?["trips"];
    return {
      if (raw is List)
        for (final lane in raw.whereType<Map<String, dynamic>>())
          if ((lane["id"]?.toString() ?? "").isNotEmpty)
            lane["id"].toString(): lane,
    };
  } catch (_) {
    return {};
  }
}

Map<String, dynamic>? laneOfShipment(Map<String, dynamic> shipment,
        Map<String, Map<String, dynamic>> lanesById) =>
    lanesById[shipment["anchorTripId"]?.toString()];

/// "Bengaluru to Chennai, 18 Oct" from the shipment's lane, else its pickup and drop as typed;
/// never its ID (spec/copy.md, "Shipment name"). Null when neither is known.
String? shipmentRouteName(Map<String, dynamic> shipment,
    {Map<String, dynamic>? lane, bool withDate = true}) {
  final from = lane?["originCity"]?.toString() ?? "";
  final to = lane?["destCity"]?.toString() ?? "";
  if (from.isNotEmpty && to.isNotEmpty) {
    final start = DateTime.tryParse(lane?["windowStart"]?.toString() ?? "");
    return withDate && start != null
        ? shipmentName(from: from, to: to, date: start)
        : "$from to $to";
  }
  final pickup = shipment["pickupAddress"]?.toString() ?? "";
  final drop = shipment["dropAddress"]?.toString() ?? "";
  return pickup.isEmpty || drop.isEmpty ? null : "$pickup to $drop";
}

String? _laneStartWords(Map<String, dynamic>? lane) {
  final start = DateTime.tryParse(lane?["windowStart"]?.toString() ?? "");
  return start == null ? null : formatDate(start);
}

String? _weightWords(Map<String, dynamic> shipment) {
  final weight = shipment["weightKg"];
  return weight is num ? formatKg(weight) : null;
}

String _carrierOf(Map<String, dynamic> shipment) {
  final name = shipment["carrierDisplayName"]?.toString() ?? "";
  return name.trim().isEmpty ? "The carrier" : name;
}

DateTime? _momentFromUtcMs(Object? value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
    : null;

/// "18 Oct, 06:10 IST".
String _dateAndTime(DateTime moment) =>
    "${formatDate(moment)}, ${formatTimeIst(moment)}";

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
    _announce(context, "Loading shipments.");
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
      _announce(context, _shipmentCount(list.length));
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

  Widget _card(Map<String, dynamic> shipment) {
    final lane = laneOfShipment(shipment, _lanesById);
    final tripStatus = lane?["status"]?.toString();
    final progress = shipmentProgress(shipment, tripStatus: tripStatus);
    final needsYou = shipperTaskFor(shipment,
            canWriteBill: AuthorizationSession.can("eway_bill.write"),
            canAddTruck: AuthorizationSession.can("eway_bill.add_truck"),
            tripStatus: tripStatus) !=
        null;
    final id = shipment["id"]?.toString() ?? "";
    final next = progress.next;
    return Padding(
      padding: const EdgeInsets.only(top: NvSpace.s3),
      child: NvListCard(
        title: shipmentRouteName(shipment, lane: lane, withDate: false) ??
            "Shipment",
        status: needsYou
            ? const NvStatusLabel("Needs you", tone: NvStatusTone.attention)
            : NvStatusLabel(progress.statusWord, tone: progress.statusTone),
        subtitle: [
          _laneStartWords(lane),
          _weightWords(shipment),
          _carrierOf(shipment),
        ].whereType<String>().join(" · "),
        next: next == null ? null : "$next.",
        needsYou: needsYou,
        onOpen: () {
          if (id.isNotEmpty) context.go("/customer/shipments/$id");
        },
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
    bool isDone(Map<String, dynamic> shipment) {
      final status = shipment["status"];
      return status == "DELIVERED" ||
          status == "PENDING_RELEASE" ||
          status == "FAILED_CARRIER_REFUNDED";
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
    return [
      if (active.isNotEmpty) ...[
        heading("Active (${active.length})"),
        for (final shipment in active) _card(shipment),
      ],
      if (done.isNotEmpty) ...[
        heading("Done"),
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
    _error = _plainError(e,
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
      setState(() => _trackingError = _plainError(e,
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
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  String get _title {
    final shipment = _shipment;
    if (shipment == null) return "Shipment";
    return shipmentRouteName(shipment, lane: _trip, withDate: false) ??
        "Shipment";
  }

  /// The amount the shipper paid: the payment's own amount, else the booking's price.
  num? get _paidPaise {
    final amount = _payment?["amountPaise"] ?? _shipment?["grossPaise"];
    return amount is num ? amount : null;
  }

  NvStep _step(ShipmentStep step, Map<String, dynamic> shipment,
      ShipmentProgress progress) {
    final carrier = _carrierOf(shipment);
    switch (step.name) {
      case ShipmentStepName.booked:
        final booked = _momentFromUtcMs(shipment["createdAtUtcMs"]);
        final paid = _paidPaise;
        final facts = [
          if (booked != null) formatDate(booked),
          if (paid != null && !progress.delivered)
            "${formatRupees(paid)} held until delivery",
        ];
        return NvStep(
            title: step.title,
            state: step.state,
            who: facts.isEmpty ? null : facts.join(" · "));
      case ShipmentStepName.carrierAccepts:
        final truck = shipment["assignedTruckNumber"]?.toString() ?? "";
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.state == NvStepState.done && truck.isNotEmpty
                ? "$carrier · Truck $truck"
                : step.who,
            panel: Text(
                "Waiting for $carrier to accept. Your payment is on hold; it is collected after delivery.",
                style: NvText.body));
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
                onSaved: _takeSavedShipment));
      case ShipmentStepName.billCheck:
        return NvStep(
            title: step.title,
            state: step.state,
            who: step.who,
            panel: const Text(
                "NaviG8r staff check the bill on the portal by hand. We will tell you if anything needs fixing.",
                style: NvText.body));
      case ShipmentStepName.onTheWay:
        final started = _momentFromUtcMs(_trip?["startedAtUtcMs"]);
        final laneStart = _laneStartWords(_trip);
        final pickup = shipment["pickupAddress"]?.toString() ?? "";
        final String sentence;
        if (progress.inTransit) {
          sentence = started == null || pickup.isEmpty
              ? "$carrier confirms when it is delivered."
              : "Left $pickup on ${formatDate(started)} at ${formatTimeIst(started)}. $carrier confirms when it is delivered.";
        } else {
          sentence = laneStart == null
              ? "Nothing for you to do now. $carrier starts the trip."
              : "Nothing for you to do now. $carrier starts the trip on $laneStart.";
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
      _weightWords(shipment),
      if (_trip != null) _laneDates(_trip!),
      _carrierOf(shipment),
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
    final paid = _paidPaise;
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
              "${_carrierOf(shipment)} confirmed delivery and added proof of delivery."
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
    final paid = _paidPaise;
    final refunded = _payment?["status"] == "REFUNDED";
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
              if (paid != null) ...[
                const SizedBox(height: NvSpace.s2),
                row("You paid", formatRupees(paid)),
                if (refunded) row("Refunded", formatRupees(paid)),
              ],
              const SizedBox(height: NvSpace.s2),
              const Text(
                  "Refunds reach your account in the time your bank or payment app takes.",
                  style: NvText.caption),
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
                  text: "Questions about this refund? ",
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

  List<Widget> _content(Map<String, dynamic> shipment) {
    final progress =
        shipmentProgress(shipment, tripStatus: _trip?["status"]?.toString());
    final map = progress.cancelled ? null : _trackingMap(shipment);
    return [
      _summary(shipment, progress),
      const SizedBox(height: NvSpace.s5),
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
    // Part 1 of the e-way bill: the portal is the shipper's one primary action, kept in view.
    final portalIsPrimary = shipment != null &&
        shipment["status"] == "BOOKED" &&
        ewayBillStageOf(shipment) == EwayBillStage.none &&
        shipperCanWriteEwayBill(shipment);
    return CustomerScaffold(
      title: _title,
      currentPath: "/customer/shipments/${widget.shipmentId}",
      actionBar: portalIsPrimary
          ? const NvActionBar(
              child: EwayBillPortalButton(
                  label: "Open the e-way bill portal",
                  kind: NvButtonKind.primary))
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
                  if (shipment != null) ..._content(shipment),
                ],
              ),
            ),
    );
  }
}
