// Size note: this file stays whole on purpose (owner decision, 12 Oct 2026). Splitting the screens waits until after
// go-live and stability, and an unrelated change should not start it.
import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:geolocator/geolocator.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "accept_booking.dart";
import "access_refresh.dart";
import "authorization_session.dart";
import "carrier_approval_banner.dart";
import "eway_bill_carrier_card.dart";
import "eway_bill_closed.dart";
import "eway_bill_words.dart";
import "driver_session.dart";
import "driver_theme.dart";
import "google_geocoding.dart";
import "location_editor.dart";
import "maps_config.dart";
import "pilot_api.dart";
import "notification_center.dart";
import "plain_error_sentence.dart";
import "signed_in_header.dart";
import "sign_in_screen.dart";
import "transporter_id_section.dart";
import "trip_assignment_card.dart";
import "ui/format.dart";
import "ui/nv_action_bar.dart";
import "ui/nv_button.dart";
import "ui/nv_choice.dart";
import "ui/nv_field.dart";
import "ui/nv_list_card.dart";
import "ui/nv_map.dart";
import "ui/nv_message.dart";
import "ui/nv_section_card.dart";
import "ui/nv_sheet.dart";
import "ui/nv_status_label.dart";
import "ui/nv_step_list.dart";
import "ui/pending_copy.dart";
import "ui/tokens.dart";
import "unassigned_driver_notice.dart";

/// Nested navigator for the driver shell (tabs + pushed detail routes).
final GlobalKey<NavigatorState> driverShellNavigatorKey =
    GlobalKey<NavigatorState>();

/// Screen title from the current driver route. A driver's home is "Today", the office's "Home".
String driverShellTitle(String path, {bool forDriver = false}) {
  if (path == "/driver") return forDriver ? "Today" : "Home";
  if (path.startsWith("/driver/shipments")) return "Bookings";
  if (path.startsWith("/driver/loads")) return "Trips";
  if (path.startsWith("/driver/publish")) return "Publish a trip";
  if (path.startsWith("/driver/track")) return "Track";
  if (path.startsWith("/driver/profile")) return forDriver ? "Profile" : "Company";
  if (path.startsWith("/driver/fleet")) return "Fleet";
  // The trip screens name themselves: "TRIP" over the route for the office, the route for a driver, and
  // "E-way bills" beside the truck.
  if (path.startsWith("/driver/trip/")) return "";
  if (path.startsWith("/driver/shipment/")) {
    // The booking screen names itself ("BOOKING" over the shipper), so the shell adds no title there.
    return path.endsWith("/pod") ? "Confirm delivery" : "";
  }
  if (path.startsWith("/driver/earnings")) return "Earnings";
  if (path.startsWith("/driver/payout-setup")) return "Payout method";
  if (path.startsWith("/driver/payout-history")) return "Payout history";
  return "NaviG8r";
}

/// Bottom-nav shell for the carrier driver journey (single instance via [ShellRoute]).
class DriverShell extends StatelessWidget {
  const DriverShell({
    required this.currentPath,
    required this.child,
    this.showBottomNav = true,
    super.key,
  });

  final String currentPath;
  final Widget child;
  final bool showBottomNav;

  // Drivers do not publish or manage bookings, so they get three tabs; the office gets five.
  static bool get _forDriver => DriverSession.carrierRole == "DRIVER";

  static const _officeTabPaths = [
    "/driver",
    "/driver/shipments",
    "/driver/loads",
    "/driver/publish",
    "/driver/profile",
  ];
  static const _driverTabPaths = [
    "/driver",
    "/driver/loads",
    "/driver/profile"
  ];

  static const _officeTabs = [
    NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: "Home"),
    NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        selectedIcon: Icon(Icons.inventory_2),
        label: "Bookings"),
    NavigationDestination(
        icon: Icon(Icons.local_shipping_outlined),
        selectedIcon: Icon(Icons.local_shipping),
        label: "Trips"),
    NavigationDestination(
        icon: Icon(Icons.add_road_outlined),
        selectedIcon: Icon(Icons.add_road),
        label: "Publish"),
    NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: "Profile"),
  ];
  static const _driverTabs = [
    NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: "Today"),
    NavigationDestination(
        icon: Icon(Icons.local_shipping_outlined),
        selectedIcon: Icon(Icons.local_shipping),
        label: "Trips"),
    NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: "Profile"),
  ];

  int _indexForPath(String path) {
    if (_forDriver) {
      // A driver opens shipments from a trip, and publish and fleet from Profile.
      if (path.startsWith("/driver/loads") ||
          path.startsWith("/driver/trip/") ||
          path.startsWith("/driver/shipment") ||
          path.startsWith("/driver/track")) {
        return 1;
      }
      if (path.startsWith("/driver/profile") ||
          path.startsWith("/driver/publish") ||
          path.startsWith("/driver/fleet") ||
          path.startsWith("/driver/earnings") ||
          path.startsWith("/driver/payout")) {
        return 2;
      }
      return 0;
    }
    if (path.startsWith("/driver/shipments") ||
        path.startsWith("/driver/shipment/")) {
      return 1;
    }
    if (path.startsWith("/driver/loads") || path.startsWith("/driver/trip/")) {
      return 2;
    }
    if (path.startsWith("/driver/publish")) return 3;
    if (path.startsWith("/driver/track")) return 3;
    if (path.startsWith("/driver/profile") ||
        path.startsWith("/driver/earnings") ||
        path.startsWith("/driver/payout")) {
      return 4;
    }
    return 0;
  }

  // The router keeps this page when only the session changes (sign-in, sign-out or a company
  // switch at the same address), so it listens to the session itself.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AuthorizationSession.revision,
      builder: (context, _) => _shell(context));

  Widget _shell(BuildContext context) {
    // Worked out here, not by the route: the route builds this page before sign-in says whether this is a driver.
    final title = driverShellTitle(currentPath, forDriver: _forDriver);
    final selected = _indexForPath(currentPath);
    final tabPaths = _forDriver ? _driverTabPaths : _officeTabPaths;
    final shellNav = Navigator.of(context);
    final canPop = shellNav.canPop();
    // Pages pushed inside the shell never show up in canPop above (that is the outer
    // navigator), so any page that is not its tab's own root gets Back. Not the
    // live trip: leaving it mid-load stops location sharing, so no one-tap exit there.
    final showBack =
        currentPath != tabPaths[selected] && !currentPath.endsWith("/active");

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Tab roots have no stack entry — back goes to driver home instead of crashing.
        if (currentPath != "/driver" && currentPath.startsWith("/driver")) {
          context.go("/driver");
        }
      },
      child: !AuthorizationSession.signedIn
          // Signed out there is only the sign-in: no header and no tabs.
          ? Scaffold(body: SafeArea(child: child))
          : Scaffold(
              appBar: signedInHeader(context,
                  backLabel: showBack ? "Back" : null,
                  onBack: showBack ? () => context.pop() : null),
              body: SafeArea(
                  child: AccessRefresh(
                child: Column(children: [
                  CarrierApprovalBanner(currentPath: currentPath),
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          NvSpace.gutter, NvSpace.s4, NvSpace.s2, NvSpace.s2),
                      child: Row(children: [
                        Expanded(
                          child: Semantics(
                              header: true,
                              child: Text(title, style: NvText.title)),
                        ),
                        // Stays until Home's "Updates" row replaces it (spec/screens.md).
                        if (AuthorizationSession.can("notification.read"))
                          const NotificationBell(),
                      ]),
                    ),
                  Expanded(child: child),
                ]),
              )),
              bottomNavigationBar: showBottomNav
                  ? NavigationBar(
                      selectedIndex: selected,
                      onDestinationSelected: (index) {
                        final target = tabPaths[index];
                        if (target != currentPath) context.go(target);
                      },
                      destinations: _forDriver ? _driverTabs : _officeTabs,
                    )
                  : null,
            ),
    );
  }
}

class DriverWelcomeScreen extends StatelessWidget {
  const DriverWelcomeScreen({super.key});

  // Listens to the session for the same reason as DriverShell: the page stays across sign-out.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: AuthorizationSession.revision,
      builder: (context, _) => _home(context));

  Widget _home(BuildContext context) {
    if (!AuthorizationSession.signedIn) return const SignInScreen();
    return DriverSession.carrierRole == "DRIVER"
        ? const _DriverToday()
        : const _OfficeHome();
  }
}

/// The API's truck sizes in words. A typed size field once showed the codes themselves.
const _truckSizes = [
  NvChoice("SMALL", "Small"),
  NvChoice("MEDIUM", "Medium"),
  NvChoice("LARGE", "Large"),
];

const _chooseTruckSizeSentence = "Choose a truck size.";

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  final _reg = TextEditingController();
  String? _truckSize;
  final _cap = TextEditingController();
  final _transporterId = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    _reg.dispose();
    _cap.dispose();
    _transporterId.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // A refusal from the last try is out of date once a new one starts, and would follow onto the code screen.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _busy = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      if (phone.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Enter a 10-digit phone number.")));
        return;
      }
      final cap = int.tryParse(_cap.text.trim()) ?? 0;
      if (cap <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Enter a positive vehicle capacity.")));
        return;
      }
      final vc = _truckSize;
      if (vc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(_chooseTruckSizeSentence)));
        return;
      }
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/driver/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": phone,
          "orgDisplayName": _org.text.trim(),
          "vehicleRegistrationNumber": _reg.text.trim(),
          "vehicleClass": vc,
          "vehicleCapacityKg": cap,
          if (_transporterId.text.trim().isNotEmpty)
            "transporterId": _transporterId.text.trim(),
        },
      );
      final orgId = orgIdFromRegisterResponse(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Carrier created — verify your phone to continue.")),
      );
      context.go("/customer/login?phone=$phone");
    } catch (e) {
      // Ten seconds because the server's sentence (what a transporter ID looks like, say) is too long to read in four.
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: "Close", onPressed: () {}),
            content: Text(plainErrorSentence(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register carrier")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Create your carrier organization and owner profile. You'll verify your phone next, then publish lanes and accept bookings.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your full name")),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: "Phone (10 digits)")),
          TextField(
              controller: _org,
              decoration: const InputDecoration(
                  labelText: "Carrier / org display name")),
          TextField(
              controller: _reg,
              decoration: const InputDecoration(
                  labelText: "Your vehicle registration")),
          const SizedBox(height: NvSpace.s3),
          NvChoiceChips<String>(
            label: "Truck size",
            options: _truckSizes,
            selected: _truckSize,
            onChanged: (size) => setState(() => _truckSize = size),
          ),
          TextField(
              controller: _cap,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: "Vehicle capacity (kg)")),
          TextField(
              controller: _transporterId,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: "Transporter ID (optional)",
                  helperText: transporterIdHelperText,
                  // Room for large text: the second sentence says shippers use the ID.
                  helperMaxLines: 10)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create carrier & continue"),
          ),
          TextButton(
              onPressed: () => context.go("/driver"),
              child: const Text("Back")),
        ],
      ),
    );
  }
}

class DriverJoinScreen extends StatefulWidget {
  const DriverJoinScreen({super.key});

  @override
  State<DriverJoinScreen> createState() => _DriverJoinScreenState();
}

class _DriverJoinScreenState extends State<DriverJoinScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/users/register",
        data: {"fullName": _fullName.text.trim(), "phone": phone},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Account created — ask your carrier admin to invite you, then sign in.")),
      );
      context.go("/customer/login");
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(plainErrorSentence(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Join a fleet")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Create a personal account so your carrier admin can invite you to their org. You do not get a carrier org from this step.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your full name")),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: "Phone (10 digits)")),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
          TextButton(
              onPressed: () => context.go("/driver"),
              child: const Text("Back")),
        ],
      ),
    );
  }
}

class DriverFleetInviteScreen extends StatefulWidget {
  const DriverFleetInviteScreen({super.key});

  @override
  State<DriverFleetInviteScreen> createState() =>
      _DriverFleetInviteScreenState();
}

class _DriverFleetInviteScreenState extends State<DriverFleetInviteScreen> {
  final _phone = TextEditingController();
  final _reg = TextEditingController();
  String? _truckSize;
  final _cap = TextEditingController();
  String? _role;
  bool _loading = true;
  bool _inviting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phone.dispose();
    _reg.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await DriverSession.refresh();
    if (!mounted) return;
    if (!DriverSession.canInviteDrivers) {
      setState(() {
        _loading = false;
        _error = "Only carrier owners and dispatchers can invite drivers.";
      });
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _invite() async {
    final orgId = DriverSession.carrierOrgId;
    if (orgId == null) return;
    final role = _role;
    if (role == null) {
      setState(() => _error = "Choose Driver or Dispatcher.");
      return;
    }
    final cap = int.tryParse(_cap.text.trim()) ?? 0;
    if (role == "DRIVER" && _truckSize == null) {
      setState(() => _error = _chooseTruckSizeSentence);
      return;
    }
    if (role == "DRIVER" && cap <= 0) {
      setState(() => _error = "Enter a positive vehicle capacity.");
      return;
    }
    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        "orgId": orgId,
        "phone": digitsOnly(_phone.text.trim()),
        "role": role,
      };
      if (role == "DRIVER") {
        payload["vehicleRegistrationNumber"] = _reg.text.trim();
        payload["vehicleClass"] = _truckSize;
        payload["vehicleCapacityKg"] = cap;
      }
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/carrier/drivers/invite",
        data: payload,
      );
      _phone.clear();
      _reg.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Driver invited to your carrier org.")));
    } catch (e) {
      if (mounted) setState(() => _error = plainErrorSentence(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DriverSession.carrierOrgName ?? "Your carrier",
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DriverTheme.navy,
              fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          "Invite a driver who already registered their phone (or used Join a fleet). Solo orgs become fleet when you add drivers.",
          style: TextStyle(color: DriverTheme.muted, height: 1.4),
        ),
        if (!DriverSession.canInviteDrivers) ...[
          const SizedBox(height: 12),
          Text(_error ?? "Not authorized.",
              style: const TextStyle(color: Colors.red)),
        ] else ...[
          const SizedBox(height: 16),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: "Driver phone (10 digits)")),
          const SizedBox(height: NvSpace.s3),
          NvChoiceChips<String>(
            label: "Role",
            options: const [
              NvChoice("DRIVER", "Driver"),
              NvChoice("DISPATCHER", "Dispatcher"),
            ],
            selected: _role,
            onChanged: (role) => setState(() => _role = role),
          ),
          if (_role == "DISPATCHER") ...[
            const SizedBox(height: 8),
            const Text(
              "Dispatchers are linked to your carrier org's primary vehicle — no separate truck registration needed.",
              style: TextStyle(
                  fontSize: 12, color: DriverTheme.muted, height: 1.35),
            ),
          ] else if (_role == "DRIVER") ...[
            TextField(
                controller: _reg,
                decoration:
                    const InputDecoration(labelText: "Vehicle registration")),
            const SizedBox(height: NvSpace.s3),
            NvChoiceChips<String>(
              label: "Truck size",
              options: _truckSizes,
              selected: _truckSize,
              onChanged: (size) => setState(() => _truckSize = size),
            ),
            TextField(
                controller: _cap,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "Vehicle capacity (kg)")),
          ],
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: () => context.push("/driver/onboarding/join"),
              child: const Text("New driver? Register account first")),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _inviting ? null : _invite,
            child: _inviting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(switch (_role) {
                    "DISPATCHER" => "Invite dispatcher",
                    "DRIVER" => "Invite driver",
                    _ => "Invite",
                  }),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ],
    );
  }
}

/// "Bengaluru to Chennai", or null when the trip is not known.
String? _tripRoute(Map<String, dynamic>? trip) {
  final from = trip?["originCity"];
  final to = trip?["destCity"];
  if (from is! String || from.isEmpty || to is! String || to.isEmpty) {
    return null;
  }
  return "$from to $to";
}

DateTime? _tripStart(Map<String, dynamic>? trip) =>
    DateTime.tryParse(trip?["windowStart"]?.toString() ?? "");

/// "18 – 19 Oct", or null when the trip is not known.
String? _tripDates(Map<String, dynamic>? trip) {
  final start = _tripStart(trip);
  if (start == null) return null;
  final end = DateTime.tryParse(trip?["windowEnd"]?.toString() ?? "");
  return end == null ? formatDate(start) : formatDateRange(start, end);
}

/// "Bengaluru to Chennai, 18 – 19 Oct", or null when the trip is not known.
String? _tripInWords(Map<String, dynamic>? trip) {
  final route = _tripRoute(trip);
  if (route == null) return null;
  final dates = _tripDates(trip);
  return dates == null ? route : "$route, $dates";
}

bool _tripStarted(Map<String, dynamic>? trip) =>
    trip?["status"] == "IN_PROGRESS" || trip?["status"] == "COMPLETED";

String _shipperName(Map<String, dynamic> booking) {
  final name = booking["customerOrgName"];
  return name is String && name.isNotEmpty ? name : "The shipper";
}

String? _weightWords(Map<String, dynamic> booking) {
  final weight = booking["weightKg"];
  return weight is num ? formatKg(weight) : null;
}

Map<String, dynamic>? _ewayBillOf(Map<String, dynamic> booking) {
  final bill = booking["ewayBill"];
  return bill is Map<String, dynamic> ? bill : null;
}

/// An accepted booking whose e-way bill the shipper made without the truck on it.
bool _truckMissingFromBill(Map<String, dynamic> booking) {
  final bill = _ewayBillOf(booking);
  final truck = bill?["truckNumber"];
  return booking["status"] == "BOOKED" &&
      bill?["kind"] == "BILL" &&
      (truck is! String || truck.isEmpty);
}

/// Owners see a booking's amounts; dispatchers and drivers do not (spec: ca-booking-dispatcher). There is no
/// owner flag, so this is the owner check the approval banner already uses: who may add the bank account.
bool get _seesPaymentAmounts =>
    DriverSession.canSetUpPayouts && AuthorizationSession.can("payment.read");

/// The status word for a booking, or null for a status the app has no word for (never the code itself).
(String, NvStatusTone)? _bookingStatus(
    Map<String, dynamic> booking, Map<String, dynamic>? trip,
    {bool onBookingScreen = false}) {
  switch (booking["status"]) {
    case "PENDING_CARRIER_ACCEPT":
      return (
        onBookingScreen ? "Waiting for you to accept" : "Waiting for you",
        NvStatusTone.attention
      );
    case "BOOKED":
      // On the booking screen its own step says the truck is missing.
      if (!onBookingScreen && _truckMissingFromBill(booking)) {
        return ("Truck not on bill", NvStatusTone.attention);
      }
      return _tripStarted(trip)
          ? ("In transit", NvStatusTone.info)
          : ("Accepted", NvStatusTone.info);
    case "PENDING_RELEASE":
      return _seesPaymentAmounts
          ? ("Awaiting payment release", NvStatusTone.attention)
          : ("Delivery confirmed", NvStatusTone.good);
    case "DELIVERED":
      return ("Delivered", NvStatusTone.good);
  }
  return null;
}

/// A label and its value on one line. A wrap, so at large text the value drops under its label instead of
/// squeezing. [identifier] sets the value in the mono face, as for a truck number.
Widget _factRow(String label, String value, {bool identifier = false}) =>
    MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s2),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: NvSpace.s4,
          runSpacing: NvSpace.s1,
          children: [
            Text(label, style: NvText.body.copyWith(color: NvColors.slate)),
            Text(value,
                style: identifier
                    ? NvText.id.copyWith(fontWeight: FontWeight.w600)
                    : NvText.bodyStrong,
                textAlign: TextAlign.end),
          ],
        ),
      ),
    );

/// Fact rows with a thin line between each.
List<Widget> _factRows(List<Widget> rows) => [
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) const Divider(height: 1, color: NvColors.line),
        row,
      ],
    ];

/// What the screen says after an accept: the truck the shipper now puts on the e-way bill, when there is one.
String _acceptedSentence(Map<String, dynamic> booking) {
  final truck = booking["assignedTruckNumber"];
  if (truck is! String || truck.isEmpty) return "Booking accepted.";
  return "Accepted with ${portalTruckNumber(truck)}. ${_shipperName(booking)} can make the e-way bill now.";
}

String _acceptRefusalSentence(Object error) => serverNeverAnswered(error)
    ? "Could not accept. Check your connection and try again."
    : _driverRefusalSentence(error);

/// Cancelled bookings stay off these screens, as before.
const _bookingStatusesShown = {
  "PENDING_CARRIER_ACCEPT",
  "BOOKED",
  "PENDING_RELEASE",
  "DELIVERED"
};

typedef _BookingsAndTrips = ({
  List<Map<String, dynamic>> bookings,
  Map<String, Map<String, dynamic>> tripsById
});

/// The carrier's bookings and its trips by id. The trips only add routes, dates and progress, so a trip list
/// that fails to load leaves them out instead of failing the screen.
Future<_BookingsAndTrips> _loadBookingsAndTrips() async {
  final response =
      await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
  final raw = response.data?["shipments"];
  final bookings = raw is List
      ? raw
          .whereType<Map<String, dynamic>>()
          .where((booking) => _bookingStatusesShown.contains(booking["status"]))
          .toList()
      : <Map<String, dynamic>>[];
  final tripsById = <String, Map<String, dynamic>>{};
  try {
    final tripsResponse =
        await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
    final rawTrips = tripsResponse.data?["trips"];
    if (rawTrips is List) {
      for (final trip in rawTrips.whereType<Map<String, dynamic>>()) {
        final id = trip["id"];
        if (id is String) tripsById[id] = trip;
      }
    }
  } catch (_) {}
  return (bookings: bookings, tripsById: tripsById);
}

/// After "Loading bookings." the list reads out how many it holds (accessibility.md, "Any list loading").
void _announceCount(BuildContext context, int count, String singular) =>
    SemanticsService.announce(
        switch (count) {
          0 => "No ${singular}s.",
          1 => "1 $singular.",
          _ => "$count ${singular}s.",
        },
        Directionality.of(context));

String _listLoadFailedWords(String what, Object error) =>
    serverNeverAnswered(error)
        ? "Could not load $what. Check your connection, then try again."
        : "Could not load $what.";

enum _BookingGroup { needsYou, active, done }

_BookingGroup _bookingGroup(Map<String, dynamic> booking) {
  final status = booking["status"];
  if (status == "PENDING_RELEASE" || status == "DELIVERED") {
    return _BookingGroup.done;
  }
  if (status == "PENDING_CARRIER_ACCEPT") return _BookingGroup.needsYou;
  return _BookingGroup.active;
}

/// The "Next:" line on a card, or null when nothing is waiting. The shipper adds the truck to the
/// e-way bill, so that card only says so (owner decision, 18 Oct 2026).
String? _bookingNextWords(Map<String, dynamic> booking) {
  if (booking["status"] == "PENDING_CARRIER_ACCEPT") {
    return "accept and choose the truck.";
  }
  if (_truckMissingFromBill(booking)) {
    return "${_shipperName(booking)} adds the truck to the e-way bill.";
  }
  return null;
}

/// The e-way bill on a booking card, in the booking's own step words, or null when there is nothing to say. A
/// bill without the truck says nothing here: the status and the "Next:" line already say the shipper adds it.
String? _ewayBillCardWords(Map<String, dynamic> booking) {
  final bill = _ewayBillOf(booking);
  if (bill?["kind"] == "NOT_NEEDED") return "E-way bill: not needed";
  final truck = bill?["truckNumber"];
  if (bill?["kind"] != "BILL" || truck is! String || truck.isEmpty) return null;
  final check = bill?["check"];
  // The same test as the booking's step list, so the card never reassures while the steps show a problem.
  final flagged = check is Map && check["result"] == "PROBLEM";
  final mismatch = ewayBillTruckMismatchSentence(booking, bill!,
          reader: TruckMismatchReader.carrierOffice) !=
      null;
  if ((flagged || mismatch) && !ewayBillIsClosed(booking)) {
    return "E-way bill has a problem";
  }
  // The same test as the bill's own lines (ewayBillTruckLines), so the card never reassures once the time has gone.
  final validUntil = bill["validUntilUtcMs"];
  if (validUntil is num &&
      validUntil.toInt() <= currentTime().millisecondsSinceEpoch &&
      !ewayBillIsClosed(booking)) {
    return "E-way bill time has passed";
  }
  return check is Map && check["result"] == "FOUND"
      ? "E-way bill checked"
      : "Truck on the e-way bill";
}

/// ca-bookings: the office's bookings under Needs you, Active and Done. A card opens its booking; Accept is
/// on the booking screen, never on the list.
class DriverShipmentsScreen extends StatefulWidget {
  const DriverShipmentsScreen({super.key});

  @override
  State<DriverShipmentsScreen> createState() => _DriverShipmentsScreenState();
}

class _DriverShipmentsScreenState extends State<DriverShipmentsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  Map<String, Map<String, dynamic>> _tripsById = {};
  bool _loading = false;
  String? _error;
  _BookingGroup _shown = _BookingGroup.needsYou;

  static const _emptyWords = {
    _BookingGroup.needsYou: "Nothing needs you right now.",
    _BookingGroup.active: "No active bookings.",
    _BookingGroup.done: "No finished bookings yet.",
  };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await _loadBookingsAndTrips();
      if (mounted) {
        setState(() {
          _bookings = loaded.bookings;
          _tripsById = loaded.tripsById;
        });
        _announceCount(context, loaded.bookings.length, "booking");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _listLoadFailedWords("bookings", e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _open(Map<String, dynamic> booking) async {
    await context.push("/driver/shipment/${booking["id"]}");
    // Accepting there moves the booking between groups.
    if (mounted) _load();
  }

  Widget _card(Map<String, dynamic> booking) {
    final trip = _tripsById[booking["anchorTripId"]];
    final status = _bookingStatus(booking, trip);
    final pickup = booking["pickupAddress"]?.toString() ?? "";
    final drop = booking["dropAddress"]?.toString() ?? "";
    final start = _tripStart(trip);
    final weight = _weightWords(booking);
    final billWords = _ewayBillCardWords(booking);
    final details = [
      if (start != null) formatDate(start),
      if (weight != null) weight,
      if (billWords != null) billWords,
    ];
    return NvListCard(
      title: _shipperName(booking),
      status: status == null
          ? null
          : NvStatusLabel(status.$1, tone: status.$2),
      subtitle: pickup.isEmpty || drop.isEmpty ? null : "$pickup to $drop",
      footnote: details.isEmpty ? null : details.join(" · "),
      next: _bookingNextWords(booking),
      needsYou: _bookingGroup(booking) == _BookingGroup.needsYou,
      onOpen: () => _open(booking),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsYouCount = _bookings
        .where((booking) => _bookingGroup(booking) == _BookingGroup.needsYou)
        .length;
    final shown =
        _bookings.where((booking) => _bookingGroup(booking) == _shown).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: [
          NvChoiceChips<_BookingGroup>(
            options: [
              NvChoice(_BookingGroup.needsYou, "Needs you ($needsYouCount)"),
              const NvChoice(_BookingGroup.active, "Active"),
              const NvChoice(_BookingGroup.done, "Done"),
            ],
            selected: _shown,
            onChanged: (group) => setState(() => _shown = group),
          ),
          const SizedBox(height: NvSpace.s4),
          if (_loading && _bookings.isEmpty) ...[
            Semantics(
                liveRegion: true,
                child: const Text("Loading bookings.", style: NvText.caption)),
            const SizedBox(height: NvSpace.s2),
            const NvListLoadingCard(),
          ] else if (_error != null)
            NvListError(title: _error!, onRetry: _load)
          else if (shown.isEmpty)
            NvListEmpty(title: _emptyWords[_shown]!),
          for (final booking in shown) ...[
            _card(booking),
            const SizedBox(height: NvSpace.s3),
          ],
        ],
      ),
    );
  }
}

/// One thing the office should do next, from its bookings and trips.
class _OfficeTask {
  const _OfficeTask(
      {required this.title,
      required this.detail,
      required this.actionLabel,
      required this.path});
  final String title;
  final String detail;
  final String actionLabel;
  final String path;
}

/// In the order they block the work: accept, then a driver for a booked trip, then start a trip that is ready.
/// The truck on the e-way bill is the shipper's to add, so it is never a task here.
/// Each kind needs the permission that does it, so nobody is sent to a task they cannot do.
List<_OfficeTask> _officeTasks(_BookingsAndTrips loaded) {
  final tasks = <_OfficeTask>[];
  if (AuthorizationSession.can("carrier.offer_accept")) {
    for (final booking in loaded.bookings
        .where((booking) => booking["status"] == "PENDING_CARRIER_ACCEPT")) {
      final trip = loaded.tripsById[booking["anchorTripId"]];
      final route = _tripRoute(trip);
      final start = _tripStart(trip);
      final weight = _weightWords(booking);
      final who =
          [_shipperName(booking), if (weight != null) weight].join(", ");
      tasks.add(_OfficeTask(
        title: "Accept a booking",
        detail: route == null
            ? "$who."
            : "$who, on your $route trip${start == null ? "" : ", ${formatDate(start)}"}.",
        actionLabel: "Review booking",
        path: "/driver/shipment/${booking["id"]}",
      ));
    }
  }
  if (AuthorizationSession.can("trip.assign")) {
    for (final trip in loaded.tripsById.values) {
      final driver = trip["assignedDriverUserId"];
      final reserved = trip["reservedKg"];
      final waitingForDriver =
          (trip["status"] == "OPEN" || trip["status"] == "FULL") &&
              reserved is num &&
              reserved > 0 &&
              (driver is! String || driver.isEmpty);
      if (!waitingForDriver) continue;
      final start = _tripStart(trip);
      tasks.add(_OfficeTask(
        title: "Assign a driver",
        detail: [
          _tripRoute(trip) ?? "Trip",
          if (start != null) formatDate(start)
        ].join(" · "),
        actionLabel: "Open trip",
        path: "/driver/trip/${trip["id"]}/active",
      ));
    }
  }
  // What the trip screen's Start trip takes (an approved carrier, an accepted booking, a driver) and also a
  // truck and a trip whose first day has come, which Start trip itself does not check.
  if (AuthorizationSession.can("load.status_update") &&
      DriverSession.complianceApproved) {
    for (final trip in loaded.tripsById.values) {
      final start = _tripStart(trip);
      final readyToStart = (trip["status"] == "OPEN" ||
              trip["status"] == "FULL") &&
          _nonEmpty(trip["assignedDriverUserId"]) != null &&
          _nonEmpty(trip["assignedTruckNumber"]) != null &&
          start != null &&
          !_dayInIndia(start).isAfter(_todayInIndia()) &&
          loaded.bookings.any((booking) =>
              booking["anchorTripId"] == trip["id"] &&
              booking["status"] == "BOOKED");
      if (!readyToStart) continue;
      tasks.add(_OfficeTask(
        title: "Start a trip",
        detail: [_tripRoute(trip) ?? "Trip", formatDate(start)].join(" · "),
        actionLabel: "Open trip",
        path: "/driver/trip/${trip["id"]}/active",
      ));
    }
  }
  return tasks;
}

/// ca-home: the office's first task with its button, the other tasks under it, then the trips on the road.
class _OfficeHome extends StatefulWidget {
  const _OfficeHome();

  @override
  State<_OfficeHome> createState() => _OfficeHomeState();
}

class _OfficeHomeState extends State<_OfficeHome> {
  _BookingsAndTrips? _loaded;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await _loadBookingsAndTrips();
      if (mounted) setState(() => _loaded = loaded);
    } catch (e) {
      if (mounted) setState(() => _error = _listLoadFailedWords("bookings", e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String path) async {
    await context.push(path);
    if (mounted) _load();
  }

  Widget _firstTask(_OfficeTask task) => Container(
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
            const SizedBox(height: NvSpace.s2),
            Text(task.title, style: NvText.heading),
            const SizedBox(height: NvSpace.s1),
            Text(task.detail, style: NvText.body),
            const SizedBox(height: NvSpace.s4),
            NvButton(
                label: task.actionLabel,
                onPressed: () => _open(task.path),
                fullWidth: true),
          ],
        ),
      );

  Widget _tripOnTheRoad(
      Map<String, dynamic> trip, List<Map<String, dynamic>> bookings) {
    final truck = trip["assignedTruckNumber"];
    final driver = trip["assignedDriverName"];
    final bookingCount = bookings
        .where((booking) => booking["anchorTripId"] == trip["id"])
        .length;
    final facts = [
      if (truck is String && truck.isNotEmpty) portalTruckNumber(truck),
      if (driver is String && driver.isNotEmpty) driver,
      bookingCount == 1 ? "1 booking" : "$bookingCount bookings",
    ];
    return NvListCard(
      title: _tripRoute(trip) ?? "Trip",
      status: const NvStatusLabel("In transit", tone: NvStatusTone.info),
      footnote: facts.join(" · "),
      onOpen: () => _open("/driver/trip/${trip["id"]}/active"),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loaded = _loaded;
    final List<Widget> content;
    if (loaded == null && _loading) {
      content = [
        Semantics(
            liveRegion: true,
            child: const Text("Loading bookings.", style: NvText.caption)),
        const SizedBox(height: NvSpace.s2),
        const NvListLoadingCard(),
      ];
    } else if (_error != null || loaded == null) {
      content = [
        NvListError(title: _error ?? "Could not load bookings.", onRetry: _load)
      ];
    } else {
      final tasks = _officeTasks(loaded);
      final onTheRoad = loaded.tripsById.values
          .where((trip) => trip["status"] == "IN_PROGRESS")
          .toList();
      content = [
        if (tasks.isEmpty)
          const NvListEmpty(title: "Nothing needs you right now.")
        else ...[
          _firstTask(tasks.first),
          for (final task in tasks.skip(1)) ...[
            const SizedBox(height: NvSpace.s3),
            NvListCard(
                title: task.title,
                subtitle: task.detail,
                onOpen: () => _open(task.path)),
          ],
        ],
        if (onTheRoad.isNotEmpty) ...[
          const SizedBox(height: NvSpace.s6),
          Semantics(
              header: true, child: const Text("Today", style: NvText.heading)),
          const SizedBox(height: NvSpace.s3),
          for (final trip in onTheRoad) ...[
            _tripOnTheRoad(trip, loaded.bookings),
            const SizedBox(height: NvSpace.s3),
          ],
        ],
      ];
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: content,
      ),
    );
  }
}

const _weekdayNames = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// Accepted bookings, the ones that ride on the truck (or did).
bool _acceptedOrDelivered(Map<String, dynamic> booking) =>
    const {"BOOKED", "PENDING_RELEASE", "DELIVERED"}
        .contains(booking["status"]);

/// dr-today: the trip to work on today with its one button, then the driver's later trips. No money anywhere.
class _DriverToday extends StatefulWidget {
  const _DriverToday();

  @override
  State<_DriverToday> createState() => _DriverTodayState();
}

class _DriverTodayState extends State<_DriverToday> {
  List<Map<String, dynamic>>? _trips;
  // Null when the bookings could not load: the card then leaves out the pickup and drop counts.
  List<Map<String, dynamic>>? _bookings;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
      final raw = response.data?["trips"];
      final trips = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      List<Map<String, dynamic>>? bookings;
      try {
        final shipments =
            await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
        final rawShipments = shipments.data?["shipments"];
        if (rawShipments is List) {
          bookings = rawShipments.whereType<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _trips = trips;
          _bookings = bookings;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _listLoadFailedWords("trips", e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> trip) async {
    await context.push("/driver/trip/${trip["id"]}/active");
    if (mounted) _load();
  }

  /// A trip on the road; otherwise the earliest one not started whose first day has come.
  static Map<String, dynamic>? _todaysTrip(List<Map<String, dynamic>> trips) {
    for (final trip in trips) {
      if (trip["status"] == "IN_PROGRESS") return trip;
    }
    final today = _todayInIndia();
    final due = trips.where((trip) {
      final start = _tripStart(trip);
      return _notStarted(trip) &&
          start != null &&
          !_dayInIndia(start).isAfter(today);
    }).toList()
      ..sort(_byStart);
    return due.isEmpty ? null : due.first;
  }

  /// Trips not started whose first day is still to come, earliest first.
  static List<Map<String, dynamic>> _laterTrips(
      List<Map<String, dynamic>> trips) {
    final today = _todayInIndia();
    return trips.where((trip) {
      final start = _tripStart(trip);
      return _notStarted(trip) &&
          start != null &&
          _dayInIndia(start).isAfter(today);
    }).toList()
      ..sort(_byStart);
  }

  static bool _notStarted(Map<String, dynamic> trip) =>
      trip["status"] == "OPEN" || trip["status"] == "FULL";

  static int _byStart(Map<String, dynamic> a, Map<String, dynamic> b) =>
      _tripStart(a)!.compareTo(_tripStart(b)!);

  Widget _todayCard(Map<String, dynamic> trip) {
    final truck = _nonEmpty(trip["assignedTruckNumber"]);
    final accepted = _bookings
        ?.where((booking) =>
            booking["anchorTripId"] == trip["id"] &&
            _acceptedOrDelivered(booking))
        .length;
    String places(int count, Object? city) =>
        _nonEmpty(city) == null ? "$count" : "$count, in $city";
    final NvStatusLabel? status;
    if (trip["status"] == "IN_PROGRESS") {
      status = const NvStatusLabel("In transit", tone: NvStatusTone.info);
    } else if (accepted != null && accepted > 0) {
      status = const NvStatusLabel("Ready to start", tone: NvStatusTone.good);
    } else {
      status = null;
    }
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: NvSpace.s2,
            runSpacing: NvSpace.s1,
            children: [
              Semantics(
                  header: true,
                  child: Text(_tripRoute(trip) ?? "Today's trip",
                      style: NvText.heading)),
              if (status != null) status,
            ],
          ),
          const SizedBox(height: NvSpace.s2),
          ..._factRows([
            if (truck != null)
              _factRow("Truck", portalTruckNumber(truck), identifier: true),
            if (accepted != null && accepted > 0) ...[
              _factRow("Pickups", places(accepted, trip["originCity"])),
              _factRow("Drops", places(accepted, trip["destCity"])),
            ],
          ]),
          const SizedBox(height: NvSpace.s4),
          NvButton(
              label: "Open today's trip",
              onPressed: () => _open(trip),
              forDriver: true,
              fullWidth: true),
        ],
      ),
    );
  }

  Widget _laterTripCard(Map<String, dynamic> trip) {
    final truck = _nonEmpty(trip["assignedTruckNumber"]);
    final details = [
      if (_tripDates(trip) != null) _tripDates(trip)!,
      if (truck != null) portalTruckNumber(truck),
    ];
    return NvListCard(
      title: _tripRoute(trip) ?? "Trip",
      subtitle: details.isEmpty ? null : details.join(" · "),
      onOpen: () => _open(trip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayInIndia();
    final trips = _trips;
    final List<Widget> content;
    if (trips == null && _loading) {
      content = [
        Semantics(
            liveRegion: true,
            child: const Text("Loading trips.", style: NvText.caption)),
        const SizedBox(height: NvSpace.s2),
        const NvListLoadingCard(),
      ];
    } else if (_error != null || trips == null) {
      content = [
        NvListError(title: _error ?? "Could not load trips.", onRetry: _load)
      ];
    } else {
      final todays = _todaysTrip(trips);
      final later = _laterTrips(trips);
      content = [
        if (todays != null)
          _todayCard(todays)
        else
          const NvListEmpty(
              title: "No trip today.",
              help: "Your office assigns trips. They appear here."),
        if (later.isNotEmpty) ...[
          const SizedBox(height: NvSpace.s6),
          Semantics(
              header: true, child: const Text("Next", style: NvText.heading)),
          const SizedBox(height: NvSpace.s3),
          for (final trip in later) ...[
            _laterTripCard(trip),
            const SizedBox(height: NvSpace.s3),
          ],
        ],
      ];
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: [
          Text("${_weekdayNames[today.weekday - 1]} ${formatDate(today)}",
              style: NvText.body),
          const SizedBox(height: NvSpace.s4),
          ...content,
        ],
      ),
    );
  }
}

class DriverShipmentDetailScreen extends StatefulWidget {
  const DriverShipmentDetailScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<DriverShipmentDetailScreen> createState() =>
      _DriverShipmentDetailScreenState();
}

/// The office sees the booking as numbered steps (ca-booking-*); a driver sees who, where and the e-way bill.
class _DriverShipmentDetailScreenState
    extends State<DriverShipmentDetailScreen> {
  Map<String, dynamic>? _shipment;
  Map<String, dynamic>? _trip;
  bool _accepting = false;
  bool _loadFailed = false;
  bool _loadNeverAnswered = false;
  bool _shipmentMissingFromList = false;

  bool get _forDriver => DriverSession.carrierRole == "DRIVER";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _accept() async {
    final shipment = _shipment;
    if (shipment == null) return;
    try {
      // Busy only once the request goes out, not while the office is choosing a truck.
      final sent = await acceptBooking(context, shipment,
          tripInWords: _tripInWords(_trip), onSending: () {
        if (mounted) setState(() => _accepting = true);
      });
      if (!sent) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_acceptedSentence(_shipment ?? shipment))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_acceptRefusalSentence(e))));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _load() async {
    Map<String, dynamic>? found;
    try {
      final r =
          await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
      final raw = r.data?["shipments"];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map<String, dynamic> && s["id"] == widget.shipmentId) {
            found = s;
            break;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _loadNeverAnswered = serverNeverAnswered(e);
          _shipmentMissingFromList = false;
        });
      }
      return;
    }
    if (!mounted) return;
    if (found == null) {
      setState(() {
        _loadFailed = true;
        _loadNeverAnswered = false;
        _shipmentMissingFromList = true;
        // Otherwise a driver keeps a stale screen offering actions on a shipment that is no longer theirs.
        if (_forDriver) _shipment = null;
      });
      return;
    }
    setState(() => _shipment = found);
    if (!_forDriver) await _loadTrip(found);
  }

  Future<void> _loadTrip(Map<String, dynamic> shipment) async {
    final tripId = shipment["anchorTripId"];
    if (tripId is! String || tripId.isEmpty) return;
    try {
      final response =
          await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips/$tripId");
      final trip = response.data?["trip"];
      if (mounted && trip is Map<String, dynamic>) setState(() => _trip = trip);
    } catch (_) {
      // The trip only adds its route, dates, room and progress; the booking reads without them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shipment;
    if (s == null && _loadFailed) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(NvSpace.gutter),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              _shipmentMissingFromList && _forDriver
                  ? "This booking is not on a trip assigned to you now. Go back and pull down on Trips to refresh."
                  : _loadNeverAnswered
                      ? "Could not load this shipment. Check your connection and try again."
                      : "Could not load this shipment.",
              style: NvText.body,
              textAlign: TextAlign.center),
          // A driver's retry would ask the same list, which has already answered without this shipment; the office
          // keeps its button as before.
          if (!_shipmentMissingFromList || !_forDriver)
            NvButton(
                label: "Try again",
                kind: NvButtonKind.quiet,
                onPressed: () {
                  setState(() => _loadFailed = false);
                  _load();
                }),
        ]),
      ));
    }
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return _forDriver ? _driverView(s) : _officeView(s);
  }

  /// A driver's view of one booking on their trip: who, where, the e-way bill, and the one thing to do now held
  /// at the bottom. A driver may still accept (the API lets them), so Accept stays. No amounts.
  Widget _driverView(Map<String, dynamic> s) {
    final status = s["status"]?.toString() ?? "";
    final statusWords = _bookingStatus(s, null, onBookingScreen: true);
    final pickup = _nonEmpty(s["pickupAddress"]);
    final drop = _nonEmpty(s["dropAddress"]);
    final weight = _weightWords(s);
    final String? cannotAcceptReason;
    if (!DriverSession.complianceApproved) {
      cannotAcceptReason = "You can accept once NaviG8r approves your company.";
    } else if (!AuthorizationSession.can("carrier.offer_accept")) {
      cannotAcceptReason = "Your role cannot accept bookings.";
    } else {
      cannotAcceptReason = null;
    }
    final Widget? action = switch (status) {
      "PENDING_CARRIER_ACCEPT" => NvButton(
          label: "Accept booking",
          loading: _accepting,
          loadingLabel: "Accepting",
          onPressed: cannotAcceptReason == null ? _accept : null,
          disabledReason: cannotAcceptReason,
          forDriver: true,
          fullWidth: true),
      "BOOKED" when AuthorizationSession.can("pod.upload") => NvButton(
          label: "Confirm delivery",
          onPressed: _confirmDelivery,
          forDriver: true,
          fullWidth: true),
      _ => null,
    };
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, NvSpace.s4, NvSpace.gutter, NvSpace.s6),
            children: [
              Semantics(
                  header: true,
                  child: Text(_shipperName(s), style: NvText.title)),
              if (statusWords != null) ...[
                const SizedBox(height: NvSpace.s2),
                Align(
                    alignment: Alignment.centerLeft,
                    child:
                        NvStatusLabel(statusWords.$1, tone: statusWords.$2)),
              ],
              const SizedBox(height: NvSpace.s2),
              ..._factRows([
                if (pickup != null) _factRow("Pickup", pickup),
                if (drop != null) _factRow("Drop", drop),
                if (weight != null) _factRow("Weight", weight),
              ]),
              const SizedBox(height: NvSpace.s4),
              NvSectionCard(title: "E-way bill", children: [
                const SizedBox(height: NvSpace.s2),
                EwayBillCarrierCard(shipment: s),
              ]),
              if (AuthorizationSession.can("conversation.read")) ...[
                const SizedBox(height: NvSpace.s4),
                NvButton(
                    label: "Messages",
                    kind: NvButtonKind.secondary,
                    forDriver: true,
                    fullWidth: true,
                    onPressed: () =>
                        openShipmentConversation(context, widget.shipmentId)),
              ],
            ],
          ),
        ),
      ),
      if (action != null) NvActionBar(child: action),
    ]);
  }

  Future<void> _confirmDelivery() async {
    final confirmed =
        await context.push<bool>("/driver/shipment/${widget.shipmentId}/pod");
    if (!mounted) return;
    if (confirmed == true) {
      // Owners only: dispatchers and drivers are not told about payments (ca-booking-dispatcher).
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_seesPaymentAmounts
              ? "Delivery confirmed. Payment will be released after ops review."
              : "Delivery confirmed.")));
    }
    // Confirming delivery changes the status, so the button must not stay on offer.
    _load();
  }

  Widget _officeView(Map<String, dynamic> s) {
    final status = s["status"]?.toString() ?? "";
    final delivered = status == "PENDING_RELEASE" || status == "DELIVERED";
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, NvSpace.s4, NvSpace.gutter, NvSpace.s6),
        children: [
          _summaryCard(s),
          const SizedBox(height: NvSpace.s4),
          NvStepList(
              steps: _officeSteps(s), listName: "Steps for this booking"),
          if (_seesPaymentAmounts)
            ..._paymentBlock(s)
          else if (delivered) ...[
            const SizedBox(height: NvSpace.s5),
            _nothingMoreForYou(status),
          ],
          if (AuthorizationSession.can("conversation.read")) ...[
            const SizedBox(height: NvSpace.s5),
            NvButton(
                label: "Messages",
                kind: NvButtonKind.secondary,
                fullWidth: true,
                onPressed: () =>
                    openShipmentConversation(context, widget.shipmentId)),
          ],
        ],
      ),
    );
  }

  /// "BOOKING" over the shipper, the status, and before acceptance the facts the office decides on.
  Widget _summaryCard(Map<String, dynamic> s) {
    final status = _bookingStatus(s, _trip, onBookingScreen: true);
    final statusLabel =
        status == null ? null : NvStatusLabel(status.$1, tone: status.$2);
    final pickup = s["pickupAddress"]?.toString() ?? "";
    final drop = s["dropAddress"]?.toString() ?? "";
    final weight = _weightWords(s);
    final List<Widget> details;
    if (s["status"] == "PENDING_CARRIER_ACCEPT") {
      final billKind = _ewayBillOf(s)?["kind"];
      final facts = [
        if (pickup.isNotEmpty) ("Pickup", pickup),
        if (drop.isNotEmpty) ("Drop", drop),
        if (weight != null) ("Weight", weight),
        if (billKind == "BILL")
          ("E-way bill", "Needed. ${_shipperName(s)} makes it."),
        if (billKind == "NOT_NEEDED")
          ("E-way bill", "Not needed (shipper said so)."),
      ];
      details = [
        if (statusLabel != null)
          Align(alignment: Alignment.centerLeft, child: statusLabel),
        for (final (index, (label, value)) in facts.indexed) ...[
          if (index > 0) const Divider(height: 1, color: NvColors.line),
          _factRow(label, value),
        ],
      ];
    } else {
      final start = _tripStart(_trip);
      final summary = [
        if (pickup.isNotEmpty && drop.isNotEmpty) "$pickup to $drop",
        if (weight != null) weight,
        if (start != null) formatDate(start),
      ].join(" · ");
      details = [
        Wrap(
          spacing: NvSpace.s2,
          runSpacing: NvSpace.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (statusLabel != null) statusLabel,
            if (summary.isNotEmpty) Text(summary, style: NvText.caption),
          ],
        ),
      ];
    }
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
        color: NvColors.card,
        borderRadius: BorderRadius.circular(NvRadius.card),
        border: Border.all(color: NvColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("BOOKING", style: NvText.label),
          const SizedBox(height: NvSpace.s1),
          Semantics(
              header: true, child: Text(_shipperName(s), style: NvText.title)),
          const SizedBox(height: NvSpace.s2),
          ...details,
        ],
      ),
    );
  }

  List<NvStep> _officeSteps(Map<String, dynamic> s) {
    final status = s["status"]?.toString() ?? "";
    final pending = status == "PENDING_CARRIER_ACCEPT";
    final delivered = status == "PENDING_RELEASE" || status == "DELIVERED";
    final truck = s["assignedTruckNumber"];
    return [
      if (pending)
        NvStep(
            title: "Accept and choose the truck",
            who: "You",
            state: NvStepState.yours,
            panel: _acceptPanel())
      else
        NvStep(
            title: truck is String && truck.isNotEmpty
                ? "Accepted with ${portalTruckNumber(truck)}"
                : "Accepted",
            state: NvStepState.done),
      _billStep(s, pending: pending, delivered: delivered),
      _tripStep(pending: pending, delivered: delivered),
      _deliveryStep(s, delivered: delivered),
      if (_seesPaymentAmounts)
        switch (status) {
          "DELIVERED" => const NvStep(
              title: "Payment released",
              who: "NaviG8r operations",
              state: NvStepState.done),
          "PENDING_RELEASE" => const NvStep(
              title: "Payment release",
              who: "NaviG8r operations",
              state: NvStepState.waiting),
          _ => const NvStep(
              title: "Payment released",
              who: "NaviG8r operations",
              state: NvStepState.later),
        }
      // After delivery a dispatcher reads "Nothing more for you to do" instead of the payment step.
      else if (!delivered)
        const NvStep(
            title: "Payment released",
            who: "NaviG8r operations",
            state: NvStepState.later),
    ];
  }

  /// ca-booking-new: the trip and the room it leaves, then Accept. There is no decline endpoint, so no Decline.
  Widget _acceptPanel() {
    final route = _tripRoute(_trip);
    final dates = _tripDates(_trip);
    final capacity = _trip?["capacityKg"];
    final reserved = _trip?["reservedKg"];
    // The server reserves a booking's weight when it is booked, so the room left already counts this one.
    final roomLeft =
        capacity is num && reserved is num ? capacity - reserved : null;
    final onTrip = route == null
        ? null
        : [
            "On your trip $route${dates == null ? "" : ", $dates"}.",
            if (roomLeft != null && roomLeft >= 0)
              "After this, ${formatKg(roomLeft)} of room is left.",
          ].join(" ");
    final String? cannotAcceptReason;
    if (!DriverSession.complianceApproved) {
      cannotAcceptReason = "You can accept once NaviG8r approves your company.";
    } else if (!AuthorizationSession.can("carrier.offer_accept")) {
      cannotAcceptReason = "Your role cannot accept bookings.";
    } else {
      cannotAcceptReason = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onTrip != null) ...[
          Text(onTrip, style: NvText.body),
          const SizedBox(height: NvSpace.s3),
        ],
        NvButton(
          label: "Accept",
          loading: _accepting,
          loadingLabel: "Accepting",
          onPressed: cannotAcceptReason == null ? _accept : null,
          disabledReason: cannotAcceptReason,
          fullWidth: true,
        ),
      ],
    );
  }

  NvStep _billStep(Map<String, dynamic> s,
      {required bool pending, required bool delivered}) {
    const title = "Truck on the e-way bill";
    final shipper = _shipperName(s);
    if (pending) {
      return NvStep(title: title, who: shipper, state: NvStepState.later);
    }
    final bill = _ewayBillOf(s);
    final card = EwayBillCarrierCard(shipment: s);
    if (bill == null) {
      return NvStep(
          title: title,
          who: shipper,
          state: delivered ? NvStepState.later : NvStepState.waiting,
          panel: card);
    }
    if (bill["kind"] == "NOT_NEEDED") {
      return const NvStep(
          title: "E-way bill",
          who: "Not needed (shipper said so).",
          state: NvStepState.done);
    }
    if (_truckMissingFromBill(s)) {
      return NvStep(
          title: title, who: shipper, state: NvStepState.waiting, panel: card);
    }
    final check = bill["check"];
    final flagged = check is Map && check["result"] == "PROBLEM";
    final mismatch = ewayBillTruckMismatchSentence(s, bill,
            reader: TruckMismatchReader.carrierOffice) !=
        null;
    // Only the shipper can fix the bill; a wrong truck on the trip is the office's own to change.
    if ((flagged || mismatch) && !ewayBillIsClosed(s)) {
      return NvStep(
          title: title,
          who: flagged ? shipper : "You or $shipper",
          state: NvStepState.problem,
          panel: card);
    }
    final number = bill["billNumber"];
    final validUntil = bill["validUntilUtcMs"];
    final checked = check is Map && check["result"] == "FOUND";
    final validWords = validUntil is num
        ? () {
            final moment = DateTime.fromMillisecondsSinceEpoch(
                validUntil.toInt(),
                isUtc: true);
            return "valid until ${formatDate(moment)}, ${formatTimeIst(moment)}";
          }()
        : null;
    final who = [
      if (number is String && number.isNotEmpty) formatBillNumber(number),
      if (checked && validWords != null) validWords,
      if (!checked) ewayBillCheckLine(bill, forShipper: false),
    ];
    return NvStep(
        title: checked ? "E-way bill checked" : title,
        who: who.isEmpty ? null : who.join(" · "),
        state: NvStepState.done);
  }

  /// Assigning the driver and starting happen on the trip screen, so this step opens it.
  NvStep _tripStep({required bool pending, required bool delivered}) {
    const title = "Driver assigned and trip started";
    final trip = _trip;
    if (delivered || _tripStarted(trip)) {
      final driver = trip?["assignedDriverName"];
      final startedAt = trip?["startedAtUtcMs"];
      final moment = startedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(startedAt.toInt(), isUtc: true)
          : null;
      final who = [
        if (driver is String && driver.isNotEmpty) driver,
        if (moment != null) "${formatDate(moment)}, ${formatTimeIst(moment)}",
      ];
      return NvStep(
          title: "Trip started",
          who: who.isEmpty ? null : who.join(" · "),
          state: NvStepState.done);
    }
    if (pending || trip == null) {
      return const NvStep(title: title, who: "You", state: NvStepState.later);
    }
    return NvStep(
      title: title,
      who: "You",
      state: NvStepState.yours,
      panel: NvButton(
          label: "Open trip",
          kind: NvButtonKind.secondary,
          fullWidth: true,
          onPressed: () async {
            await context.push("/driver/trip/${trip["id"]}/active");
            if (mounted) _load();
          }),
    );
  }

  /// Confirming opens today's proof of delivery screen (notes, no photo). It is offered once the trip is on the
  /// road, or whenever the trip could not be read, since the server accepts it for any accepted booking.
  NvStep _deliveryStep(Map<String, dynamic> s, {required bool delivered}) {
    const title = "Confirm delivery";
    if (delivered) {
      final podAt = s["podAtUtcMs"];
      final moment = podAt is num
          ? DateTime.fromMillisecondsSinceEpoch(podAt.toInt(), isUtc: true)
          : null;
      return NvStep(
          title: "Delivery confirmed",
          who: moment == null
              ? null
              : "${formatDate(moment)}, ${formatTimeIst(moment)} · Proof of delivery added",
          state: NvStepState.done);
    }
    final driver = _trip?["assignedDriverName"];
    final who = driver is String && driver.isNotEmpty
        ? "You or $driver"
        : "You or your driver";
    final canConfirm = s["status"] == "BOOKED" &&
        AuthorizationSession.can("pod.upload") &&
        (_trip == null || _tripStarted(_trip));
    if (!canConfirm) {
      return NvStep(title: title, who: who, state: NvStepState.later);
    }
    return NvStep(
      title: title,
      who: who,
      state: NvStepState.yours,
      panel: NvButton(
          label: "Confirm delivery",
          onPressed: _confirmDelivery,
          fullWidth: true),
    );
  }

  /// ca-booking-owner, with only the amount the carrier API sends: "You receive". The shipper's price, the
  /// commission and the bank account's last digits are not sent to carriers.
  List<Widget> _paymentBlock(Map<String, dynamic> s) {
    final awaitingRelease = s["status"] == "PENDING_RELEASE";
    final amount = s["netToCarrierPaise"];
    if (!awaitingRelease && amount is! num) return const [];
    return [
      const SizedBox(height: NvSpace.s5),
      Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (awaitingRelease)
              const Text(
                  "NaviG8r operations check the proof of delivery, then release the payment to your bank account.",
                  style: NvText.body),
            if (awaitingRelease && amount is num)
              const SizedBox(height: NvSpace.s3),
            if (amount is num)
              Row(children: [
                const Expanded(
                    child: Text("You receive", style: NvText.bodyStrong)),
                Text(formatRupees(amount), style: NvText.bodyStrong),
              ]),
          ],
        ),
      ),
      const SizedBox(height: NvSpace.s2),
      const Text(
          "Only owners see payment amounts. Dispatchers and drivers do not.",
          style: NvText.caption),
    ];
  }

  /// ca-booking-dispatcher: delivered, and no amounts.
  Widget _nothingMoreForYou(String status) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
          color: NvColors.sunken,
          borderRadius: BorderRadius.circular(NvRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Nothing more for you to do on this booking.",
                style: NvText.bodyStrong),
            if (status == "PENDING_RELEASE") ...[
              const SizedBox(height: NvSpace.s1),
              const Text(
                  "NaviG8r operations check the proof of delivery. The owner sees the payment.",
                  style: NvText.body),
            ],
          ],
        ),
      );
}

String? _nonEmpty(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

enum _TripGroup { open, inTransit, done }

_TripGroup? _tripGroup(Map<String, dynamic> trip) => switch (trip["status"]) {
      "OPEN" || "FULL" => _TripGroup.open,
      "IN_PROGRESS" => _TripGroup.inTransit,
      "COMPLETED" => _TripGroup.done,
      _ => null,
    };

/// The status word for a trip, or null for a status the app has no word for (never the code itself).
NvStatusLabel? _tripStatusLabel(Map<String, dynamic>? trip) =>
    switch (trip?["status"]) {
      "OPEN" => const NvStatusLabel("Open", tone: NvStatusTone.good),
      "FULL" => const NvStatusLabel("Full", tone: NvStatusTone.ended),
      "IN_PROGRESS" =>
        const NvStatusLabel("In transit", tone: NvStatusTone.info),
      "COMPLETED" => const NvStatusLabel("Done", tone: NvStatusTone.ended),
      _ => null,
    };

/// Kilograms the trip can still take, or null when the trip does not say its capacity.
num? _roomLeftKg(Map<String, dynamic>? trip) {
  final capacity = trip?["capacityKg"];
  if (capacity is! num) return null;
  final reserved = trip?["reservedKg"];
  final room = capacity - (reserved is num ? reserved : 0);
  return room < 0 ? 0 : room;
}

/// "Medium truck", or null for a size the app has no word for.
String? _truckSizeWords(Object? size) =>
    const ["SMALL", "MEDIUM", "LARGE"].contains(size)
        ? vehicleClassLabel(size as String)
        : null;

/// ca-trips: the carrier's trips under Open, In transit and Done. A card opens its trip; Start is on the trip
/// screen only, behind a confirm sheet, since a slip on the list once started trips.
class DriverLoadsScreen extends StatefulWidget {
  const DriverLoadsScreen({super.key});

  @override
  State<DriverLoadsScreen> createState() => _DriverLoadsScreenState();
}

class _DriverLoadsScreenState extends State<DriverLoadsScreen> {
  List<Map<String, dynamic>> _trips = [];
  // Null when the bookings could not load: the cards then leave the count out rather than show 0.
  Map<String, int>? _bookingCounts;
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  _TripGroup _shown = _TripGroup.open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DriverSession.refresh();
      final response =
          await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
      final raw = response.data?["trips"];
      final trips = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      // Newest first, as before.
      trips.sort((a, b) {
        final first = a["createdAtUtcMs"];
        final second = b["createdAtUtcMs"];
        return first is num && second is num ? second.compareTo(first) : 0;
      });
      final counts = await _bookingCountsByTrip();
      if (mounted) {
        setState(() {
          _trips = trips;
          _bookingCounts = counts;
          _loaded = true;
        });
        _announceCount(context, trips.length, "trip");
      }
    } catch (e) {
      if (mounted) setState(() => _error = _listLoadFailedWords("trips", e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static Future<Map<String, int>?> _bookingCountsByTrip() async {
    try {
      final response =
          await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
      final raw = response.data?["shipments"];
      if (raw is! List) return null;
      final counts = <String, int>{};
      for (final booking in raw.whereType<Map<String, dynamic>>()) {
        final tripId = booking["anchorTripId"];
        if (tripId is String &&
            _bookingStatusesShown.contains(booking["status"])) {
          counts[tripId] = (counts[tripId] ?? 0) + 1;
        }
      }
      return counts;
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(Map<String, dynamic> trip) async {
    await context.push("/driver/trip/${trip["id"]}/active");
    // Assigning or starting there moves the trip between groups.
    if (mounted) _load();
  }

  String? _truckAndDriverWords(Map<String, dynamic> trip) {
    final truck = _nonEmpty(trip["assignedTruckNumber"]);
    final driver = _nonEmpty(trip["assignedDriverName"]);
    if (truck != null) {
      return "${portalTruckNumber(truck)} · ${driver ?? "No driver yet"}";
    }
    if (_tripGroup(trip) == _TripGroup.open) {
      return "Truck chosen when you accept the first booking";
    }
    return driver;
  }

  Widget _card(Map<String, dynamic> trip) {
    final status = _tripStatusLabel(trip);
    final dates = _tripDates(trip);
    final room = _roomLeftKg(trip);
    final counts = _bookingCounts;
    return NvListCard(
      title: _tripRoute(trip) ?? "Trip",
      status: status,
      facts: [
        if (dates != null) NvFact("Dates", dates),
        if (room != null)
          NvFact("Room left", room == 0 ? "None" : formatKg(room)),
        if (counts != null) NvFact("Bookings", "${counts[trip["id"]] ?? 0}"),
      ],
      footnote: _truckAndDriverWords(trip),
      onOpen: () => _open(trip),
    );
  }

  Widget _empty() => switch (_shown) {
        _TripGroup.open => NvListEmpty(
            title: "No open trips.",
            help: AuthorizationSession.can("trip.publish") &&
                    DriverSession.carrierRole != "DRIVER"
                ? "Shippers can book space on a trip once it is published."
                : null),
        _TripGroup.inTransit => const NvListEmpty(title: "No trips in transit."),
        _TripGroup.done => const NvListEmpty(title: "No finished trips yet."),
      };

  @override
  Widget build(BuildContext context) {
    final shown = _trips.where((trip) => _tripGroup(trip) == _shown).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: [
          NvChoiceChips<_TripGroup>(
            options: const [
              NvChoice(_TripGroup.open, "Open"),
              NvChoice(_TripGroup.inTransit, "In transit"),
              NvChoice(_TripGroup.done, "Done"),
            ],
            selected: _shown,
            onChanged: (group) => setState(() => _shown = group),
          ),
          const SizedBox(height: NvSpace.s4),
          if (_loading && !_loaded) ...[
            Semantics(
                liveRegion: true,
                child: const Text("Loading trips.", style: NvText.caption)),
            const SizedBox(height: NvSpace.s2),
            const NvListLoadingCard(),
          ] else if (_error != null)
            NvListError(title: _error!, onRetry: _load)
          // The server shows a driver only their own trips, so for a driver none at all means none assigned yet.
          else if (_trips.isEmpty && DriverSession.carrierRole == "DRIVER")
            const UnassignedDriverNotice()
          else if (shown.isEmpty)
            _empty(),
          for (final trip in shown) ...[
            _card(trip),
            const SizedBox(height: NvSpace.s3),
          ],
        ],
      ),
    );
  }
}

class DriverTrackScreen extends StatefulWidget {
  const DriverTrackScreen({super.key});

  @override
  State<DriverTrackScreen> createState() => _DriverTrackScreenState();
}

class _DriverTrackScreenState extends State<DriverTrackScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
      final raw = r.data?["trips"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic> &&
              (item["reservedKg"] as num? ?? 0) > 0 &&
              item["status"]?.toString() == "IN_PROGRESS") {
            list.add(item);
          }
        }
      }
      if (!mounted) return;
      setState(() => _trips = list);
    } catch (e) {
      if (mounted) setState(() => _error = plainErrorSentence(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: [
          const Text(
              "Trips in transit with bookings on them. Open one to see it on the map.",
              style: NvText.body),
          const SizedBox(height: NvSpace.s4),
          if (_error != null) ...[
            NvMessage(_error!, tone: NvMessageTone.problem),
            const SizedBox(height: NvSpace.s3),
          ],
          if (_loading && _trips.isEmpty) const NvListLoadingCard(),
          for (final trip in _trips) ...[
            NvListCard(
              title: _tripRoute(trip) ?? "Trip",
              status: _tripStatusLabel(trip),
              footnote: trip["reservedKg"] is num
                  ? "${formatKg(trip["reservedKg"] as num)} booked"
                  : null,
              onOpen: () => context.push("/driver/trip/${trip["id"]}/active"),
            ),
            const SizedBox(height: NvSpace.s3),
          ],
        ],
      ),
    );
  }
}

/// ca-profile: the company's transporter ID, trucks, drivers, bank details (owner only) and team; the office signs
/// out from the account menu under the header. dr-profile: a driver sees who they are, Sign out and their truck.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  bool _loaded = false;
  List<Map<String, dynamic>> _fleetTrucks = [];
  List<Map<String, dynamic>> _fleetDrivers = [];
  bool _fleetLoaded = false;

  // Holding trip.assign is what makes a login the carrier office, and what lets it read the fleet.
  bool get _office => AuthorizationSession.can("trip.assign");

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DriverSession.refresh();
    if (!mounted) return;
    var fleetLoaded = false;
    var trucks = <Map<String, dynamic>>[];
    var drivers = <Map<String, dynamic>>[];
    if (_office) {
      try {
        final response =
            await api.get<Map<String, dynamic>>("/v1/pilot/carrier/fleet");
        final rawTrucks = response.data?["vehicles"];
        final rawDrivers = response.data?["drivers"];
        trucks = rawTrucks is List
            ? rawTrucks.whereType<Map<String, dynamic>>().toList()
            : trucks;
        drivers = rawDrivers is List
            ? rawDrivers.whereType<Map<String, dynamic>>().toList()
            : drivers;
        fleetLoaded = true;
      } catch (_) {
        // The page reads without the fleet: the person's own truck still shows.
      }
    }
    if (!mounted) return;
    setState(() {
      _fleetTrucks = trucks;
      _fleetDrivers = drivers;
      _fleetLoaded = fleetLoaded;
      _loaded = true;
    });
  }

  Future<void> _editOwnTruck() async {
    final saved = await showNvSheet<bool>(
        context: context, builder: (_) => const _TruckSheet());
    if (saved == true && mounted) await _load();
  }

  /// One truck: its number in the mono face and its size. Only the person's own truck opens, because the one
  /// truck the app can change is their own (PATCH /v1/pilot/me/vehicle).
  Widget _truckRow(String registration, Object? size, {VoidCallback? onOpen}) {
    final sizeWords = _truckSizeWords(size);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: NvSpace.targetMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s2),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(portalTruckNumber(registration),
                  style: NvText.id.copyWith(fontWeight: FontWeight.w600)),
              if (sizeWords != null) Text(sizeWords, style: NvText.caption),
            ]),
          ),
          if (onOpen != null)
            const ExcludeSemantics(
                child: Icon(Icons.chevron_right, color: NvColors.slate)),
        ]),
      ),
    );
    if (onOpen == null) return MergeSemantics(child: row);
    return MergeSemantics(
        child: Semantics(
            button: true, child: InkWell(onTap: onOpen, child: row)));
  }

  Widget _trucks() {
    final ownId = DriverSession.vehicleId;
    final ownRegistration = DriverSession.vehicleRegistrationNumber;
    final rows = <Widget>[];
    if (_fleetLoaded) {
      for (final truck in _fleetTrucks) {
        final registration = _nonEmpty(truck["registrationNumber"]);
        if (registration == null) continue;
        final own = ownId != null && truck["id"] == ownId;
        rows.add(_truckRow(registration, truck["vehicleClass"],
            onOpen: own ? _editOwnTruck : null));
      }
    } else if (ownRegistration != null && ownRegistration.isNotEmpty) {
      rows.add(_truckRow(ownRegistration, DriverSession.vehicleClass,
          onOpen: _editOwnTruck));
    }
    // A failed fleet load shows no count and no "no trucks", which would read as an empty fleet.
    final fleetFailed = _office && !_fleetLoaded;
    return NvSectionCard(
      title: !_office
          ? "Your truck"
          : fleetFailed
              ? "Trucks"
              : "Trucks (${rows.length})",
      children: [
        const SizedBox(height: NvSpace.s2),
        if (rows.isEmpty && !fleetFailed) ...[
          const Text("You have no trucks yet.", style: NvText.body),
          if (DriverSession.canInviteDrivers)
            const Text("A truck is added with its driver: use Add driver.",
                style: NvText.caption),
        ],
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) const Divider(height: 1, color: NvColors.line),
          row,
        ],
        if (fleetFailed) _fleetLoadFailed("Could not load your trucks."),
      ],
    );
  }

  Widget _fleetLoadFailed(String sentence) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: NvSpace.s2),
          Text(sentence, style: NvText.caption),
          NvButton(
              label: "Try again", kind: NvButtonKind.quiet, onPressed: _load),
        ],
      );

  Widget _drivers() {
    final names = _fleetDrivers
        .map((driver) => _nonEmpty(driver["displayName"]))
        .whereType<String>()
        .toList();
    return NvSectionCard(
      title: _fleetLoaded ? "Drivers (${names.length})" : "Drivers",
      action: DriverSession.canInviteDrivers
          ? NvButton(
              label: "Add driver",
              kind: NvButtonKind.secondary,
              onPressed: () => context.push("/driver/fleet"))
          : null,
      children: [
        if (_fleetLoaded) ...[
          const SizedBox(height: NvSpace.s2),
          Text(names.isEmpty ? "No drivers yet." : names.join(" · "),
              style: NvText.body),
        ] else
          _fleetLoadFailed("Could not load your drivers."),
      ],
    );
  }

  Widget _bankDetails() {
    // The status says whether the owner has sent bank details for review (approvalStatusInWords).
    final sent = const {"SUBMITTED", "APPROVED", "REJECTED"}
        .contains(DriverSession.kycStatus);
    return NvSectionCard(
      title: "Bank details",
      action: NvButton(
          label: sent ? "Change bank details" : "Add bank details",
          kind: NvButtonKind.secondary,
          onPressed: () => context.push("/driver/payout-setup")),
      children: [
        const SizedBox(height: NvSpace.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: NvButton(
              label: "Earnings & payouts",
              kind: NvButtonKind.quiet,
              onPressed: () => context.push("/driver/earnings")),
        ),
      ],
    );
  }

  Widget _team() => NvSectionCard(
        title: "Team",
        action: NvButton(
            label: "Invite",
            kind: NvButtonKind.secondary,
            onPressed: () => context.push("/driver/fleet")),
        children: const [
          SizedBox(height: NvSpace.s2),
          Text(
              "Dispatchers accept bookings and assign drivers. They do not see payments.",
              style: NvText.caption),
        ],
      );

  /// dr-profile: who the driver is signed in as. No bank, earnings or payouts.
  Widget _aboutYou(String? phone) {
    final name = _nonEmpty(DriverSession.userFullName);
    final company = _nonEmpty(DriverSession.carrierOrgName);
    final role = _nonEmpty(DriverSession.carrierRole);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: NvSpace.s4, vertical: NvSpace.s2),
      decoration: BoxDecoration(
        color: NvColors.card,
        borderRadius: BorderRadius.circular(NvRadius.card),
        border: Border.all(color: NvColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _factRows([
          if (name != null) _factRow("Name", name),
          if (phone != null && phone.isNotEmpty)
            _factRow("Phone", formatPhone(phone)),
          if (company != null) _factRow("Company", company),
          if (role != null) _factRow("Role", carrierMemberRoleLabel(role)),
        ]),
      ),
    );
  }

  /// The same sign-out as the account menu, as a row the mockup puts on a driver's Profile.
  Widget _signOutRow() => Material(
        color: NvColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NvRadius.card),
          side: const BorderSide(color: NvColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            child: InkWell(
              onTap: () async {
                // Taken before signing out, which rebuilds this screen under a new key.
                final router = GoRouter.of(context);
                await AuthorizationSession.signOut();
                router.go("/");
              },
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: NvSpace.targetDriver),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: NvSpace.s4),
                  child: Row(children: [
                    ExcludeSemantics(
                        child: Icon(Icons.logout, color: NvColors.slate)),
                    SizedBox(width: NvSpace.s4),
                    Expanded(child: Text("Sign out", style: NvText.bodyStrong)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final phone = DriverSession.userPhone;
    const gap = SizedBox(height: NvSpace.s4);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
        children: [
          if (_office) ...[
            if (DriverSession.complianceApproved)
              const Align(
                alignment: Alignment.centerLeft,
                child: NvStatusLabel("Approved by NaviG8r",
                    tone: NvStatusTone.good),
              ),
            gap,
            const TransporterIdSection(),
            gap,
            _trucks(),
            gap,
            _drivers(),
            // Owners only: dispatchers and drivers never see bank details or payments (spec: ca-profile).
            if (_seesPaymentAmounts) ...[gap, _bankDetails()],
            if (DriverSession.canInviteDrivers) ...[gap, _team()],
          ] else ...[
            _aboutYou(phone),
            gap,
            _signOutRow(),
            gap,
            _trucks(),
            gap,
            // Drivers have no Publish tab; this was, and stays, their way to it.
            Align(
              alignment: Alignment.centerLeft,
              child: NvButton(
                  label: "Publish a trip",
                  kind: NvButtonKind.secondary,
                  onPressed: () => context.go("/driver/publish")),
            ),
            gap,
            const Text(
                "Your office assigns your trips. If something about a trip is wrong, ask your office.",
                style: NvText.caption),
          ],
        ],
      ),
    );
  }
}

/// ca-vehicle-sheet: the person's own truck. The size is a choice, not a typed code. Removing a truck is not
/// offered: the API has no way to do it.
class _TruckSheet extends StatefulWidget {
  const _TruckSheet();

  @override
  State<_TruckSheet> createState() => _TruckSheetState();
}

class _TruckSheetState extends State<_TruckSheet> {
  final _registration =
      TextEditingController(text: DriverSession.vehicleRegistrationNumber ?? "");
  // The saved size, so the sheet shows the truck as it is.
  String? _size = const ["SMALL", "MEDIUM", "LARGE"]
          .contains(DriverSession.vehicleClass)
      ? DriverSession.vehicleClass
      : null;
  final _capacity = TextEditingController(text: switch (DriverSession.vehicleCapacityKg) {
    null => "",
    final kg => kg == kg.roundToDouble() ? "${kg.round()}" : "$kg",
  });
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _registration.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final registration = _registration.text.trim();
    final capacity = double.tryParse(_capacity.text.trim());
    final size = _size;
    final String? problem;
    if (registration.isEmpty) {
      problem = "Enter the registration number.";
    } else if (size == null) {
      problem = _chooseTruckSizeSentence;
    } else if (capacity == null || capacity <= 0) {
      problem = "Enter the capacity in kg.";
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await api.patch<Map<String, dynamic>>(
        "/v1/pilot/me/vehicle",
        data: {
          "vehicleRegistrationNumber": registration,
          "vehicleClass": size,
          "vehicleCapacityKg": capacity,
        },
      );
      if (!mounted) return;
      closeNvSheetAfterSuccess<bool>(context,
          announcement: "Truck saved.", result: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = ewayBillErrorSentence(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => NvSheet(
        title: "Truck",
        errorText: _error,
        choices: [
          NvField(
            label: "Registration number",
            controller: _registration,
            identifier: true,
            textCapitalization: TextCapitalization.characters,
            help:
                "As on the registration certificate. Spaces are removed for the e-way bill.",
          ),
          const SizedBox(height: NvSpace.s2),
          NvChoiceRows<String>(
            label: "Truck size",
            options: [
              for (final size in _truckSizes)
                NvChoice(size.value, size.label,
                    caption: PendingCopy.truckSizeGuide),
            ],
            selected: _size,
            onChanged: (size) => setState(() => _size = size),
          ),
          const SizedBox(height: NvSpace.s2),
          NvField(
            label: "Capacity",
            controller: _capacity,
            unit: "kg",
            keyboardType: TextInputType.number,
          ),
        ],
        primaryLabel: "Save truck",
        onPrimary: _save,
        loading: _saving,
        loadingLabel: "Saving",
      );
}

/// What a driver reads when the office has given their trip to someone else since they opened it.
const _tripNoLongerAssignedSentence =
    "This trip is no longer assigned to you. Pull down on Trips to refresh.";

/// While a trip is in transit the driver's phone sends its position, and shippers see it.
const _locationSharedSentence =
    "Your location is shared with the shippers while this trip is in transit.";

/// A 404 to a driver: the trip, or the shipment's trip, is no longer assigned to them.
bool _answeredTripNoLongerAssigned(Object error) =>
    DriverSession.carrierRole == "DRIVER" && serverAnsweredNotFound(error);

/// The sentence for a refused action: for a driver's 404 the trip sentence, otherwise the usual one.
String _driverRefusalSentence(Object error) =>
    _answeredTripNoLongerAssigned(error)
        ? _tripNoLongerAssignedSentence
        : plainErrorSentence(error);

class DriverActiveTripScreen extends StatefulWidget {
  const DriverActiveTripScreen({required this.tripId, super.key});
  final String tripId;

  @override
  State<DriverActiveTripScreen> createState() => _DriverActiveTripScreenState();
}

class _DriverActiveTripScreenState extends State<DriverActiveTripScreen> {
  Map<String, dynamic>? _trip;
  List<Map<String, dynamic>> _shipments = [];
  LatLng? _driverPos;
  StreamSubscription<Position>? _posSub;
  DateTime? _lastLocationPostAt;
  LatLng? _geocodedOrigin;
  LatLng? _geocodedDest;
  String? _error;
  bool _loading = true;
  bool _starting = false;
  bool _completing = false;
  bool _tripNoLongerAssigned = false;
  bool _startingLocationSharing = false;
  bool _sharingStoppedOnThisPhone = false;
  // The stop the driver has just confirmed, shown at the top until the screen loads again (dr-done).
  Map<String, dynamic>? _justDelivered;

  @override
  void initState() {
    super.initState();
    // The load starts location sharing when it finds the trip in progress.
    _load();
  }

  void _stopLocationSharing() {
    _posSub?.cancel();
    _posSub = null;
  }

  /// A running stream outlives the trip it started on, so each new copy of the trip is checked: an owner who was
  /// driving and gives the trip to another driver stops sending this phone's position at once.
  void _stopSharingIfNotInTheTruck() {
    if (_posSub == null || _phoneIsInTheTruck) return;
    _stopLocationSharing();
    setState(() => _sharingStoppedOnThisPhone = true);
  }

  /// The phone in the truck: a driver's, or an owner's who is the trip's driver. An office phone that
  /// opens a trip in transit is not where the truck is, so it never sends its position as the truck's.
  bool get _phoneIsInTheTruck {
    final driver = _nonEmpty(_trip?["assignedDriverUserId"]);
    return _forDriver ||
        (driver != null &&
            driver == AuthorizationSession.user?["id"]?.toString());
  }

  /// Location may be shared only while the trip on screen is in progress and still this person's to see.
  bool get _mayShareLocation =>
      mounted &&
      !_tripNoLongerAssigned &&
      _phoneIsInTheTruck &&
      _trip?["status"]?.toString() == "IN_PROGRESS";

  Future<void> _startLocation() async {
    // One attempt at a time: a load and Start load, or two loads, can both ask while an attempt waits on the phone.
    if (_posSub != null || _startingLocationSharing || !_mayShareLocation) {
      return;
    }
    _startingLocationSharing = true;
    try {
      // Each answer can arrive after the trip was given away or finished, so a check follows each one.
      var perm = await Geolocator.checkPermission();
      if (!_mayShareLocation) return;
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (!_mayShareLocation) return;
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;
      try {
        final p = await Geolocator.getCurrentPosition();
        if (mounted) setState(() => _driverPos = LatLng(p.latitude, p.longitude));
      } catch (_) {}
      if (!_mayShareLocation) return;
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 25),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _driverPos = LatLng(p.latitude, p.longitude));
        _maybePostLocation(p);
      });
    } finally {
      _startingLocationSharing = false;
    }
  }

  /// dr-confirm, then dr-done: back on the trip, the delivery just confirmed sits at the top and the next stop
  /// follows. A screen reader hears both at once (accessibility.md, "Confirm delivery").
  Future<void> _openPod(Map<String, dynamic> stop) async {
    final confirmed =
        await context.push<bool>("/driver/shipment/${stop["id"]}/pod");
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    if (confirmed == true) {
      final place = _nonEmpty(stop["dropAddress"]);
      final next = _nextStop;
      final nextPlace = next == null ? null : _nonEmpty(next["dropAddress"]);
      setState(() => _justDelivered = _shipments.firstWhere(
          (shipment) => shipment["id"] == stop["id"],
          orElse: () => stop));
      SemanticsService.announce(
          [
            place == null ? "Delivery confirmed." : "Delivery confirmed at $place.",
            if (nextPlace != null) "Next stop: $nextPlace.",
          ].join(" "),
          Directionality.of(context));
    }
    if (_trip?["status"]?.toString() == "COMPLETED") {
      _stopLocationSharing();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Trip complete. All deliveries confirmed.")));
    }
  }

  Future<void> _completeLoad() async {
    setState(() => _completing = true);
    try {
      final r = await api.post<Map<String, dynamic>>(
          "/v1/pilot/anchor-trips/${widget.tripId}/complete",
          data: {});
      final t = r.data?["trip"];
      if (!mounted) return;
      if (t is Map<String, dynamic>) setState(() => _trip = t);
      _stopLocationSharing();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Trip complete.")));
    } catch (e) {
      if (!mounted) return;
      if (_answeredTripNoLongerAssigned(e)) {
        // The reload's own 404 branch stops location sharing and leaves only the sentence on screen.
        await _load();
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(plainErrorSentence(e))));
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _startTrip() async {
    setState(() => _starting = true);
    try {
      final r = await api.post<Map<String, dynamic>>(
          "/v1/pilot/anchor-trips/${widget.tripId}/start");
      final t = r.data?["trip"];
      if (!mounted) return;
      if (t is Map<String, dynamic>) setState(() => _trip = t);
      if (_posSub == null) await _startLocation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Trip started. Shippers are told their goods are on the way.")));
    } catch (e) {
      if (!mounted) return;
      if (_answeredTripNoLongerAssigned(e)) {
        // The reload's own 404 branch stops location sharing and leaves only the sentence on screen.
        await _load();
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(plainErrorSentence(e))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  List<Map<String, dynamic>> get _acceptedBookings => _shipments
      .where((shipment) => shipment["status"] == "BOOKED")
      .toList();

  /// ca-start: nothing is sent until the sheet's Start trip, since a slip on the old list started trips.
  Future<void> _confirmStart() async {
    final trip = _trip;
    if (trip == null) return;
    final missingTruck = _acceptedBookings.where(_truckMissingFromBill).toList();
    final start = await showNvSheet<bool>(
        context: context,
        builder: (_) => _StartTripSheet(
            trip: trip,
            accepted: _acceptedBookings,
            missingTruck: missingTruck));
    if (!mounted || start != true) return;
    await _startTrip();
  }

  Future<void> _maybePostLocation(Position p) async {
    if (_trip?["status"]?.toString() != "IN_PROGRESS") return;
    final now = DateTime.now();
    if (_lastLocationPostAt != null &&
        now.difference(_lastLocationPostAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastLocationPostAt = now;
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/anchor-trips/${widget.tripId}/location",
        data: {
          "lat": p.latitude,
          "lng": p.longitude,
          "accuracyM": p.accuracy,
          if (p.speed >= 0) "speedMps": p.speed,
          if (p.heading >= 0) "headingDeg": p.heading,
        },
      );
    } catch (_) {
      // Best-effort; map still works locally if API is unreachable.
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _tripNoLongerAssigned = false;
      _justDelivered = null;
    });
    try {
      final r = await api
          .get<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}");
      final t = r.data?["trip"];
      if (!mounted) return;
      setState(() => _trip = t is Map<String, dynamic> ? t : null);
      _stopSharingIfNotInTheTruck();
      // Also restarts sharing once the office gives the trip back. Not awaited, so a permission dialog never
      // holds up the load.
      if (_trip?["status"]?.toString() == "IN_PROGRESS") _startLocation();
    } catch (e) {
      if (!mounted) return;
      if (_answeredTripNoLongerAssigned(e)) {
        // Nothing on this trip is this driver's to see or share any more, its location included.
        _stopLocationSharing();
        setState(() {
          _tripNoLongerAssigned = true;
          _trip = null;
          _shipments = [];
          _geocodedOrigin = null;
          _geocodedDest = null;
          _loading = false;
        });
        return;
      }
      setState(() => _error = _listLoadFailedWords("this trip", e));
    }

    try {
      final sr = await api.get<Map<String, dynamic>>(
        "/v1/pilot/carrier/shipments",
        query: {"anchorTripId": widget.tripId},
      );
      final raw = sr.data?["shipments"];
      final ships = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map<String, dynamic>) ships.add(s);
        }
      }
      if (mounted) setState(() => _shipments = ships);
    } catch (e) {
      if (mounted) {
        setState(() {
          _shipments = [];
          _error ??= _listLoadFailedWords("the bookings on this trip", e);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted && _trip?["status"]?.toString() == "COMPLETED") {
      _stopLocationSharing();
    }
    // Only the driver's view has the map these places are for.
    if (_forDriver) await _geocodeTripCitiesIfNeeded();
  }

  bool get _forDriver => DriverSession.carrierRole == "DRIVER";

  bool get _hasActiveShipments => _shipments.any((s) {
        final st = s["status"]?.toString() ?? "";
        return st == "BOOKED" || st == "PENDING_CARRIER_ACCEPT";
      });

  Future<void> _geocodeTripCitiesIfNeeded() async {
    final trip = _trip;
    if (trip == null) return;
    if (latLngFromGeoMap(trip, "origin") != null &&
        latLngFromGeoMap(trip, "destination") != null) return;
    if (kMapsApiKey.isEmpty) return;
    final oc = trip["originCity"]?.toString().trim() ?? "";
    final dc = trip["destCity"]?.toString().trim() ?? "";
    if (oc.isEmpty || dc.isEmpty) return;
    final o = await GoogleGeocodingService.forwardAddress("$oc, India");
    final d = await GoogleGeocodingService.forwardAddress("$dc, India");
    if (!mounted) return;
    setState(() {
      if (o.isOk) _geocodedOrigin = o.position;
      if (d.isOk) _geocodedDest = d.position;
    });
  }

  ({LatLng? laneStart, LatLng? laneEnd, LatLng? pickup, LatLng? drop})
      _resolvedMapPoints() {
    final trip = _trip;
    var laneStart = latLngFromGeoMap(trip, "origin") ?? _geocodedOrigin;
    var laneEnd = latLngFromGeoMap(trip, "destination") ?? _geocodedDest;
    LatLng? pickup;
    LatLng? drop;
    for (final s in _shipments) {
      pickup ??= latLngFromGeoMap(s, "pickup");
      drop ??= latLngFromGeoMap(s, "drop");
    }
    laneStart ??= pickup;
    laneEnd ??= drop;
    return (laneStart: laneStart, laneEnd: laneEnd, pickup: pickup, drop: drop);
  }

  @override
  void dispose() {
    _stopLocationSharing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_tripNoLongerAssigned) {
      // Only the sentence; pulling down asks again, in case the office gives the trip back.
      return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(NvSpace.gutter),
              children: const [
                NvMessage(_tripNoLongerAssignedSentence,
                    tone: NvMessageTone.problem),
              ]));
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    final trip = _trip;
    final canComplete = trip?["status"] == "IN_PROGRESS" &&
        _shipments.isNotEmpty &&
        !_hasActiveShipments;
    return _forDriver
        ? _driverView(trip, canComplete: canComplete)
        : _officeView(trip, canComplete: canComplete);
  }

  /// The first accepted booking not yet delivered, in the order the server lists them: the app has no stop order.
  Map<String, dynamic>? get _nextStop {
    for (final shipment in _shipments) {
      if (shipment["status"] == "BOOKED") return shipment;
    }
    return null;
  }

  /// dr-done: the stop just confirmed, its shipper and the time the server recorded. Not a live region: the
  /// confirmation is announced once, with the next stop, when the screen comes back.
  Widget _deliveredBanner(Map<String, dynamic> stop) {
    final podAt = stop["podAtUtcMs"];
    final details = [
      if (_nonEmpty(stop["dropAddress"]) != null) stop["dropAddress"] as String,
      _shipperName(stop),
      if (podAt is num)
        formatTimeIst(
            DateTime.fromMillisecondsSinceEpoch(podAt.toInt(), isUtc: true)),
    ].join(" · ");
    return Semantics(
      container: true,
      label: "Delivery confirmed. $details",
      child: ExcludeSemantics(
        child: NvMessage(details,
            title: "Delivery confirmed", tone: NvMessageTone.good),
      ),
    );
  }

  Widget _nextStopCard(Map<String, dynamic> stop) {
    final weight = _weightWords(stop);
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
              child: const Text("NEXT STOP", style: NvText.label)),
          const SizedBox(height: NvSpace.s1),
          Text(_nonEmpty(stop["dropAddress"]) ?? _shipperName(stop),
              style: NvText.title),
          const SizedBox(height: NvSpace.s1),
          Text([_shipperName(stop), if (weight != null) weight].join(" · "),
              style: NvText.body),
          if (AuthorizationSession.can("pod.upload")) ...[
            const SizedBox(height: NvSpace.s4),
            NvButton(
                label: "I am here: confirm delivery",
                onPressed: () => _openPod(stop),
                forDriver: true,
                fullWidth: true),
          ],
        ],
      ),
    );
  }

  /// One stop under "All stops". It opens the booking, where a driver can still accept or confirm it.
  Widget _stopCard(Map<String, dynamic> stop, Map<String, dynamic>? trip) {
    final status = _bookingStatus(stop, trip);
    final weight = _weightWords(stop);
    return NvListCard(
      title: _nonEmpty(stop["dropAddress"]) ?? _shipperName(stop),
      subtitle: [_shipperName(stop), if (weight != null) weight].join(" · "),
      status: status == null
          ? null
          : NvStatusLabel(status.$1, tone: status.$2),
      onOpen: () async {
        await context.push("/driver/shipment/${stop["id"]}");
        if (mounted) await _load();
      },
    );
  }

  /// dr-trip: the route, its status and truck, the e-way bills one tap away, the next stop with its one button,
  /// then every stop; Start or Complete sits at the bottom. There is no Directions button and no "Drop 1 of 3":
  /// the app hands nothing to a maps app and has no stop order, so the map stays and stops keep the server's order.
  Widget _driverView(Map<String, dynamic>? trip, {required bool canComplete}) {
    final status = trip?["status"];
    final started = status == "IN_PROGRESS";
    final truck = _nonEmpty(trip?["assignedTruckNumber"]);
    final next = started ? _nextStop : null;
    final stops = _shipments
        .where((stop) => _bookingStatusesShown.contains(stop["status"]))
        .toList();
    final mayStart = trip != null &&
        (status == "OPEN" || status == "FULL") &&
        AuthorizationSession.can("load.status_update");
    final startBlocked = trip == null ? null : _startBlockedReason(trip);
    final NvStatusLabel? statusLabel = switch (status) {
      "IN_PROGRESS" =>
        const NvStatusLabel("In transit", tone: NvStatusTone.info),
      "COMPLETED" => const NvStatusLabel("Done", tone: NvStatusTone.ended),
      "OPEN" || "FULL" when _acceptedBookings.isNotEmpty =>
        const NvStatusLabel("Ready to start", tone: NvStatusTone.good),
      _ => null,
    };
    final points = _resolvedMapPoints();
    final hasMap = points.laneStart != null ||
        points.laneEnd != null ||
        (started && _driverPos != null);
    const gap = SizedBox(height: NvSpace.s4);
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, NvSpace.s2, NvSpace.gutter, NvSpace.s6),
            children: [
              if (_error != null) ...[
                NvMessage(_error!, tone: NvMessageTone.problem),
                gap,
              ],
              if (_justDelivered != null) ...[
                _deliveredBanner(_justDelivered!),
                gap,
              ],
              Semantics(
                  header: true,
                  child: Text(_tripRoute(trip) ?? "Trip", style: NvText.title)),
              const SizedBox(height: NvSpace.s2),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: NvSpace.s2,
                runSpacing: NvSpace.s1,
                children: [
                  if (statusLabel != null) statusLabel,
                  if (truck != null)
                    Text(portalTruckNumber(truck), style: NvText.id),
                ],
              ),
              if (trip != null) ...[
                gap,
                NvButton(
                    label: "Show e-way bills",
                    kind: NvButtonKind.secondary,
                    forDriver: true,
                    fullWidth: true,
                    onPressed: () => context
                        .push("/driver/trip/${widget.tripId}/eway-bills")),
              ],
              if (next != null) ...[gap, _nextStopCard(next)],
              if (status == "COMPLETED") ...[
                gap,
                const NvMessage(
                    "All deliveries confirmed. GPS sharing has stopped.",
                    tone: NvMessageTone.good),
              ],
              if (canComplete) ...[
                gap,
                const NvMessage(
                    "Every delivery is confirmed. Complete the trip to stop sharing your location.",
                    tone: NvMessageTone.info),
              ],
              if (started) ...[
                const SizedBox(height: NvSpace.s2),
                const Text(_locationSharedSentence, style: NvText.caption),
              ],
              if (hasMap) ...[
                gap,
                NvMap(
                  map: activeTripMap(
                    laneStart: points.laneStart,
                    laneEnd: points.laneEnd,
                    driver: started ? _driverPos : null,
                    pickup: points.pickup,
                    drop: points.drop,
                  ),
                ),
              ],
              if (stops.isNotEmpty) ...[
                const SizedBox(height: NvSpace.s6),
                Semantics(
                    header: true,
                    child: const Text("All stops", style: NvText.heading)),
                const SizedBox(height: NvSpace.s3),
                for (final stop in stops) ...[
                  _stopCard(stop, trip),
                  const SizedBox(height: NvSpace.s3),
                ],
              ],
            ],
          ),
        ),
      ),
      if (mayStart)
        NvActionBar(
          child: NvButton(
            label: "Start trip",
            onPressed: startBlocked == null ? _confirmStart : null,
            disabledReason: startBlocked,
            loading: _starting,
            loadingLabel: "Starting",
            forDriver: true,
            fullWidth: true,
          ),
        )
      else if (canComplete && AuthorizationSession.can("load.status_update"))
        NvActionBar(
          child: NvButton(
            label: "Complete trip",
            onPressed: _completeLoad,
            loading: _completing,
            loadingLabel: "Completing",
            forDriver: true,
            fullWidth: true,
          ),
        ),
    ]);
  }

  /// Why the office cannot start the trip yet, or null when it can (copy.md, "Start (disabled)").
  String? _startBlockedReason(Map<String, dynamic> trip) {
    if (!DriverSession.complianceApproved) {
      return "NaviG8r has not approved this carrier yet.";
    }
    if (_acceptedBookings.isEmpty) return "Accept a booking on this trip first.";
    // A driver only ever sees the trips they drive.
    if (!_forDriver && _nonEmpty(trip["assignedDriverUserId"]) == null) {
      return "Assign a driver first. Then start on loading day.";
    }
    return null;
  }

  Widget _tripSummary(Map<String, dynamic> trip) {
    final status = _tripStatusLabel(trip);
    final details = [
      if (_tripDates(trip) != null) _tripDates(trip)!,
      if (_truckSizeWords(trip["vehicleClass"]) != null)
        _truckSizeWords(trip["vehicleClass"])!,
    ];
    final room = _roomLeftKg(trip);
    final capacity = trip["capacityKg"];
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
        color: NvColors.card,
        borderRadius: BorderRadius.circular(NvRadius.card),
        border: Border.all(color: NvColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("TRIP", style: NvText.label),
          const SizedBox(height: NvSpace.s1),
          Semantics(
              header: true,
              child: Text(_tripRoute(trip) ?? "Trip", style: NvText.title)),
          const SizedBox(height: NvSpace.s2),
          Wrap(
            spacing: NvSpace.s2,
            runSpacing: NvSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status != null) status,
              if (details.isNotEmpty)
                Text(details.join(" · "), style: NvText.caption),
            ],
          ),
          if (room != null && capacity is num) ...[
            const SizedBox(height: NvSpace.s2),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: "Room left: ${formatKg(room)}",
                    style: NvText.bodyStrong),
                TextSpan(text: " of ${formatKg(capacity)}"),
              ]),
              style: NvText.body,
            ),
          ],
        ],
      ),
    );
  }

  Widget _bookingOnTrip(
      Map<String, dynamic> booking, Map<String, dynamic>? trip) {
    final status = _bookingStatus(booking, trip);
    final pickup = booking["pickupAddress"]?.toString() ?? "";
    final drop = booking["dropAddress"]?.toString() ?? "";
    final weight = _weightWords(booking);
    return NvListCard(
      title: [_shipperName(booking), if (weight != null) weight].join(" · "),
      subtitle: pickup.isEmpty || drop.isEmpty ? null : "$pickup to $drop",
      status: status == null
          ? null
          : NvStatusLabel(status.$1, tone: status.$2),
      onOpen: () async {
        await context.push("/driver/shipment/${booking["id"]}");
        if (mounted) await _load();
      },
    );
  }

  /// ca-trip: the trip, its truck and driver, its bookings, and Start (or Complete) held at the bottom so it is
  /// visible without scrolling. No map: on the office's phone the map's own dot is the office, not the truck.
  Widget _officeView(Map<String, dynamic>? trip, {required bool canComplete}) {
    final status = trip?["status"];
    final bookings = _shipments
        .where((booking) => _bookingStatusesShown.contains(booking["status"]))
        .toList();
    final mayStart = trip != null &&
        (status == "OPEN" || status == "FULL") &&
        AuthorizationSession.can("load.status_update");
    final startBlocked = trip == null ? null : _startBlockedReason(trip);
    const gap = SizedBox(height: NvSpace.s4);
    return Column(children: [
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, NvSpace.s2, NvSpace.gutter, NvSpace.s6),
            children: [
              if (_error != null) ...[
                NvMessage(_error!, tone: NvMessageTone.problem),
                gap,
              ],
              if (trip != null) ...[
                _tripSummary(trip),
                gap,
                TripAssignmentCard(
                  key: ValueKey(trip["id"]),
                  trip: trip,
                  tripInWords: _tripInWords(trip),
                  onAssigned: (saved) {
                    setState(() => _trip = saved);
                    _stopSharingIfNotInTheTruck();
                  },
                  onAddDriver: DriverSession.canInviteDrivers
                      ? () => context.push("/driver/fleet")
                      : null,
                ),
                gap,
              ],
              if (bookings.isNotEmpty) ...[
                Semantics(
                    header: true,
                    child: Text("Bookings on this trip (${bookings.length})",
                        style: NvText.heading)),
                const SizedBox(height: NvSpace.s3),
                for (final booking in bookings) ...[
                  _bookingOnTrip(booking, trip),
                  const SizedBox(height: NvSpace.s3),
                ],
              ],
              if (status == "COMPLETED")
                const NvMessage(
                    "All deliveries confirmed. GPS sharing has stopped.",
                    tone: NvMessageTone.good),
              // An owner driving the trip shares this phone's location, and is told so as a driver is.
              if (status == "IN_PROGRESS" && _phoneIsInTheTruck)
                const Text(_locationSharedSentence, style: NvText.caption)
              else if (status == "IN_PROGRESS" && _sharingStoppedOnThisPhone)
                const NvMessage(
                    "Location sharing has stopped on this phone. You are no longer this trip's driver.",
                    tone: NvMessageTone.info),
            ],
          ),
        ),
      ),
      if (mayStart)
        NvActionBar(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (startBlocked != null) ...[
                Semantics(
                    header: true,
                    child:
                        const Text("Start the trip", style: NvText.bodyStrong)),
                const SizedBox(height: NvSpace.s2),
              ],
              NvButton(
                label: "Start trip",
                onPressed: startBlocked == null ? _confirmStart : null,
                disabledReason: startBlocked,
                loading: _starting,
                loadingLabel: "Starting",
                fullWidth: true,
              ),
            ],
          ),
        )
      else if (canComplete && AuthorizationSession.can("load.status_update"))
        NvActionBar(
          child: NvButton(
            label: "Complete trip",
            onPressed: _completeLoad,
            loading: _completing,
            loadingLabel: "Completing",
            fullWidth: true,
          ),
        ),
    ]);
  }
}

/// "Start [route] now?": what starting the trip takes on the road, and a warning for each accepted booking whose
/// e-way bill does not have the truck yet. Closes with true to start; the screen then starts the trip.
class _StartTripSheet extends StatelessWidget {
  const _StartTripSheet(
      {required this.trip, required this.accepted, required this.missingTruck});
  final Map<String, dynamic> trip;
  final List<Map<String, dynamic>> accepted;
  final List<Map<String, dynamic>> missingTruck;

  Widget _fact(String label, String value, {bool identifier = false}) =>
      MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NvSpace.s2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: NvText.body.copyWith(color: NvColors.slate)),
            const SizedBox(width: NvSpace.s3),
            Expanded(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: identifier
                        ? NvText.id.copyWith(fontWeight: FontWeight.w600)
                        : NvText.bodyStrong)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final truck = _nonEmpty(trip["assignedTruckNumber"]);
    final totalKg = accepted
        .map((booking) => booking["weightKg"])
        .whereType<num>()
        .fold<num>(0, (sum, kg) => sum + kg);
    return NvSheet(
      title: "Start ${_tripRoute(trip) ?? "this trip"} now?",
      choices: [
        _fact("Truck", truck == null ? "Not assigned" : portalTruckNumber(truck),
            identifier: truck != null),
        const Divider(height: 1, color: NvColors.line),
        _fact("Driver", _nonEmpty(trip["assignedDriverName"]) ?? "Not assigned"),
        const Divider(height: 1, color: NvColors.line),
        _fact("Bookings", "${accepted.length} · ${formatKg(totalKg)}"),
        for (final booking in missingTruck)
          NvMessage(
              "${_shipperName(booking)} adds it. Without the truck, the bill is not valid for moving the goods.",
              title:
                  "${_shipperName(booking)}'s e-way bill does not have the truck yet.",
              tone: NvMessageTone.attention),
      ],
      primaryLabel: "Start trip",
      onPrimary: () => Navigator.of(context).pop(true),
      cancelLabel: "Not yet",
      footer: const Text("Starting tells each shipper their goods are on the way.",
          style: NvText.caption),
    );
  }
}

/// dr-confirm: which drop this is, then Confirm delivery at the bottom. The mockup's photo step is not here: the
/// app has no camera and the API takes only notes, so the notes field stays. Closes with true once confirmed, and
/// the screen underneath says so.
class DriverPodScreen extends StatefulWidget {
  const DriverPodScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<DriverPodScreen> createState() => _DriverPodScreenState();
}

class _DriverPodScreenState extends State<DriverPodScreen> {
  final _notes = TextEditingController();
  // Null until found: the stop's place, shipper and weight only name the drop, so the screen works without them.
  Map<String, dynamic>? _shipment;
  bool _busy = false;
  String? _error;

  bool get _forDriver => DriverSession.carrierRole == "DRIVER";

  @override
  void initState() {
    super.initState();
    _loadShipment();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadShipment() async {
    try {
      final response =
          await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
      final raw = response.data?["shipments"];
      if (raw is! List) return;
      for (final shipment in raw.whereType<Map<String, dynamic>>()) {
        if (shipment["id"] == widget.shipmentId) {
          if (mounted) setState(() => _shipment = shipment);
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notes = _notes.text.trim();
      await api.post<Map<String, dynamic>>(
        "/shipments/${widget.shipmentId}/driver-pod",
        data: notes.isEmpty ? {} : {"notes": notes},
      );
      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = serverNeverAnswered(e)
            ? "Could not confirm: no signal. Try again when you have one."
            : _driverRefusalSentence(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// What confirming leads to, for each reader. Only the owner is told about the payment (ca-booking-owner).
  String get _whatHappensNext {
    if (_seesPaymentAmounts) {
      return "NaviG8r operations check the proof of delivery, then release the payment to your bank account.";
    }
    if (AuthorizationSession.can("payment.read")) {
      return "NaviG8r operations check the proof of delivery. The owner sees the payment.";
    }
    return "Confirming delivery sends your proof of delivery to NaviG8r.";
  }

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final weight = shipment == null ? null : _weightWords(shipment);
    final drop = [
      if (shipment != null) ...[
        if (_nonEmpty(shipment["dropAddress"]) != null)
          shipment["dropAddress"] as String,
        _shipperName(shipment),
        if (weight != null) weight,
      ],
    ];
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
          children: [
            if (drop.isNotEmpty) ...[
              Text(drop.join(" · "), style: NvText.body),
              const SizedBox(height: NvSpace.s4),
            ],
            NvSectionCard(
              title: "Confirm the goods are handed over",
              children: [
                const SizedBox(height: NvSpace.s2),
                Text(_whatHappensNext, style: NvText.body),
                const SizedBox(height: NvSpace.s3),
                NvField(label: "Notes", optional: true, controller: _notes),
              ],
            ),
          ],
        ),
      ),
      NvActionBar(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              NvMessage(_error!, tone: NvMessageTone.problem),
              const SizedBox(height: NvSpace.s3),
            ],
            NvButton(
              label: "Confirm delivery",
              onPressed: _confirm,
              loading: _busy,
              loadingLabel: "Confirming",
              forDriver: _forDriver,
              fullWidth: true,
            ),
          ],
        ),
      ),
    ]);
  }
}

/// dr-ewb: the e-way bill of each booking on the truck, with its number large enough to read out at a check post.
/// The mockup's "Drop 1" and "Call [carrier]" are not here: the app has no stop order and no office phone number,
/// so each bill names its drop place instead, and a missing truck says to call the office without a button.
class DriverTripEwayBillsScreen extends StatefulWidget {
  const DriverTripEwayBillsScreen({required this.tripId, super.key});
  final String tripId;

  @override
  State<DriverTripEwayBillsScreen> createState() =>
      _DriverTripEwayBillsScreenState();
}

class _DriverTripEwayBillsScreenState extends State<DriverTripEwayBillsScreen> {
  Map<String, dynamic>? _trip;
  List<Map<String, dynamic>>? _bookings;
  String? _error;
  bool _tripNoLongerAssigned = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _tripNoLongerAssigned = false;
    });
    try {
      final tripResponse = await api
          .get<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}");
      final shipments = await api.get<Map<String, dynamic>>(
          "/v1/pilot/carrier/shipments",
          query: {"anchorTripId": widget.tripId});
      final trip = tripResponse.data?["trip"];
      final raw = shipments.data?["shipments"];
      if (!mounted) return;
      setState(() {
        _trip = trip is Map<String, dynamic> ? trip : null;
        _bookings = raw is List
            ? raw
                .whereType<Map<String, dynamic>>()
                .where((booking) => booking["status"] == "BOOKED")
                .toList()
            : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tripNoLongerAssigned = _answeredTripNoLongerAssigned(e);
        _error = _listLoadFailedWords("the e-way bills", e);
      });
    }
  }

  /// What is wrong with this bill for the truck on the road, or null when nothing is.
  String? _problem(Map<String, dynamic> booking, Map<String, dynamic> bill) {
    final onBill = bill["truckNumber"];
    if (onBill is! String || onBill.isEmpty) {
      return "This truck is not on this bill. Call your office now so they can add it.";
    }
    final mismatch = ewayBillTruckMismatchSentence(booking, bill,
        reader: TruckMismatchReader.driver);
    if (mismatch != null) return mismatch;
    final check = bill["check"];
    if (check is Map && check["result"] == "PROBLEM") {
      return ewayBillCheckLine(bill, forShipper: false);
    }
    return null;
  }

  Widget _billCard(Map<String, dynamic> booking) {
    final shipper = _shipperName(booking);
    final drop = _nonEmpty(booking["dropAddress"]);
    final bill = _ewayBillOf(booking);
    final List<Widget> details;
    String? problem;
    if (bill == null) {
      details = [
        Text("$shipper has not added an e-way bill or said none is needed.",
            style: NvText.body)
      ];
    } else if (bill["kind"] == "NOT_NEEDED") {
      details = const [
        Text("Not needed (shipper said so).", style: NvText.body)
      ];
    } else {
      final number = _nonEmpty(bill["billNumber"]);
      final validUntil = bill["validUntilUtcMs"];
      final moment = validUntil is num
          ? DateTime.fromMillisecondsSinceEpoch(validUntil.toInt(),
              isUtc: true)
          : null;
      problem = _problem(booking, bill);
      details = [
        if (number != null)
          SelectableText(formatBillNumber(number), style: NvText.idDisplay),
        if (moment != null)
          Text.rich(
              TextSpan(children: [
                const TextSpan(text: "Valid until "),
                TextSpan(
                    text: "${formatDate(moment)}, ${formatTimeIst(moment)}",
                    style: NvText.bodyStrong),
              ]),
              style: NvText.body),
      ];
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: "E-way bill for $shipper",
      child: Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(
              color: problem == null ? NvColors.line : NvColors.problem,
              width: problem == null ? 1 : 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(shipper.toUpperCase(), style: NvText.label),
            if (drop != null) Text(drop, style: NvText.caption),
            const SizedBox(height: NvSpace.s2),
            ...details,
            if (problem != null) ...[
              const SizedBox(height: NvSpace.s3),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const ExcludeSemantics(
                    child: Icon(Icons.error_outline,
                        size: 20, color: NvColors.problem)),
                const SizedBox(width: NvSpace.s2),
                Expanded(
                    child: Text(problem,
                        style: NvText.bodyStrong
                            .copyWith(color: NvColors.problem))),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookings = _bookings;
    final truck = _nonEmpty(_trip?["assignedTruckNumber"]);
    final List<Widget> content;
    if (_tripNoLongerAssigned) {
      content = const [
        NvMessage(_tripNoLongerAssignedSentence, tone: NvMessageTone.problem)
      ];
    } else if (_error != null) {
      content = [NvListError(title: _error!, onRetry: _load)];
    } else if (bookings == null) {
      content = [
        Semantics(
            liveRegion: true,
            child: const Text("Loading the e-way bills.",
                style: NvText.caption)),
        const SizedBox(height: NvSpace.s2),
        const NvListLoadingCard(),
      ];
    } else if (bookings.isEmpty) {
      content = const [NvListEmpty(title: "No e-way bills on this trip yet.")];
    } else {
      content = [
        for (final booking in bookings) ...[
          _billCard(booking),
          const SizedBox(height: NvSpace.s3),
        ],
      ];
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            NvSpace.gutter, NvSpace.s2, NvSpace.gutter, NvSpace.s6),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: NvSpace.s3,
            runSpacing: NvSpace.s1,
            children: [
              Semantics(
                  header: true,
                  child: const Text("E-way bills", style: NvText.title)),
              if (truck != null)
                Text.rich(TextSpan(children: [
                  const TextSpan(text: "Truck ", style: NvText.caption),
                  TextSpan(text: portalTruckNumber(truck), style: NvText.id),
                ])),
            ],
          ),
          const SizedBox(height: NvSpace.s4),
          ...content,
        ],
      ),
    );
  }
}

class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  Map<String, dynamic>? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await DriverSession.refresh();
      if (!mounted) return;
      final orgId = DriverSession.carrierOrgId ?? "";
      final r = await api.get<Map<String, dynamic>>(
          "/v1/pilot/carrier/earnings",
          query: {"orgId": orgId});
      if (!mounted) return;
      setState(() => _summary = r.data?["summary"] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted)
        setState(() {
          _summary = null;
          _error = plainErrorSentence(e);
        });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final pending = s?["pendingAccruedPaise"] as num? ?? 0;
    final paid = s?["paidPaise"] as num? ?? 0;
    final kyc =
        s?["kycStatus"]?.toString() ?? DriverSession.kycStatus ?? "NOT_STARTED";

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null) Text(_error!),
              Row(
                children: [
                  Expanded(
                      child: _StatTile(
                          label: "Pending (accrued)",
                          value: formatRupees(pending))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatTile(
                          label: "Paid out", value: formatRupees(paid))),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  // Same live status as the banner above, so a refresh can't leave them disagreeing.
                  child: ListenableBuilder(
                    listenable: AuthorizationSession.revision,
                    builder: (context, _) => Text(
                      "Approval status: ${approvalStatusInWords(DriverSession.kycStatus ?? kyc)}. Settlement remains subject to payment readiness.",
                      style: const TextStyle(color: DriverTheme.muted),
                    ),
                  ),
                ),
              ),
              if (DriverSession.canSetUpPayouts)
                FilledButton(
                  onPressed: () => context.push("/driver/payout-setup"),
                  child: const Text("Manage payout method"),
                ),
              OutlinedButton(
                  onPressed: () => context.push("/driver/payout-history"),
                  child: const Text("Payout history")),
            ],
          );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DriverTheme.navy)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
          ],
        ),
      ),
    );
  }
}

class DriverPayoutSetupScreen extends StatefulWidget {
  const DriverPayoutSetupScreen({super.key});

  @override
  State<DriverPayoutSetupScreen> createState() =>
      _DriverPayoutSetupScreenState();
}

class _DriverPayoutSetupScreenState extends State<DriverPayoutSetupScreen> {
  final _name = TextEditingController();
  final _ifsc = TextEditingController();
  final _accountNumber = TextEditingController();
  bool _busy = false;
  String? _refusedField;
  int _edits = 0;

  @override
  void dispose() {
    _name.dispose();
    _ifsc.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  // The refused field gets a red box in the theme's own shape; the sentence stays in the snackbar.
  InputDecoration _decoration(String label, String field) {
    if (_refusedField != field) return InputDecoration(labelText: label);
    final theme = Theme.of(context);
    final box =
        (theme.inputDecorationTheme.border ?? const OutlineInputBorder())
            .copyWith(
                borderSide: BorderSide(color: theme.colorScheme.error, width: 2));
    return InputDecoration(
        labelText: label, enabledBorder: box, focusedBorder: box);
  }

  // Counts every edit, so a refusal for text typed over while the save was in flight boxes nothing.
  void _edited(String field) {
    _edits++;
    if (_refusedField == field) setState(() => _refusedField = null);
  }

  Future<void> _save() async {
    if (!DriverSession.canSetUpPayouts) return;
    // A message about the last save is out of date once a new save starts.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _busy = true);
    final editsWhenSent = _edits;
    try {
      final orgId = DriverSession.carrierOrgId ?? "";
      final name = _name.text.trim();
      final ifsc = _ifsc.text.trim();
      final acct = _accountNumber.text.trim();
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/carrier/payout-setup",
        data: {
          "orgId": orgId,
          "accountHolderName": name,
          "ifsc": ifsc,
          if (acct.isNotEmpty) "accountNumber": acct,
        },
      );
      final msg = r.data?["message"]?.toString() ?? "Saved.";
      await DriverSession.refresh();
      if (!mounted) return;
      // The server upper-cases the IFSC, so retyping it in the other case sends it nothing new.
      final fieldsMatchWhatWasSent = _name.text.trim() == name &&
          _ifsc.text.trim().toUpperCase() == ifsc.toUpperCase() &&
          _accountNumber.text.trim() == acct;
      if (!fieldsMatchWhatWasSent) {
        // The server got the text from the tap, not what the fields show now: stay here and say so.
        // Ten seconds because it is too long to read in four; Close because it covers the Save button.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: "Close", onPressed: () {}),
            content: Text("$msg\n"
                "You changed a field after tapping Save. The details sent are the ones from when you tapped. "
                "Tap Save again to send the change.")));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.push("/driver/payout-history");
    } catch (e) {
      if (mounted) {
        setState(() => _refusedField =
            _edits == editsWhenSent ? refusedBankDetailsField(e) : null);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(plainErrorSentence(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DriverSession.canSetUpPayouts)
      return const Center(
          child: Text(
              "Only an authorized carrier owner can manage the payout method."));
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Delivery payments go to this account. Check the details before saving.",
            style: TextStyle(color: DriverTheme.muted),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _name,
              onChanged: (_) => _edited("accountHolderName"),
              decoration:
                  _decoration("Account holder name", "accountHolderName")),
          TextField(
              controller: _ifsc,
              onChanged: (_) => _edited("ifsc"),
              decoration: _decoration("IFSC / bank identifier", "ifsc")),
          TextField(
            controller: _accountNumber,
            keyboardType: TextInputType.number,
            onChanged: (_) => _edited("accountNumber"),
            decoration: _decoration("Bank account number", "accountNumber"),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Save bank details"),
          ),
        ],
      ),
    );
  }
}

class DriverPayoutHistoryScreen extends StatefulWidget {
  const DriverPayoutHistoryScreen({super.key});

  @override
  State<DriverPayoutHistoryScreen> createState() =>
      _DriverPayoutHistoryScreenState();
}

class _DriverPayoutHistoryScreenState extends State<DriverPayoutHistoryScreen> {
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orgId = DriverSession.carrierOrgId ?? "";
      final r = await api.get<Map<String, dynamic>>(
          "/v1/pilot/carrier/payout-batches",
          query: {"orgId": orgId});
      final raw = r.data?["payoutBatches"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final b in raw) {
          if (b is Map<String, dynamic>) list.add(b);
        }
      }
      setState(() => _batches = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_batches.isEmpty)
                const Text(
                    "No payout batches yet. Complete POD on shipments and wait for batch settlement."),
              ..._batches.map((b) {
                final cutoff = b["cutoffUtcMs"];
                final moment = cutoff is num
                    ? DateTime.fromMillisecondsSinceEpoch(cutoff.toInt(),
                        isUtc: true)
                    : null;
                final lineCount = (b["lineIds"] as List?)?.length ?? 0;
                return Card(
                  child: ListTile(
                    title: Text(
                        formatRupees(b["totalNetToCarrierPaise"] as num? ?? 0)),
                    subtitle: Text([
                      if (moment != null)
                        "Cutoff ${formatDate(moment)}, ${formatTimeIst(moment)}",
                      "$lineCount lines",
                    ].join(" · ")),
                  ),
                );
              }),
            ],
          );
  }
}

/// What the publisher is told. A trip a driver publishes names no driver, so it shows under their Trips only
/// if the office assigns it to them.
SnackBar tripPublishedMessage() => DriverSession.carrierRole == "DRIVER"
    // Ten seconds because it is too long to read in four; Close because it covers the list underneath.
    ? SnackBar(
        duration: const Duration(seconds: 10),
        action: SnackBarAction(label: "Close", onPressed: () {}),
        content: const Text(
            "Trip published. Your carrier must assign it to a driver. You will see it under Trips only if it is assigned to you."))
    : const SnackBar(content: Text("Trip published."));

/// The calendar day in India at [moment], held as midnight UTC so days compare directly.
DateTime _dayInIndia(DateTime moment) {
  final india = moment.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime.utc(india.year, india.month, india.day);
}

/// Tests move it past midnight; the date picker cannot choose a day that has gone.
@visibleForTesting
DateTime Function() currentTime = DateTime.now;

/// The calendar day in India today.
DateTime _todayInIndia() => _dayInIndia(currentTime());

/// What was typed on Publish, kept in memory while the person goes to another tab and back. [owner] is the
/// sign-in and company it was typed under, so a sign-out, another sign-in or a company switch never gets it back.
typedef _PublishDraft = ({
  String owner,
  String from,
  LatLng? fromPoint,
  String to,
  LatLng? toPoint,
  DateTime? leaves,
  DateTime? arrivesBy,
  String? truckSize,
  String room,
});

_PublishDraft? _publishDraft;

/// Changes on every sign-in and sign-out (identityGeneration) and on a company switch (scopeKey).
String _publishDraftOwner() =>
    "${AuthorizationSession.identityGeneration}:${AuthorizationSession.scopeKey}";

/// ca-publish: every field starts empty (or as left on another tab), the truck size is a choice, and Publish stays
/// visible at the bottom.
class DriverPublishTripScreen extends StatefulWidget {
  const DriverPublishTripScreen(
      {super.key, this.findPlace = GoogleGeocodingService.forwardAddress});

  final PlaceFinder findPlace;

  @override
  State<DriverPublishTripScreen> createState() =>
      _DriverPublishTripScreenState();
}

class _DriverPublishTripScreenState extends State<DriverPublishTripScreen> {
  final _origin = TextEditingController();
  final _dest = TextEditingController();
  LatLng? _originPos;
  LatLng? _destPos;
  // Calendar days in India, held as midnight UTC.
  DateTime? _leaves;
  DateTime? _arrivesBy;
  String? _truckSize;
  final _room = TextEditingController();
  bool _submitting = false;
  bool _published = false;
  String? _error;
  final _form = ScrollController();
  final _draftOwner = _publishDraftOwner();

  @override
  void initState() {
    super.initState();
    final draft = _publishDraft;
    if (draft != null && draft.owner == _draftOwner) {
      // A draft kept past midnight can hold a day that has gone; the form only checks that one was chosen.
      final today = _todayInIndia();
      bool notGone(DateTime? day) => day != null && !day.isBefore(today);
      _origin.text = draft.from;
      _originPos = draft.fromPoint;
      _dest.text = draft.to;
      _destPos = draft.toPoint;
      _leaves = notGone(draft.leaves) ? draft.leaves : null;
      _arrivesBy = notGone(draft.arrivesBy) ? draft.arrivesBy : null;
      _truckSize = draft.truckSize;
      _room.text = draft.room;
    }
    DriverSession.refresh();
  }

  @override
  void dispose() {
    // A publish still sending may yet land; its draft would let the same trip be sent again.
    _publishDraft = _published || _submitting || _publishDraftOwner() != _draftOwner
        ? null
        : (
            owner: _draftOwner,
            from: _origin.text,
            fromPoint: _originPos,
            to: _dest.text,
            toPoint: _destPos,
            leaves: _leaves,
            arrivesBy: _arrivesBy,
            truckSize: _truckSize,
            room: _room.text,
          );
    _origin.dispose();
    _dest.dispose();
    _room.dispose();
    _form.dispose();
    super.dispose();
  }

  /// The message sits at the top of the form, so the form scrolls back up to show it.
  void _showError(String message) {
    setState(() => _error = message);
    if (_form.hasClients) {
      _form.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _chooseDay({required bool leaves}) async {
    final today = _todayInIndia();
    final earliest = leaves ? today : (_leaves ?? today);
    final current = leaves ? _leaves : _arrivesBy;
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current != null && !current.isBefore(earliest) ? current : earliest,
      firstDate: earliest,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    final day = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (leaves) {
        _leaves = day;
        // An arrival before the new departure no longer makes sense.
        if (_arrivesBy != null && _arrivesBy!.isBefore(day)) _arrivesBy = null;
      } else {
        _arrivesBy = day;
      }
    });
  }

  /// What is missing before the trip can be published, or null.
  String? _missing() {
    if (_origin.text.trim().isEmpty || _originPos == null) {
      return "Search for the From place so shippers can find this trip.";
    }
    if (_dest.text.trim().isEmpty || _destPos == null) {
      return "Search for the To place so shippers can find this trip.";
    }
    if (_leaves == null) return "Choose the day the trip leaves.";
    if (_arrivesBy == null) return "Choose the day the trip arrives by.";
    if (_truckSize == null) return _chooseTruckSizeSentence;
    final room = int.tryParse(_room.text.trim()) ?? 0;
    if (room <= 0) return "Enter the room for shippers in kg.";
    return null;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final missing = _missing();
    if (missing != null) {
      _showError(missing);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DriverSession.refresh();
      if (!mounted) return;
      final orgId = DriverSession.carrierOrgId;
      if (orgId == null || orgId.isEmpty) {
        _showError("Sign in and complete carrier registration first.");
        return;
      }
      const india = Duration(hours: 5, minutes: 30);
      // The whole of both days, in India time, as the pickup window always was.
      final windowStart = _leaves!.subtract(india);
      final windowEnd = _arrivesBy!
          .add(const Duration(days: 1))
          .subtract(india)
          .subtract(const Duration(seconds: 1));
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/anchor-trips",
        data: {
          "orgId": orgId,
          "originCity": _origin.text.trim(),
          "destCity": _dest.text.trim(),
          "origin": {
            "lat": _originPos!.latitude,
            "lng": _originPos!.longitude,
            "label": _origin.text.trim()
          },
          "destination": {
            "lat": _destPos!.latitude,
            "lng": _destPos!.longitude,
            "label": _dest.text.trim()
          },
          "windowStart": formatIstIsoFromUtc(windowStart),
          "windowEnd": formatIstIsoFromUtc(windowEnd),
          "vehicleClass": _truckSize,
          "capacityKg": int.parse(_room.text.trim()),
        },
      );
      // Both: the screen may already be gone, having kept the draft, when the publish lands.
      _published = true;
      _publishDraft = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(tripPublishedMessage());
      context.go("/driver/loads");
    } catch (e) {
      if (mounted) _showError(ewayBillErrorSentence(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _day(String label, DateTime? day, {required bool leaves}) =>
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: NvText.bodyStrong),
            const SizedBox(height: 6),
            NvButton(
              label: day == null
                  ? "Choose a date"
                  : formatDate(day, withYear: true),
              kind: NvButtonKind.secondary,
              onPressed: () => _chooseDay(leaves: leaves),
              fullWidth: true,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: NvSpace.s4);
    return Column(children: [
      Expanded(
        // A tap outside the fields closes the keyboard; the fields and buttons still take their own taps.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListView(
            controller: _form,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
            children: [
              if (_error != null) ...[
                NvMessage(_error!, tone: NvMessageTone.problem),
                gap,
              ],
              const Text("Shippers can book space on it once it is published.",
                  style: NvText.body),
              gap,
              // Each map shows once its place has a point, so the form stays short while typing.
              LocationEndpointEditor(
                title: "From",
                hint: "City or area",
                labelController: _origin,
                markerId: "pub_origin",
                markerHue: BitmapDescriptor.hueOrange,
                position: _originPos ?? pinNotPlacedYet,
                onPositionChanged: (p) => setState(() => _originPos = p),
                showMap: _originPos != null,
                findPlace: widget.findPlace,
              ),
              gap,
              LocationEndpointEditor(
                title: "To",
                hint: "City or area",
                labelController: _dest,
                markerId: "pub_dest",
                markerHue: BitmapDescriptor.hueAzure,
                position: _destPos ?? pinNotPlacedYet,
                onPositionChanged: (p) => setState(() => _destPos = p),
                showMap: _destPos != null,
                findPlace: widget.findPlace,
              ),
              gap,
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _day("Leaves", _leaves, leaves: true)),
                const SizedBox(width: NvSpace.s3),
                Expanded(
                    child: _day("Arrives by", _arrivesBy, leaves: false)),
              ]),
              gap,
              NvChoiceChips<String>(
                label: "Truck size",
                options: _truckSizes,
                selected: _truckSize,
                onChanged: (size) => setState(() => _truckSize = size),
              ),
              gap,
              NvField(
                label: "Room for shippers",
                controller: _room,
                unit: "kg",
                keyboardType: TextInputType.number,
                help: "The weight you can carry for shippers on this trip.",
              ),
              const SizedBox(height: NvSpace.s3),
              const Text("You choose the truck when you accept the first booking.",
                  style: NvText.caption),
            ],
          ),
        ),
      ),
      NvActionBar(
        child: NvButton(
          label: "Publish trip",
          onPressed: _submit,
          loading: _submitting,
          loadingLabel: "Publishing",
          fullWidth: true,
        ),
      ),
    ]);
  }
}

/// Driver navigation uses [ShellRoute] so the bottom nav stays mounted.
///
/// Alternatives considered:
/// - **Per-screen [DriverShell] + flat [GoRoute]s** (previous): simple but no real stack;
///   Android back with only [go] caused empty pop / instability.
/// - **IndexedStack tab state**: persistent tabs but poor deep-linking and URL sync.
/// - **Full-screen detail routes on root navigator**: hides nav on drill-down; rejected for flow continuity.
///
/// Chosen: shell navigator for tabs + [push] for drill-down (active trip, POD, earnings stack);
/// [go] for tab switches; [PopScope] sends back to `/driver` from tab roots.
List<RouteBase> driverFlowRoutes() {
  return [
    ShellRoute(
      navigatorKey: driverShellNavigatorKey,
      builder: (context, state, child) {
        final path = state.uri.path;
        return DriverShell(
          currentPath: path,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: "/driver",
          builder: (_, __) => const DriverWelcomeScreen(),
          routes: [
            GoRoute(
                path: "shipments",
                builder: (_, __) => const DriverShipmentsScreen()),
            GoRoute(
              path: "shipment/:shipmentId",
              builder: (_, state) => DriverShipmentDetailScreen(
                  shipmentId: state.pathParameters["shipmentId"] ?? ""),
              routes: [
                GoRoute(
                  path: "pod",
                  builder: (_, state) => DriverPodScreen(
                      shipmentId: state.pathParameters["shipmentId"] ?? ""),
                ),
              ],
            ),
            GoRoute(
                path: "loads", builder: (_, __) => const DriverLoadsScreen()),
            GoRoute(
                path: "publish",
                builder: (_, __) => const DriverPublishTripScreen()),
            GoRoute(
                path: "track", builder: (_, __) => const DriverTrackScreen()),
            GoRoute(
                path: "profile",
                builder: (_, __) => const DriverProfileScreen()),
            GoRoute(
                path: "fleet",
                builder: (_, __) => const DriverFleetInviteScreen()),
            GoRoute(
              path: "trip/:tripId/active",
              builder: (_, state) => DriverActiveTripScreen(
                  tripId: state.pathParameters["tripId"] ?? ""),
            ),
            GoRoute(
              path: "trip/:tripId/eway-bills",
              builder: (_, state) => DriverTripEwayBillsScreen(
                  tripId: state.pathParameters["tripId"] ?? ""),
            ),
            GoRoute(
                path: "earnings",
                builder: (_, __) => const DriverEarningsScreen()),
            GoRoute(
                path: "payout-setup",
                builder: (_, __) => const DriverPayoutSetupScreen()),
            GoRoute(
                path: "payout-history",
                builder: (_, __) => const DriverPayoutHistoryScreen()),
          ],
        ),
      ],
    ),
    // The carriers' old sign-in addresses, kept so saved links still open the one sign-in.
    GoRoute(
        path: "/driver/onboarding/phone",
        redirect: (_, __) => "/customer/login"),
    GoRoute(
        path: "/driver/onboarding/otp",
        redirect: (_, state) {
          final phone = state.uri.queryParameters["phone"];
          return phone == null
              ? "/customer/login"
              : "/customer/login?phone=${Uri.encodeQueryComponent(phone)}";
        }),
    GoRoute(
        path: "/driver/onboarding/register",
        builder: (_, __) => const DriverRegisterScreen()),
    GoRoute(
        path: "/driver/onboarding/join",
        builder: (_, __) => const DriverJoinScreen()),
  ];
}
