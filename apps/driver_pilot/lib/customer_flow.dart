import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:razorpay_flutter/razorpay_flutter.dart";

import "customer_session.dart";
import "driver_theme.dart";
import "location_editor.dart";
import "pilot_api.dart";

String? lastBookedShipmentId;

List<RouteBase> customerFlowRoutes() {
  return [
    GoRoute(
      path: "/customer",
      builder: (_, __) => const CustomerHomeScreen(),
      routes: [
        GoRoute(path: "login", builder: (_, __) => const CustomerLoginScreen()),
        GoRoute(path: "register", builder: (_, __) => const CustomerRegisterScreen()),
        GoRoute(path: "register-user", builder: (_, __) => const CustomerRegisterUserScreen()),
        GoRoute(path: "team", builder: (_, __) => const CustomerTeamScreen()),
        GoRoute(path: "trips", builder: (_, __) => const CustomerTripsScreen()),
        GoRoute(path: "book", builder: (_, __) => const CustomerBookShipmentScreen()),
        GoRoute(
          path: "eligible",
          redirect: (_, __) => "/customer/trips?tab=match",
        ),
        GoRoute(path: "shipments", builder: (_, __) => const CustomerShipmentsScreen()),
        GoRoute(
          path: "shipments/:shipmentId",
          builder: (_, state) => CustomerShipmentDetailScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
        ),
      ],
    ),
  ];
}

class CustomerScaffold extends StatelessWidget {
  const CustomerScaffold({
    required this.title,
    required this.currentPath,
    required this.body,
    super.key,
  });

  final String title;
  final String currentPath;
  final Widget body;

  int _indexForPath(String path) {
    if (path.startsWith("/customer/trips") || path.startsWith("/customer/eligible")) return 1;
    if (path.startsWith("/customer/book")) return 2;
    if (path.startsWith("/customer/shipments")) return 3;
    return 0;
  }

  String _pathForIndex(int index) {
    switch (index) {
      case 1:
        return "/customer/trips";
      case 2:
        return "/customer/book";
      case 3:
        return "/customer/shipments";
      case 0:
      default:
        return "/customer";
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexForPath(currentPath);
    final session = CustomerSession.isSignedIn
        ? "${CustomerSession.userFullName ?? "Signed in"} · ${CustomerSession.userPhone ?? ""}"
        : null;

    return Scaffold(
      backgroundColor: DriverTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            if (session != null)
              Text(session, style: const TextStyle(fontSize: 11, color: DriverTheme.muted, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Switch to driver",
            onPressed: () => context.go("/driver"),
            icon: const Icon(Icons.local_shipping_outlined),
          ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          final target = _pathForIndex(index);
          if (target != currentPath) context.go(target);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: "Home"),
          NavigationDestination(icon: Icon(Icons.travel_explore_outlined), selectedIcon: Icon(Icons.travel_explore), label: "Trips"),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: "Book"),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: "Shipments"),
        ],
      ),
    );
  }
}

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  @override
  void initState() {
    super.initState();
    CustomerSession.refresh().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Book freight",
      currentPath: "/customer",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Find carrier lanes, book a shipment, and track delivery from pickup to drop-off.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (!CustomerSession.isSignedIn) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Sign in to view your shipments and book with your org.", style: TextStyle(color: DriverTheme.muted)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () => context.go("/customer/login"), child: const Text("Sign in with phone")),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: () => context.go("/customer/register"), child: const Text("Register business")),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: () => context.go("/customer/register-user"), child: const Text("Register as teammate")),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (CustomerSession.isOrgAdmin) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: Text(CustomerSession.customerOrgName ?? "Your org"),
                subtitle: const Text("Manage who can book and view shipments"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go("/customer/team"),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (CustomerSession.hasCustomerOrg) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  "Signed in to ${CustomerSession.customerOrgName ?? "your org"}. Shipments booked by your team appear under My shipments.",
                  style: const TextStyle(color: DriverTheme.muted, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: () => context.go("/customer/trips"),
            icon: const Icon(Icons.travel_explore),
            label: const Text("Browse open trips"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/book"),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text("Book a shipment"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go("/customer/shipments"),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text("My shipments"),
          ),
        ],
      ),
    );
  }
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
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
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
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone});
      final dc = r.data?["debugCode"];
      if (dc is String && dc.isNotEmpty) {
        _debugCode = dc;
        _code.text = dc;
      }
    } catch (e) {
      setState(() => _error = formatApiError(e));
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
      final start = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone});
      final challengeId = start.data?["challengeId"] as String?;
      if (challengeId == null) throw Exception("Could not start OTP.");
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {"phone": phone, "challengeId": challengeId, "code": _code.text.trim()},
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      await CustomerSession.refresh();
      if (!mounted) return;
      context.go("/customer/shipments");
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Sign in",
      currentPath: "/customer/login",
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Use the phone number you registered with.", style: TextStyle(color: DriverTheme.muted)),
            if (_debugCode != null) ...[
              const SizedBox(height: 8),
              Text("Debug OTP: $_debugCode", style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Mobile number"),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _sending ? null : _sendOtp,
              child: _sending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Send code"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: "6-digit code"),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: _verifying
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Verify and continue"),
            ),
          ],
        ),
      ),
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
  State<CustomerRegisterUserScreen> createState() => _CustomerRegisterUserScreenState();
}

class _CustomerRegisterUserScreenState extends State<CustomerRegisterUserScreen> {
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
        const SnackBar(content: Text("Account created — ask your admin to invite you, then sign in.")),
      );
      context.go("/customer/login");
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Join your team",
      currentPath: "/customer/register-user",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your personal account. Your business admin will invite your phone to the org so you can book and track shared shipments.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Your name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone (10 digits)"), keyboardType: TextInputType.phone),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
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
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/customer/members?orgId=$orgId");
      final raw = r.data?["members"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _members = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Teammate invited.")));
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Team",
      currentPath: "/customer/team",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            CustomerSession.customerOrgName ?? "Your organization",
            style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Invite colleagues who have already registered their phone. They will see all org shipments after joining.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          if (!CustomerSession.isOrgAdmin) ...[
            const SizedBox(height: 12),
            Text(_error ?? "Admin access required.", style: const TextStyle(color: Colors.red)),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Teammate phone (10 digits)"),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _inviting ? null : _invite,
              child: _inviting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Invite to org"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            const Text("Members", style: TextStyle(fontWeight: FontWeight.w600)),
            if (_loading) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
            ..._members.map((row) {
              final user = row["user"];
              final membership = row["membership"];
              if (user is! Map<String, dynamic>) return const SizedBox.shrink();
              final role = membership is Map<String, dynamic> ? membership["role"]?.toString() ?? "" : "";
              return Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  title: Text(user["fullName"]?.toString() ?? "—"),
                  subtitle: Text("${user["phone"]} · ${customerMemberRoleLabel(role)}"),
                ),
              );
            }),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account created — sign in with your phone.")));
      context.go("/customer/login");
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Register",
      currentPath: "/customer/register",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your business org. You become the admin and can invite teammates later.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Your name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone (10 digits)"), keyboardType: TextInputType.phone),
          TextField(controller: _org, decoration: const InputDecoration(labelText: "Business / org name")),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
        ],
      ),
    );
  }
}

class CustomerTripsScreen extends StatefulWidget {
  const CustomerTripsScreen({super.key});

  @override
  State<CustomerTripsScreen> createState() => _CustomerTripsScreenState();
}

class _CustomerTripsScreenState extends State<CustomerTripsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _tabSynced = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_tabSynced) {
      final tab = GoRouterState.of(context).uri.queryParameters["tab"];
      if (tab == "match") _tabs.index = 1;
      _tabSynced = true;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Find a lane",
      currentPath: "/customer/trips",
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            labelColor: DriverTheme.navy,
            tabs: const [
              Tab(text: "Browse open"),
              Tab(text: "Match my route"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _CustomerBrowseTripsTab(),
                _CustomerMatchTripsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerBrowseTripsTab extends StatefulWidget {
  const _CustomerBrowseTripsTab();

  @override
  State<_CustomerBrowseTripsTab> createState() => _CustomerBrowseTripsTabState();
}

class _CustomerBrowseTripsTabState extends State<_CustomerBrowseTripsTab> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _trips = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips");
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
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (!_loading && _trips.isEmpty) const Text("No open trips right now.", style: TextStyle(color: DriverTheme.muted)),
          ..._trips.map((t) => _tripCard(context, t)),
        ],
      ),
    );
  }
}

class _CustomerMatchTripsTab extends StatefulWidget {
  const _CustomerMatchTripsTab();

  @override
  State<_CustomerMatchTripsTab> createState() => _CustomerMatchTripsTabState();
}

class _CustomerMatchTripsTabState extends State<_CustomerMatchTripsTab> {
  final _pickupLabel = TextEditingController(text: "Gurugram, Haryana");
  final _dropLabel = TextEditingController(text: "Jaipur, Rajasthan");
  final _weightKg = TextEditingController(text: "200");
  LatLng _pickupPos = const LatLng(28.4700, 77.0300);
  LatLng _dropPos = const LatLng(26.9000, 75.8200);
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void dispose() {
    _pickupLabel.dispose();
    _dropLabel.dispose();
    _weightKg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final weightKg = int.tryParse(_weightKg.text.trim()) ?? 0;
      if (weightKg <= 0) {
        setState(() => _error = "Enter a weight greater than 0 kg.");
        return;
      }
      final qs = Uri(queryParameters: {
        "pickupLat": _pickupPos.latitude.toString(),
        "pickupLng": _pickupPos.longitude.toString(),
        "dropLat": _dropPos.latitude.toString(),
        "dropLng": _dropPos.longitude.toString(),
        "weightKg": weightKg.toString(),
      }).query;
      final r = await api.get<Map<String, dynamic>>("/v1/customer/eligible-anchor-trips?$qs");
      final raw = r.data?["trips"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _rows = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "Trips whose lane passes near your pickup and drop.",
          style: TextStyle(color: DriverTheme.muted),
        ),
        const SizedBox(height: 12),
        LocationEndpointEditor(
          title: "Pickup",
          hint: "City or area",
          labelController: _pickupLabel,
          markerId: "match_pickup",
          markerHue: BitmapDescriptor.hueGreen,
          position: _pickupPos,
          onPositionChanged: (p) => setState(() => _pickupPos = p),
        ),
        const SizedBox(height: 16),
        LocationEndpointEditor(
          title: "Drop",
          hint: "City or area",
          labelController: _dropLabel,
          markerId: "match_drop",
          markerHue: BitmapDescriptor.hueRed,
          position: _dropPos,
          onPositionChanged: (p) => setState(() => _dropPos = p),
        ),
        const SizedBox(height: 12),
        routePreviewMap(a: _pickupPos, b: _dropPos),
        const SizedBox(height: 12),
        TextField(controller: _weightKg, decoration: const InputDecoration(labelText: "Weight (kg)"), keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading ? null : _load,
          child: _loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Find matching trips"),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        ..._rows.map((row) {
          final trip = row["trip"];
          final elig = row["eligibility"];
          if (trip is! Map<String, dynamic>) return const SizedBox.shrink();
          final eligible = elig is Map<String, dynamic> && elig["eligible"] == true;
          if (!eligible) return const SizedBox.shrink();
          return _tripCard(context, trip);
        }),
      ],
    );
  }
}

Widget _tripCard(BuildContext context, Map<String, dynamic> t) {
  final id = t["id"]?.toString() ?? "";
  final route = "${t["originCity"]} → ${t["destCity"]}";
  final status = tripStatusLabel(t["status"]?.toString() ?? "");
  final carrier = t["carrierDisplayName"]?.toString() ?? "Carrier";
  final window = formatTripWindowRange(t["windowStart"]?.toString(), t["windowEnd"]?.toString());
  final isBookable = t["status"]?.toString() == "OPEN";
  return Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(route, style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy)),
          const SizedBox(height: 4),
          Text(carrier, style: const TextStyle(color: DriverTheme.muted)),
          const SizedBox(height: 6),
          Text("$status · ${vehicleClassLabel(t["vehicleClass"]?.toString())} · $window", style: const TextStyle(fontSize: 12)),
          Text("Capacity ${t["capacityKg"]} kg (${t["reservedKg"]} kg reserved)", style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: (!isBookable || id.isEmpty) ? null : () => context.go("/customer/book?anchorTripId=$id"),
            child: Text(isBookable ? "Book this lane" : "Not available"),
          ),
        ],
      ),
    ),
  );
}

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({super.key});

  @override
  State<CustomerBookShipmentScreen> createState() => _CustomerBookShipmentScreenState();
}

class _CustomerBookShipmentScreenState extends State<CustomerBookShipmentScreen> {
  final _anchorTripId = TextEditingController();
  final _customerOrgName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _weightKg = TextEditingController(text: "200");
  final _pickup = TextEditingController(text: "Sector 44, Gurugram");
  final _drop = TextEditingController(text: "Sitapura, Jaipur");
  LatLng _pickupPos = const LatLng(28.4700, 77.0300);
  LatLng _dropPos = const LatLng(26.9000, 75.8200);
  bool _quoting = false;
  bool _booking = false;
  Map<String, dynamic>? _quote;
  Map<String, dynamic>? _anchorTrip;
  bool _loadingTrip = false;
  String? _tripLoadError;
  bool _tripLocked = false;
  Razorpay? _rzp;
  String? _pendingShipmentIdForCheckout;

  @override
  void initState() {
    super.initState();
    _rzp = Razorpay();
    _rzp!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRzpPaymentSuccess);
    _rzp!.on(Razorpay.EVENT_PAYMENT_ERROR, _onRzpPaymentError);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await CustomerSession.refresh();
    if (CustomerSession.customerOrgName != null && CustomerSession.customerOrgName!.isNotEmpty) {
      _customerOrgName.text = CustomerSession.customerOrgName!;
    }
    if (CustomerSession.userPhone != null) _customerPhone.text = CustomerSession.userPhone!;
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = GoRouterState.of(context).uri.queryParameters["anchorTripId"];
    if (id != null && id.isNotEmpty && _anchorTripId.text.isEmpty) {
      _anchorTripId.text = id;
      _tripLocked = true;
      scheduleMicrotask(_loadAnchorTrip);
    }
  }

  @override
  void dispose() {
    _rzp?.clear();
    _anchorTripId.dispose();
    _customerOrgName.dispose();
    _customerPhone.dispose();
    _weightKg.dispose();
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _loadAnchorTrip() async {
    final id = _anchorTripId.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loadingTrip = true;
      _tripLoadError = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips/$id");
      final t = r.data?["trip"];
      setState(() => _anchorTrip = t is Map<String, dynamic> ? t : null);
    } catch (e) {
      setState(() {
        _tripLoadError = formatApiError(e);
        _anchorTrip = null;
      });
    } finally {
      if (mounted) setState(() => _loadingTrip = false);
    }
  }

  Future<void> _onRzpPaymentSuccess(PaymentSuccessResponse response) async {
    final id = _pendingShipmentIdForCheckout;
    if (id != null && id.isNotEmpty) {
      try {
        await api.post<Map<String, dynamic>>(
          "/v1/payments/razorpay/confirm",
          data: {
            "shipmentId": id,
            "razorpayOrderId": response.orderId ?? "",
            "razorpayPaymentId": response.paymentId ?? "",
            "razorpaySignature": response.signature ?? "",
          },
        );
      } catch (_) {}
    }
    if (!mounted) return;
    if (id != null) {
      lastBookedShipmentId = id;
      context.go("/customer/shipments/$id");
    }
    _pendingShipmentIdForCheckout = null;
  }

  void _onRzpPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Payment did not go through. ${response.message ?? "Try again."}")),
    );
  }

  Future<void> _fetchQuote() async {
    setState(() => _quoting = true);
    try {
      final w = int.tryParse(_weightKg.text.trim()) ?? 0;
      final payload = <String, dynamic>{
        "weightKg": w,
        "pickup": {"lat": _pickupPos.latitude, "lng": _pickupPos.longitude, "label": _pickup.text.trim()},
        "drop": {"lat": _dropPos.latitude, "lng": _dropPos.longitude, "label": _drop.text.trim()},
      };
      final id = _anchorTripId.text.trim();
      if (id.isNotEmpty) payload["anchorTripId"] = id;
      final r = await api.post<Map<String, dynamic>>("/shipments/quote", data: payload);
      setState(() => _quote = r.data?["quote"] is Map<String, dynamic> ? r.data!["quote"] as Map<String, dynamic> : null);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _book() async {
    setState(() => _booking = true);
    try {
      final id = _anchorTripId.text.trim();
      if (id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Choose a trip from the Trips tab first.")));
        return;
      }
      final r = await api.post<Map<String, dynamic>>(
        "/shipments/book",
        data: {
          "anchorTripId": id,
          "customerOrgName": _customerOrgName.text.trim(),
          if (_customerPhone.text.trim().isNotEmpty) "customerPhone": _customerPhone.text.trim(),
          "weightKg": int.tryParse(_weightKg.text.trim()) ?? 0,
          "pickupAddress": _pickup.text.trim(),
          "dropAddress": _drop.text.trim(),
          "pickup": {"lat": _pickupPos.latitude, "lng": _pickupPos.longitude, "label": _pickup.text.trim()},
          "drop": {"lat": _dropPos.latitude, "lng": _dropPos.longitude, "label": _drop.text.trim()},
        },
      );
      final shipment = r.data?["shipment"];
      final pay = r.data?["payment"];
      final shipmentId = shipment is Map<String, dynamic> ? shipment["id"]?.toString() : null;
      final keyId = r.data?["razorpayKeyId"]?.toString();
      final orderId = pay is Map<String, dynamic> ? pay["razorpayOrderId"]?.toString() : null;
      final payStatus = pay is Map<String, dynamic> ? pay["status"]?.toString() : null;
      final amountPaise = pay is Map<String, dynamic> && pay["amountPaise"] is num ? (pay["amountPaise"] as num).toInt() : 0;

      if (shipmentId != null &&
          keyId != null &&
          orderId != null &&
          payStatus == "CREATED" &&
          amountPaise > 0 &&
          _rzp != null) {
        lastBookedShipmentId = shipmentId;
        _pendingShipmentIdForCheckout = shipmentId;
        _rzp!.open({
          "key": keyId,
          "amount": amountPaise,
          "currency": "INR",
          "name": "NaviG8r",
          "description": "Authorize shipment payment",
          "order_id": orderId,
        });
      } else if (shipmentId != null) {
        lastBookedShipmentId = shipmentId;
        if (!mounted) return;
        context.go("/customer/shipments/$shipmentId");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ao = latLngFromTripField(_anchorTrip, "origin");
    final ad = latLngFromTripField(_anchorTrip, "destination");
    return CustomerScaffold(
      title: "Book shipment",
      currentPath: "/customer/book",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_anchorTrip == null && !_tripLocked) ...[
            OutlinedButton.icon(
              onPressed: () => context.go("/customer/trips"),
              icon: const Icon(Icons.travel_explore),
              label: const Text("Choose a lane from Trips"),
            ),
            const SizedBox(height: 12),
          ],
          if (_loadingTrip) const Center(child: CircularProgressIndicator()),
          if (_tripLoadError != null) Text(_tripLoadError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          if (_anchorTrip != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${_anchorTrip!["originCity"]} → ${_anchorTrip!["destCity"]}", style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(_anchorTrip!["carrierDisplayName"]?.toString() ?? "Carrier", style: const TextStyle(color: DriverTheme.muted)),
                    Text(
                      "${tripStatusLabel(_anchorTrip!["status"]?.toString() ?? "")} · ${vehicleClassLabel(_anchorTrip!["vehicleClass"]?.toString())}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(formatTripWindowRange(_anchorTrip!["windowStart"]?.toString(), _anchorTrip!["windowEnd"]?.toString()), style: const TextStyle(fontSize: 12, color: DriverTheme.muted)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Text("Shipment details", style: TextStyle(fontWeight: FontWeight.w600, color: DriverTheme.navy)),
          const SizedBox(height: 8),
          if (!CustomerSession.isSignedIn || !CustomerSession.hasCustomerOrg)
            TextField(controller: _customerOrgName, decoration: const InputDecoration(labelText: "Your business name")),
          TextField(controller: _weightKg, decoration: const InputDecoration(labelText: "Weight (kg)"), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          LocationEndpointEditor(
            title: "Pickup",
            hint: "Pickup address",
            labelController: _pickup,
            markerId: "book_pickup",
            markerHue: BitmapDescriptor.hueGreen,
            position: _pickupPos,
            onPositionChanged: (p) => setState(() => _pickupPos = p),
          ),
          const SizedBox(height: 16),
          LocationEndpointEditor(
            title: "Drop",
            hint: "Drop address",
            labelController: _drop,
            markerId: "book_drop",
            markerHue: BitmapDescriptor.hueRed,
            position: _dropPos,
            onPositionChanged: (p) => setState(() => _dropPos = p),
          ),
          const SizedBox(height: 12),
          bookShipmentRouteMap(
            shipmentPickup: _pickupPos,
            shipmentDrop: _dropPos,
            anchorOrigin: ao,
            anchorDestination: ad,
          ),
          if (_quote != null) ...[
            const SizedBox(height: 12),
            Card(
              color: DriverTheme.navy.withOpacity(0.06),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Estimated price", style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      formatInrFromPaise(_quote!["grossPaise"] as num? ?? 0),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: DriverTheme.navy),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _quoting ? null : _fetchQuote, child: const Text("Get quote")),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _booking ? null : _book,
                  child: _booking
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Book & pay"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CustomerShipmentsScreen extends StatefulWidget {
  const CustomerShipmentsScreen({super.key});

  @override
  State<CustomerShipmentsScreen> createState() => _CustomerShipmentsScreenState();
}

class _CustomerShipmentsScreenState extends State<CustomerShipmentsScreen> {
  bool _loading = false;
  String? _error;
  bool _needsAuth = false;
  List<Map<String, dynamic>> _shipments = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _needsAuth = false;
    });
    await CustomerSession.refresh();
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments");
      final raw = r.data?["shipments"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _shipments = list);
    } catch (e) {
      final msg = formatApiError(e);
      setState(() {
        _error = msg;
        _needsAuth = msg.contains("401") || !CustomerSession.isSignedIn;
      });
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
    return CustomerScaffold(
      title: "My shipments",
      currentPath: "/customer/shipments",
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_needsAuth)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Sign in to see shipments linked to your phone or business."),
                      const SizedBox(height: 10),
                      FilledButton(onPressed: () => context.go("/customer/login"), child: const Text("Sign in")),
                    ],
                  ),
                ),
              ),
            if (_error != null && !_needsAuth) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && !_needsAuth && _shipments.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("No shipments yet.", style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text("Browse carrier lanes and book your first shipment.", style: TextStyle(color: DriverTheme.muted)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: () => context.go("/customer/trips"), child: const Text("Browse trips")),
                    ],
                  ),
                ),
              ),
            ..._shipments.map((s) {
              final id = s["id"]?.toString() ?? "";
              final status = shipmentStatusLabel(s["status"]?.toString() ?? "");
              final carrier = s["carrierDisplayName"]?.toString() ?? "Carrier";
              return Card(
                margin: const EdgeInsets.only(top: 12),
                child: ListTile(
                  title: Text(carrier),
                  subtitle: Text("$status · ${s["weightKg"]} kg\n${s["pickupAddress"]} → ${s["dropAddress"]}"),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: id.isEmpty ? null : () => context.go("/customer/shipments/$id"),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class CustomerShipmentDetailScreen extends StatefulWidget {
  const CustomerShipmentDetailScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<CustomerShipmentDetailScreen> createState() => _CustomerShipmentDetailScreenState();
}

class _CustomerShipmentDetailScreenState extends State<CustomerShipmentDetailScreen> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _shipment;
  Map<String, dynamic>? _payment;
  Map<String, dynamic>? _trip;
  Map<String, dynamic>? _liveLocation;
  bool _isLive = false;
  Timer? _poll;

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments/${widget.shipmentId}");
      if (!mounted) return;
      setState(() {
        _shipment = r.data?["shipment"] is Map<String, dynamic> ? r.data!["shipment"] as Map<String, dynamic> : null;
        _payment = r.data?["payment"] is Map<String, dynamic> ? r.data!["payment"] as Map<String, dynamic> : null;
      });
      await _loadTracking();
    } catch (e) {
      if (showSpinner && mounted) setState(() => _error = formatApiError(e));
    } finally {
      if (showSpinner && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadTracking() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments/${widget.shipmentId}/tracking");
      if (!mounted) return;
      setState(() {
        _trip = r.data?["trip"] is Map<String, dynamic> ? r.data!["trip"] as Map<String, dynamic> : null;
        _liveLocation = r.data?["liveLocation"] is Map<String, dynamic> ? r.data!["liveLocation"] as Map<String, dynamic> : null;
        _isLive = r.data?["isLive"] == true;
      });
    } catch (_) {}
  }

  void _schedulePoll() {
    _poll?.cancel();
    final st = _shipment?["status"]?.toString() ?? "";
    if (st == "DELIVERED" || st == "FAILED_CARRIER_REFUNDED") return;
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      await _load(showSpinner: false);
    });
  }

  LatLng? _latLngFromGeo(Map<String, dynamic>? g) {
    if (g == null) return null;
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

  @override
  Widget build(BuildContext context) {
    final shipment = _shipment;
    final tripStatus = _trip?["status"]?.toString();
    final steps = shipment != null
        ? shipmentTimelineSteps(shipmentStatus: shipment["status"]?.toString() ?? "", tripStatus: tripStatus, isLive: _isLive)
        : <ShipmentTimelineStep>[];

    return CustomerScaffold(
      title: shipment?["carrierDisplayName"]?.toString() ?? "Shipment",
      currentPath: "/customer/shipments/${widget.shipmentId}",
      body: _loading && shipment == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                if (shipment != null) ...[
                  _ShipmentTimeline(steps: steps),
                  const SizedBox(height: 12),
                  if (_trip != null &&
                      _latLngFromGeo(_trip!["origin"] as Map<String, dynamic>?) != null &&
                      _latLngFromGeo(_trip!["destination"] as Map<String, dynamic>?) != null)
                    tripTrackingMap(
                      origin: _latLngFromGeo(_trip!["origin"] as Map<String, dynamic>?)!,
                      destination: _latLngFromGeo(_trip!["destination"] as Map<String, dynamic>?)!,
                      pickup: _latLngFromGeo(shipment["pickup"] as Map<String, dynamic>?),
                      drop: _latLngFromGeo(shipment["drop"] as Map<String, dynamic>?),
                      driver: _isLive ? _latLngFromGeo(_liveLocation) : null,
                    )
                  else
                    const Text("Map will appear when the carrier lane has map coordinates.", style: TextStyle(color: DriverTheme.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(
                    _isLive
                        ? "Live tracking — updates every ~30 seconds."
                        : shipment["status"] == "PENDING_CARRIER_ACCEPT"
                            ? "Waiting for ${shipment["carrierDisplayName"] ?? "carrier"} to accept your booking."
                            : shipment["status"] == "BOOKED" && tripStatus != "IN_PROGRESS"
                                ? "Carrier accepted — tracking starts when the load is started."
                                : "Tracking unavailable for this status.",
                    style: const TextStyle(fontSize: 12, color: DriverTheme.muted),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${shipment["pickupAddress"]} → ${shipment["dropAddress"]}", style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text("${shipment["weightKg"]} kg · ${formatInrFromPaise(shipment["grossPaise"] as num? ?? 0)}"),
                          if (_trip != null)
                            Text(
                              "Lane: ${_trip!["originCity"]} → ${_trip!["destCity"]}",
                              style: const TextStyle(fontSize: 12, color: DriverTheme.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_payment != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      title: Text(paymentStatusLabel(_payment!["status"]?.toString() ?? "")),
                      subtitle: Text(formatInrFromPaise(_payment!["amountPaise"] as num? ?? 0)),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _ShipmentTimeline extends StatelessWidget {
  const _ShipmentTimeline({required this.steps});
  final List<ShipmentTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    steps[i].complete ? Icons.check_circle : steps[i].current ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20,
                    color: steps[i].complete || steps[i].current ? DriverTheme.navy : DriverTheme.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(steps[i].label, style: TextStyle(fontWeight: steps[i].current ? FontWeight.w700 : FontWeight.w500, color: DriverTheme.navy)),
                        Text(steps[i].subtitle, style: const TextStyle(fontSize: 11, color: DriverTheme.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              if (i < steps.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
