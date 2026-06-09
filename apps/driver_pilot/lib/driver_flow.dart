import "dart:async";

import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "driver_session.dart";
import "driver_theme.dart";
import "google_geocoding.dart";
import "location_editor.dart";
import "maps_config.dart";
import "pilot_api.dart";

/// Nested navigator for the driver shell (tabs + pushed detail routes).
final GlobalKey<NavigatorState> driverShellNavigatorKey = GlobalKey<NavigatorState>();

/// App bar title from the current driver route.
String driverShellTitle(String path) {
  if (path == "/driver") return "NaviG8r";
  if (path.startsWith("/driver/shipments")) return "Shipments";
  if (path.startsWith("/driver/loads")) return "Loads";
  if (path.startsWith("/driver/publish")) return "Publish trip";
  if (path.startsWith("/driver/track")) return "Track";
  if (path.startsWith("/driver/profile")) return "Profile";
  if (path.startsWith("/driver/fleet")) return "Fleet";
  if (path.startsWith("/driver/trip/")) return "Active trip";
  if (path.startsWith("/driver/shipment/")) return "Proof of delivery";
  if (path.startsWith("/driver/earnings")) return "Earnings";
  if (path.startsWith("/driver/payout-setup")) return "Payout method";
  if (path.startsWith("/driver/payout-history")) return "Payout history";
  return "NaviG8r";
}

/// Bottom-nav shell for the carrier driver journey (single instance via [ShellRoute]).
class DriverShell extends StatelessWidget {
  const DriverShell({
    required this.title,
    required this.currentPath,
    required this.child,
    this.actions,
    this.showBottomNav = true,
    super.key,
  });

  final String title;
  final String currentPath;
  final Widget child;
  final List<Widget>? actions;
  final bool showBottomNav;

  int _indexForPath(String path) {
    if (path.startsWith("/driver/shipments") || path.startsWith("/driver/shipment/")) {
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

  String _pathForIndex(int index) {
    switch (index) {
      case 1:
        return "/driver/shipments";
      case 2:
        return "/driver/loads";
      case 3:
        return "/driver/publish";
      case 4:
        return "/driver/profile";
      case 0:
      default:
        return "/driver";
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexForPath(currentPath);
    final shellNav = Navigator.of(context);
    final canPop = shellNav.canPop();

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // Tab roots have no stack entry — back goes to driver home instead of crashing.
        if (currentPath != "/driver" && currentPath.startsWith("/driver")) {
          context.go("/driver");
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                )
              : null,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 26)),
          actions: [
            if (actions != null) ...actions!,
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(backgroundColor: DriverTheme.navy, radius: 18),
            ),
          ],
        ),
        body: SafeArea(child: child),
        bottomNavigationBar: showBottomNav
            ? NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (index) {
                  final target = _pathForIndex(index);
                  if (target != currentPath) context.go(target);
                },
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Home"),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: "Shipments",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.local_shipping_outlined),
                    selectedIcon: Icon(Icons.local_shipping),
                    label: "Loads",
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.add_road_outlined),
                    selectedIcon: Icon(Icons.add_road),
                    label: "Publish",
                  ),
                  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: "Profile"),
                ],
              )
            : null,
      ),
    );
  }
}

class DriverWelcomeScreen extends StatelessWidget {
  const DriverWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Driver & carrier",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: DriverTheme.navy),
          ),
          const SizedBox(height: 12),
          const Text(
            "Sign in with your phone, confirm your carrier organization, run trips with live tracking, "
            "and get paid after proof of delivery and cooling-off.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => context.go("/driver/onboarding/phone"),
            child: const Text("Sign in with phone"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go("/driver/onboarding/register"),
            child: const Text("Register as new carrier"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              final ok = await DriverSession.refresh();
              if (!context.mounted) return;
              if (ok && DriverSession.hasCarrierOrg) {
                context.go("/driver/loads");
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Sign in first, or complete carrier registration.")),
                );
              }
            },
            child: const Text("Continue as signed-in driver"),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.go("/driver/onboarding/join"), child: const Text("Join a carrier fleet")),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.go("/pilot-lab"), child: const Text("Developer lab")),
        ],
      ),
    );
  }
}

class DriverPhoneScreen extends StatefulWidget {
  const DriverPhoneScreen({super.key});

  @override
  State<DriverPhoneScreen> createState() => _DriverPhoneScreenState();
}

class _DriverPhoneScreenState extends State<DriverPhoneScreen> {
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final phone = digitsOnly(_phone.text.trim());
    if (phone.length != 10) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a 10-digit mobile number.")));
      return;
    }
    try {
      await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone});
      if (!mounted) return;
      context.go("/driver/onboarding/otp?phone=$phone");
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign in")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Mobile number", hintText: "+91 …"),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Send code"),
            ),
            TextButton(onPressed: () => context.go("/driver"), child: const Text("Back")),
          ],
        ),
      ),
    );
  }
}

class DriverOtpScreen extends StatefulWidget {
  const DriverOtpScreen({super.key});

  @override
  State<DriverOtpScreen> createState() => _DriverOtpScreenState();
}

class _DriverOtpScreenState extends State<DriverOtpScreen> {
  final _challengeId = TextEditingController();
  final _code = TextEditingController();
  bool _starting = false;
  bool _verifying = false;
  String? _debugCode;
  String _phone = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = GoRouterState.of(context).uri.queryParameters["phone"] ?? "";
    if (p.isNotEmpty && p != _phone) {
      _phone = p;
      _resend();
    }
  }

  Future<void> _resend() async {
    setState(() => _starting = true);
    try {
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": _phone});
      final id = r.data?["challengeId"] as String?;
      if (id != null) _challengeId.text = id;
      final dc = r.data?["debugCode"];
      if (dc is String && dc.isNotEmpty) {
        _debugCode = dc;
        _code.text = dc;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {"phone": _phone, "challengeId": _challengeId.text.trim(), "code": _code.text.trim()},
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      await DriverSession.refresh();
      if (!mounted) return;
      if (DriverSession.hasCarrierOrg) {
        context.go("/driver/loads");
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No carrier org for this phone. Use Register as new carrier on the welcome screen."),
          ),
        );
        context.go("/driver");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _challengeId.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify code")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text("Code sent to $_phone", style: const TextStyle(color: DriverTheme.muted)),
          if (_debugCode != null) ...[
            const SizedBox(height: 8),
            Text("Debug OTP: $_debugCode", style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
          ],
          const SizedBox(height: 16),
          TextField(controller: _challengeId, decoration: const InputDecoration(labelText: "Challenge id")),
          TextField(controller: _code, decoration: const InputDecoration(labelText: "6-digit code")),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _verifying ? null : _verify,
            child: _verifying
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Verify"),
          ),
          TextButton(onPressed: _starting ? null : _resend, child: const Text("Resend code")),
        ],
      ),
    );
  }
}

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
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    _reg.dispose();
    _vehClass.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      if (phone.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a 10-digit phone number.")));
        return;
      }
      final cap = int.tryParse(_cap.text.trim()) ?? 0;
      if (cap <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a positive vehicle capacity.")));
        return;
      }
      final vc = _vehClass.text.trim().toUpperCase();
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/driver/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": phone,
          "orgDisplayName": _org.text.trim(),
          "vehicleRegistrationNumber": _reg.text.trim(),
          "vehicleClass": vc,
          "vehicleCapacityKg": cap,
        },
      );
      final orgId = orgIdFromRegisterResponse(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Carrier created — verify your phone to continue.")),
      );
      context.go("/driver/onboarding/otp?phone=$phone");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Your full name")),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone (10 digits)")),
          TextField(controller: _org, decoration: const InputDecoration(labelText: "Carrier / org display name")),
          TextField(controller: _reg, decoration: const InputDecoration(labelText: "Your vehicle registration")),
          TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "Vehicle class (SMALL|MEDIUM|LARGE)")),
          TextField(controller: _cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Vehicle capacity (kg)")),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create carrier & continue"),
          ),
          TextButton(onPressed: () => context.go("/driver"), child: const Text("Back")),
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
        const SnackBar(content: Text("Account created — ask your carrier admin to invite you, then sign in.")),
      );
      context.go("/driver/onboarding/phone");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Your full name")),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Phone (10 digits)")),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
          TextButton(onPressed: () => context.go("/driver"), child: const Text("Back")),
        ],
      ),
    );
  }
}

class DriverFleetInviteScreen extends StatefulWidget {
  const DriverFleetInviteScreen({super.key});

  @override
  State<DriverFleetInviteScreen> createState() => _DriverFleetInviteScreenState();
}

class _DriverFleetInviteScreenState extends State<DriverFleetInviteScreen> {
  final _phone = TextEditingController();
  final _reg = TextEditingController();
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  String _role = "DRIVER";
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
    _vehClass.dispose();
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
    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        "orgId": orgId,
        "phone": digitsOnly(_phone.text.trim()),
        "role": _role,
      };
      if (_role == "DRIVER") {
        final cap = int.tryParse(_cap.text.trim()) ?? 0;
        payload["vehicleRegistrationNumber"] = _reg.text.trim();
        payload["vehicleClass"] = _vehClass.text.trim().toUpperCase();
        payload["vehicleCapacityKg"] = cap;
      }
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/carrier/drivers/invite",
        data: payload,
      );
      _phone.clear();
      _reg.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Driver invited to your carrier org.")));
    } catch (e) {
      setState(() => _error = formatApiError(e));
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
          style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          "Invite a driver who already registered their phone (or used Join a fleet). Solo orgs become fleet when you add drivers.",
          style: TextStyle(color: DriverTheme.muted, height: 1.4),
        ),
        if (!DriverSession.canInviteDrivers) ...[
          const SizedBox(height: 12),
          Text(_error ?? "Not authorized.", style: const TextStyle(color: Colors.red)),
        ] else ...[
          const SizedBox(height: 16),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Driver phone (10 digits)")),
          DropdownButtonFormField<String>(
            value: _role,
            decoration: const InputDecoration(labelText: "Role"),
            items: const [
              DropdownMenuItem(value: "DRIVER", child: Text("Driver")),
              DropdownMenuItem(value: "DISPATCHER", child: Text("Dispatcher")),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _role = v);
            },
          ),
          if (_role == "DISPATCHER") ...[
            const SizedBox(height: 8),
            const Text(
              "Dispatchers are linked to your carrier org's primary vehicle — no separate truck registration needed.",
              style: TextStyle(fontSize: 12, color: DriverTheme.muted, height: 1.35),
            ),
          ] else ...[
            TextField(controller: _reg, decoration: const InputDecoration(labelText: "Vehicle registration")),
            TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "Vehicle class (SMALL|MEDIUM|LARGE)")),
            TextField(controller: _cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Vehicle capacity (kg)")),
          ],
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.push("/driver/onboarding/join"), child: const Text("New driver? Register account first")),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _inviting ? null : _invite,
            child: _inviting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_role == "DISPATCHER" ? "Invite dispatcher" : "Invite driver"),
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

class DriverShipmentsScreen extends StatefulWidget {
  const DriverShipmentsScreen({super.key});

  @override
  State<DriverShipmentsScreen> createState() => _DriverShipmentsScreenState();
}

class _DriverShipmentsScreenState extends State<DriverShipmentsScreen> {
  List<Map<String, dynamic>> _shipments = [];
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
      final raw = r.data?["shipments"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map<String, dynamic>) {
            final st = s["status"]?.toString() ?? "";
            if (st == "PENDING_CARRIER_ACCEPT" || st == "BOOKED" || st == "PENDING_RELEASE") list.add(s);
          }
        }
      }
      setState(() => _shipments = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _acceptShipment(String shipmentId) async {
    try {
      await api.post<Map<String, dynamic>>("/v1/pilot/carrier/shipments/$shipmentId/accept");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking accepted.")));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
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
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Customer bookings — accept new requests, then confirm delivery when drop-off is complete.",
            style: TextStyle(color: DriverTheme.muted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_loading) const Center(child: CircularProgressIndicator()),
          ..._shipments.map((s) {
            final id = s["id"]?.toString() ?? "";
            final st = s["status"]?.toString() ?? "";
            final stLabel = shipmentStatusLabel(st);
            return Card(
              child: ListTile(
                title: Text("${s["customerOrgName"]} · ${s["weightKg"]} kg"),
                subtitle: Text("$stLabel · ${s["pickupAddress"]} → ${s["dropAddress"]}"),
                trailing: st == "PENDING_CARRIER_ACCEPT"
                    ? FilledButton(
                        onPressed: () => _acceptShipment(id),
                        child: const Text("Accept"),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: st == "PENDING_CARRIER_ACCEPT" ? null : () => context.push("/driver/shipment/$id"),
              ),
            );
          }),
          if (!_loading && _shipments.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 24), child: Text("No shipments to deliver.", style: TextStyle(color: DriverTheme.muted))),
        ],
      ),
    );
  }
}

class DriverShipmentDetailScreen extends StatefulWidget {
  const DriverShipmentDetailScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<DriverShipmentDetailScreen> createState() => _DriverShipmentDetailScreenState();
}

class _DriverShipmentDetailScreenState extends State<DriverShipmentDetailScreen> {
  Map<String, dynamic>? _shipment;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await api.post<Map<String, dynamic>>("/v1/pilot/carrier/shipments/${widget.shipmentId}/accept");
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking accepted.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _load() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/carrier/shipments");
      final raw = r.data?["shipments"];
      if (raw is List) {
        for (final s in raw) {
          if (s is Map<String, dynamic> && s["id"] == widget.shipmentId) {
            setState(() => _shipment = s);
            return;
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _shipment;
    if (s == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final st = s["status"]?.toString() ?? "";
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s["customerOrgName"]?.toString() ?? "", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: DriverTheme.navy)),
          const SizedBox(height: 8),
          Text("Status: ${shipmentStatusLabel(st)}", style: const TextStyle(color: DriverTheme.muted)),
          const SizedBox(height: 12),
          Text("Pickup: ${s["pickupAddress"]}"),
          Text("Drop: ${s["dropAddress"]}"),
          Text("Net to carrier: ${formatInrFromPaise(s["netToCarrierPaise"] as num? ?? 0)}"),
          const Spacer(),
          if (st == "PENDING_CARRIER_ACCEPT")
            FilledButton(
              onPressed: _accepting ? null : _accept,
              child: _accepting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Accept booking"),
            ),
          if (st == "BOOKED")
            FilledButton(
              onPressed: () => context.push("/driver/shipment/${widget.shipmentId}/pod"),
              child: const Text("Confirm delivery"),
            ),
          if (st == "PENDING_RELEASE")
            const Text("Awaiting ops payment release.", style: TextStyle(color: DriverTheme.muted)),
        ],
      ),
    );
  }
}

class DriverLoadsScreen extends StatefulWidget {
  const DriverLoadsScreen({super.key});

  @override
  State<DriverLoadsScreen> createState() => _DriverLoadsScreenState();
}

class _DriverLoadsScreenState extends State<DriverLoadsScreen> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = false;
  String? _error;
  /// API `vehicleClass`: All | SMALL | MEDIUM | LARGE
  String _vehicleClass = "All";
  /// API `status`: All | OPEN | FULL | IN_PROGRESS | COMPLETED
  String _status = "All";

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DriverSession.refresh();
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
      final raw = r.data?["trips"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _trips = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _statusRank(String status) {
    switch (status) {
      case "IN_PROGRESS":
        return 0;
      case "OPEN":
        return 1;
      case "FULL":
        return 2;
      case "COMPLETED":
        return 3;
      default:
        return 4;
    }
  }

  Future<void> _startTrip(String tripId) async {
    try {
      await api.post<Map<String, dynamic>>("/v1/pilot/anchor-trips/$tripId/start");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Load started — live tracking enabled.")));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_trips);
    if (_vehicleClass != "All") {
      list = list.where((t) => (t["vehicleClass"]?.toString() ?? "") == _vehicleClass).toList();
    }
    if (_status != "All") {
      list = list.where((t) => (t["status"]?.toString() ?? "") == _status).toList();
    }
    list.sort((a, b) {
      final sa = a["status"]?.toString() ?? "";
      final sb = b["status"]?.toString() ?? "";
      final ra = _statusRank(sa);
      final rb = _statusRank(sb);
      if (ra != rb) return ra.compareTo(rb);
      final ca = a["createdAtUtcMs"];
      final cb = b["createdAtUtcMs"];
      if (ca is num && cb is num) return cb.compareTo(ca);
      return 0;
    });
    return list;
  }

  String _vehicleChipLabel(String apiValue) {
    switch (apiValue) {
      case "SMALL":
        return "Small";
      case "MEDIUM":
        return "Medium";
      case "LARGE":
        return "Large";
      default:
        return apiValue;
    }
  }

  String _statusChipLabel(String apiValue) {
    return tripStatusLabel(apiValue);
  }

  String _loadsSummary() {
    final org = DriverSession.carrierOrgName ?? "Your carrier";
    if (_trips.isEmpty) {
      return "$org · No anchor trips · tap Publish to add a lane";
    }
    final open = _trips.where((t) => t["status"] == "OPEN").length;
    final full = _trips.where((t) => t["status"] == "FULL").length;
    final active = _trips.where((t) => (t["reservedKg"] as num? ?? 0) > 0).length;
    return "$org · $open open · $full full · $active with bookings";
  }

  @override
  Widget build(BuildContext context) {
    final summary = _loadsSummary();

    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DriverTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 20, color: DriverTheme.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(summary, style: const TextStyle(color: DriverTheme.muted, fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Vehicle", style: TextStyle(fontSize: 12, color: DriverTheme.muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["All", "SMALL", "MEDIUM", "LARGE"].map((value) {
                  final active = _vehicleClass == value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(value == "All" ? "All" : _vehicleChipLabel(value)),
                      selected: active,
                      onSelected: (_) => setState(() => _vehicleClass = value),
                      selectedColor: DriverTheme.navy,
                      labelStyle: TextStyle(color: active ? Colors.white : DriverTheme.navy),
                      showCheckmark: false,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Trip status", style: TextStyle(fontSize: 12, color: DriverTheme.muted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["All", "IN_PROGRESS", "OPEN", "FULL", "COMPLETED"].map((value) {
                  final active = _status == value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(value == "All" ? "All" : _statusChipLabel(value)),
                      selected: active,
                      onSelected: (_) => setState(() => _status = value),
                      selectedColor: DriverTheme.navy,
                      labelStyle: TextStyle(color: active ? Colors.white : DriverTheme.navy),
                      showCheckmark: false,
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _trips.isNotEmpty && _filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text("No trips match these filters.", style: TextStyle(color: DriverTheme.muted)),
              ),
            ..._filtered.map(
              (t) => _LoadCard(
                trip: t,
                onView: () => context.push("/driver/trip/${t["id"]}/active"),
                onStart: () => _startTrip(t["id"]?.toString() ?? ""),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.trip, required this.onView, required this.onStart});

  final Map<String, dynamic> trip;
  final VoidCallback onView;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final route = "${trip["originCity"]} → ${trip["destCity"]}";
    final cap = (trip["capacityKg"] as num?)?.toInt() ?? 0;
    final res = (trip["reservedKg"] as num?)?.toInt() ?? 0;
    final available = cap - res;
    final status = trip["status"]?.toString() ?? "";
    final vClass = trip["vehicleClass"]?.toString() ?? "";
    final hasBookings = res > 0;

    final statusLabel = tripStatusLabel(status);
    final canStart = hasBookings && status != "IN_PROGRESS" && status != "COMPLETED";

    final tags = <Widget>[
      Chip(label: Text(statusLabel), visualDensity: VisualDensity.compact),
      Chip(label: Text(vClass), visualDensity: VisualDensity.compact),
      if (status == "OPEN" && available > 0)
        Chip(label: Text("$available kg available"), visualDensity: VisualDensity.compact),
      if (hasBookings) const Chip(label: Text("Has bookings"), visualDensity: VisualDensity.compact),
    ];

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(route, style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy)),
                ),
                Text("$res / $cap kg", style: const TextStyle(fontWeight: FontWeight.w600, color: DriverTheme.navy, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "${_formatVehicle(vClass)} vehicle · $res kg booked on this lane",
              style: const TextStyle(fontSize: 12, color: DriverTheme.muted),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: tags),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _formatWindow(trip["windowStart"]?.toString()),
                    style: const TextStyle(fontSize: 11, color: DriverTheme.muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canStart) ...[
                  OutlinedButton(onPressed: onStart, child: const Text("Start")),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: onView,
                  child: Text(status == "IN_PROGRESS" ? "Track" : hasBookings ? "View" : "View"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatVehicle(String v) {
    switch (v) {
      case "SMALL":
        return "Small";
      case "MEDIUM":
        return "Medium";
      case "LARGE":
        return "Large";
      default:
        return v;
    }
  }

  static String _formatWindow(String? iso) {
    if (iso == null || iso.isEmpty) return "Pickup window not set";
    // Show date portion for IST-style strings e.g. 2026-05-12T00:00:00+05:30
    final t = iso.indexOf("T");
    if (t > 0) return "Window from ${iso.substring(0, t)}";
    return "Window $iso";
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
          if (item is Map<String, dynamic> && (item["reservedKg"] as num? ?? 0) > 0) list.add(item);
        }
      }
      setState(() => _trips = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
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
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Trips with reserved capacity — open for live GPS tracking while in progress.",
              style: TextStyle(color: DriverTheme.muted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading) const Center(child: CircularProgressIndicator()),
            ..._trips.map(
              (t) => ListTile(
                title: Text("${t["originCity"]} → ${t["destCity"]}"),
                subtitle: Text("Reserved ${t["reservedKg"]}kg · ${t["status"]}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push("/driver/trip/${t["id"]}/active"),
              ),
            ),
          ],
        ),
      );
  }
}

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  @override
  void initState() {
    super.initState();
    DriverSession.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text(DriverSession.carrierOrgName ?? "Carrier"),
            subtitle: Text("${DriverSession.userFullName ?? "—"} · ${DriverSession.userPhone ?? "—"}"),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.payments_outlined, color: DriverTheme.navy),
          title: const Text("Earnings & payouts"),
          subtitle: Text(DriverSession.payoutSetupComplete ? "Payout method on file" : "Set up before first transfer"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push("/driver/earnings"),
        ),
        ListTile(
          leading: const Icon(Icons.add_road, color: DriverTheme.navy),
          title: const Text("Publish anchor trip"),
          onTap: () => context.go("/driver/publish"),
        ),
        if (DriverSession.canInviteDrivers)
          ListTile(
            leading: const Icon(Icons.groups_outlined, color: DriverTheme.navy),
            title: const Text("Fleet — invite drivers"),
            subtitle: const Text("Add drivers or dispatchers to your carrier org"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push("/driver/fleet"),
          ),
        ListTile(
          leading: const Icon(Icons.logout, color: DriverTheme.navy),
          title: const Text("Sign out"),
          onTap: () async {
            await api.clearToken();
            DriverSession.clear();
            if (context.mounted) context.go("/driver");
          },
        ),
      ],
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _load();
    _startLocation();
  }

  Future<void> _startLocation() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    try {
      final p = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _driverPos = LatLng(p.latitude, p.longitude));
    } catch (_) {}
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(distanceFilter: 25),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _driverPos = LatLng(p.latitude, p.longitude));
      _maybePostLocation(p);
    });
  }

  Future<void> _acceptOnTrip(String shipmentId) async {
    try {
      await api.post<Map<String, dynamic>>("/v1/pilot/carrier/shipments/$shipmentId/accept");
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Booking accepted.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    }
  }

  Future<void> _startTrip() async {
    setState(() => _starting = true);
    try {
      final r = await api.post<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}/start");
      final t = r.data?["trip"];
      if (t is Map<String, dynamic>) setState(() => _trip = t);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Load started.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _maybePostLocation(Position p) async {
    if (_trip?["status"]?.toString() != "IN_PROGRESS") return;
    final now = DateTime.now();
    if (_lastLocationPostAt != null && now.difference(_lastLocationPostAt!) < const Duration(seconds: 30)) {
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
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}");
      final t = r.data?["trip"];
      setState(() => _trip = t is Map<String, dynamic> ? t : null);
    } catch (e) {
      setState(() => _error = formatApiError(e));
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
      final msg = formatApiError(e);
      if (mounted) {
        setState(() {
          _shipments = [];
          _error = _error == null
              ? "$msg\n(Shipment list needs API deploy — merge driver-onboarding PR.)"
              : _error;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _geocodeTripCitiesIfNeeded();
  }

  Future<void> _geocodeTripCitiesIfNeeded() async {
    final trip = _trip;
    if (trip == null) return;
    if (latLngFromGeoMap(trip, "origin") != null && latLngFromGeoMap(trip, "destination") != null) return;
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

  ({LatLng? laneStart, LatLng? laneEnd, LatLng? pickup, LatLng? drop}) _resolvedMapPoints() {
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
    _posSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final tripStatus = trip?["status"]?.toString() ?? "";
    final tripStarted = tripStatus == "IN_PROGRESS";
    final hasAccepted = _shipments.any((s) => s["status"]?.toString() == "BOOKED");
    final pts = _resolvedMapPoints();
    Map<String, dynamic>? next;
    for (final s in _shipments) {
      if (s["status"]?.toString() == "BOOKED") {
        next = s;
        break;
      }
    }
    next ??= _shipments.isNotEmpty ? _shipments.first : null;
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: activeTripMap(
                    laneStart: pts.laneStart,
                    laneEnd: pts.laneEnd,
                    driver: _driverPos,
                    pickup: pts.pickup,
                    drop: pts.drop,
                    emptyMessage: trip == null
                        ? "Could not load trip."
                        : "No coordinates yet — allow location, or republish trip with map pins.",
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                      Text(
                        tripStarted ? "Load in progress" : "Load not started",
                        style: const TextStyle(color: DriverTheme.muted, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        "Status: ${tripStatusLabel(tripStatus)}",
                        style: const TextStyle(color: DriverTheme.muted, fontSize: 13),
                      ),
                      if (!tripStarted && hasAccepted) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _starting ? null : _startTrip,
                          child: _starting
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text("Start load"),
                        ),
                      ],
                      if (!tripStarted && !hasAccepted)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "Accept customer bookings on Shipments before starting.",
                            style: TextStyle(color: DriverTheme.muted, fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        next != null ? "Next pickup: ${next["pickupAddress"]}" : "No shipments on this trip yet",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DriverTheme.navy),
                      ),
                      const SizedBox(height: 12),
                      ..._shipments.map((s) {
                        final id = s["id"]?.toString() ?? "";
                        final st = s["status"]?.toString() ?? "";
                        return Card(
                          child: ListTile(
                            title: Text("${s["customerOrgName"]} · ${s["weightKg"]}kg"),
                            subtitle: Text("${shipmentStatusLabel(st)} · ${formatInrFromPaise(s["netToCarrierPaise"] as num? ?? 0)} net"),
                            trailing: st == "PENDING_CARRIER_ACCEPT"
                                ? TextButton(onPressed: () => _acceptOnTrip(id), child: const Text("Accept"))
                                : st == "BOOKED"
                                ? TextButton(
                                    onPressed: () => context.push("/driver/shipment/$id/pod"),
                                    child: const Text("Confirm delivery"),
                                  )
                                : st == "PENDING_RELEASE"
                                    ? const Text("Awaiting ops", style: TextStyle(fontSize: 12, color: DriverTheme.muted))
                                    : null,
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton(onPressed: () {}, child: const Text("Share live")),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: next != null && next["status"] == "BOOKED"
                                  ? () => context.push("/driver/shipment/${next!["id"]}/pod")
                                  : null,
                              child: const Text("Mark arrived / POD"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
  }
}

class DriverPodScreen extends StatefulWidget {
  const DriverPodScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<DriverPodScreen> createState() => _DriverPodScreenState();
}

class _DriverPodScreenState extends State<DriverPodScreen> {
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final notes = _notes.text.trim();
      await api.post<Map<String, dynamic>>(
        "/shipments/${widget.shipmentId}/driver-pod",
        data: notes.isEmpty ? {} : {"notes": notes},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Delivery confirmed. Payment will be released after ops review.",
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Confirming delivery submits proof of delivery to the platform. Ops will release customer payment to your carrier ledger after review.",
            style: TextStyle(color: DriverTheme.muted),
          ),
          const SizedBox(height: 16),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: "Notes (optional)"), maxLines: 3),
          const Spacer(),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Confirm POD"),
          ),
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
      final orgId = DriverSession.carrierOrgId ?? lastRegisteredOrgId ?? "";
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/carrier/earnings", query: {"orgId": orgId});
      setState(() => _summary = r.data?["summary"] as Map<String, dynamic>?);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final pending = s?["pendingAccruedPaise"] as num? ?? 0;
    final paid = s?["paidPaise"] as num? ?? 0;
    final kyc = s?["kycStatus"]?.toString() ?? DriverSession.kycStatus ?? "NOT_STARTED";

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(child: _StatTile(label: "Pending (accrued)", value: formatInrFromPaise(pending))),
                  const SizedBox(width: 12),
                  Expanded(child: _StatTile(label: "Paid out", value: formatInrFromPaise(paid))),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    kyc == "NOT_STARTED"
                        ? "Customer payments sit on the platform ledger until you add a verified payout method. No bank details required at signup."
                        : "Payout profile status: $kyc",
                    style: const TextStyle(color: DriverTheme.muted),
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => context.push("/driver/payout-setup"),
                child: Text(kyc == "NOT_STARTED" ? "Set up payouts" : "Update payout method"),
              ),
              OutlinedButton(onPressed: () => context.push("/driver/payout-history"), child: const Text("Payout history")),
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
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: DriverTheme.navy)),
            Text(label, style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
          ],
        ),
      ),
    );
  }
}

class DriverPayoutSetupScreen extends StatefulWidget {
  const DriverPayoutSetupScreen({super.key});

  @override
  State<DriverPayoutSetupScreen> createState() => _DriverPayoutSetupScreenState();
}

class _DriverPayoutSetupScreenState extends State<DriverPayoutSetupScreen> {
  final _name = TextEditingController();
  final _ifsc = TextEditingController();
  final _accountNumber = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ifsc.dispose();
    _accountNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final orgId = DriverSession.carrierOrgId ?? lastRegisteredOrgId ?? "";
      final acct = _accountNumber.text.trim();
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/carrier/payout-setup",
        data: {
          "orgId": orgId,
          "accountHolderName": _name.text.trim(),
          "ifsc": _ifsc.text.trim(),
          if (acct.isNotEmpty) "accountNumber": acct,
        },
      );
      final msg = r.data?["message"]?.toString() ?? "Saved.";
      await DriverSession.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.push("/driver/payout-history");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Collect once before your first transfer. KYC may be required by your payment provider.",
            style: TextStyle(color: DriverTheme.muted),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: "Account holder name")),
          TextField(controller: _ifsc, decoration: const InputDecoration(labelText: "IFSC / bank identifier")),
          TextField(
            controller: _accountNumber,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Bank account number",
              helperText: "Required to receive real transfers",
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Save and verify"),
          ),
        ],
      ),
    );
  }
}

class DriverPayoutHistoryScreen extends StatefulWidget {
  const DriverPayoutHistoryScreen({super.key});

  @override
  State<DriverPayoutHistoryScreen> createState() => _DriverPayoutHistoryScreenState();
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
      final orgId = DriverSession.carrierOrgId ?? lastRegisteredOrgId ?? "";
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/carrier/payout-batches", query: {"orgId": orgId});
      final raw = r.data?["payoutBatches"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final b in raw) {
          if (b is Map<String, dynamic>) list.add(b);
        }
      }
      setState(() => _batches = list);
    } finally {
      setState(() => _loading = false);
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
                const Text("No payout batches yet. Complete POD on shipments and wait for batch settlement."),
              ..._batches.map((b) {
                return Card(
                  child: ListTile(
                    title: Text(formatInrFromPaise(b["totalNetToCarrierPaise"] as num? ?? 0)),
                    subtitle: Text("Cutoff ${b["cutoffUtcMs"]} · ${(b["lineIds"] as List?)?.length ?? 0} lines"),
                  ),
                );
              }),
            ],
          );
  }
}

class DriverPublishTripScreen extends StatefulWidget {
  const DriverPublishTripScreen({super.key});

  @override
  State<DriverPublishTripScreen> createState() => _DriverPublishTripScreenState();
}

class _DriverPublishTripScreenState extends State<DriverPublishTripScreen> {
  final _origin = TextEditingController(text: "Gurugram, Haryana");
  final _dest = TextEditingController(text: "Jaipur, Rajasthan");
  LatLng _originPos = const LatLng(28.4595, 77.0266);
  LatLng _destPos = const LatLng(26.9124, 75.7873);
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    defaultAnchorTripWindow(_w1, _w2);
    DriverSession.refresh();
  }

  @override
  void dispose() {
    _origin.dispose();
    _dest.dispose();
    _w1.dispose();
    _w2.dispose();
    _vehClass.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await DriverSession.refresh();
      final orgId = DriverSession.carrierOrgId;
      if (orgId == null || orgId.isEmpty) {
        setState(() => _error = "Sign in and complete carrier registration first.");
        return;
      }
      final cap = int.tryParse(_cap.text.trim()) ?? 0;
      if (cap <= 0) {
        setState(() => _error = "capacityKg must be a positive number.");
        return;
      }
      final vc = _vehClass.text.trim().toUpperCase();
      if (vc != "SMALL" && vc != "MEDIUM" && vc != "LARGE") {
        setState(() => _error = "vehicleClass must be SMALL, MEDIUM, or LARGE.");
        return;
      }
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/anchor-trips",
        data: {
          "orgId": orgId,
          "originCity": _origin.text.trim(),
          "destCity": _dest.text.trim(),
          "origin": {"lat": _originPos.latitude, "lng": _originPos.longitude, "label": _origin.text.trim()},
          "destination": {"lat": _destPos.latitude, "lng": _destPos.longitude, "label": _dest.text.trim()},
          "windowStart": _w1.text.trim(),
          "windowEnd": _w2.text.trim(),
          "vehicleClass": vc,
          "capacityKg": cap,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trip published.")));
      context.go("/driver/loads");
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DriverSession.carrierOrgName ?? "Your carrier",
          style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy, fontSize: 18),
        ),
        const SizedBox(height: 8),
        const Text(
          "Publish an anchor lane customers can book against. Set origin and destination on the map.",
          style: TextStyle(color: DriverTheme.muted, height: 1.35),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() => defaultAnchorTripWindow(_w1, _w2)),
          icon: const Icon(Icons.schedule),
          label: const Text("Reset pickup window (today–tomorrow, IST)"),
        ),
        const SizedBox(height: 12),
        LocationEndpointEditor(
          title: "Origin",
          hint: "Origin city or area",
          labelController: _origin,
          markerId: "pub_origin",
          markerHue: BitmapDescriptor.hueOrange,
          position: _originPos,
          onPositionChanged: (p) => setState(() => _originPos = p),
        ),
        const SizedBox(height: 16),
        LocationEndpointEditor(
          title: "Destination",
          hint: "Destination city or area",
          labelController: _dest,
          markerId: "pub_dest",
          markerHue: BitmapDescriptor.hueAzure,
          position: _destPos,
          onPositionChanged: (p) => setState(() => _destPos = p),
        ),
        const SizedBox(height: 12),
        TextField(controller: _w1, decoration: const InputDecoration(labelText: "windowStart (ISO)")),
        TextField(controller: _w2, decoration: const InputDecoration(labelText: "windowEnd (ISO)")),
        TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "vehicleClass (SMALL|MEDIUM|LARGE)")),
        TextField(controller: _cap, decoration: const InputDecoration(labelText: "capacityKg"), keyboardType: TextInputType.number),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Publish trip"),
        ),
      ],
    );
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
          title: driverShellTitle(path),
          currentPath: path,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: "/driver",
          builder: (_, __) => const DriverWelcomeScreen(),
          routes: [
            GoRoute(path: "shipments", builder: (_, __) => const DriverShipmentsScreen()),
            GoRoute(
              path: "shipment/:shipmentId",
              builder: (_, state) => DriverShipmentDetailScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
              routes: [
                GoRoute(
                  path: "pod",
                  builder: (_, state) => DriverPodScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
                ),
              ],
            ),
            GoRoute(path: "loads", builder: (_, __) => const DriverLoadsScreen()),
            GoRoute(path: "publish", builder: (_, __) => const DriverPublishTripScreen()),
            GoRoute(path: "track", builder: (_, __) => const DriverTrackScreen()),
            GoRoute(path: "profile", builder: (_, __) => const DriverProfileScreen()),
            GoRoute(path: "fleet", builder: (_, __) => const DriverFleetInviteScreen()),
            GoRoute(
              path: "trip/:tripId/active",
              builder: (_, state) => DriverActiveTripScreen(tripId: state.pathParameters["tripId"] ?? ""),
            ),
            GoRoute(path: "earnings", builder: (_, __) => const DriverEarningsScreen()),
            GoRoute(path: "payout-setup", builder: (_, __) => const DriverPayoutSetupScreen()),
            GoRoute(path: "payout-history", builder: (_, __) => const DriverPayoutHistoryScreen()),
          ],
        ),
      ],
    ),
    GoRoute(path: "/driver/onboarding/phone", builder: (_, __) => const DriverPhoneScreen()),
    GoRoute(path: "/driver/onboarding/otp", builder: (_, __) => const DriverOtpScreen()),
    GoRoute(path: "/driver/onboarding/register", builder: (_, __) => const DriverRegisterScreen()),
    GoRoute(path: "/driver/onboarding/join", builder: (_, __) => const DriverJoinScreen()),
  ];
}
