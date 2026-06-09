import "dart:async";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter/services.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:go_router/go_router.dart";
import "package:razorpay_flutter/razorpay_flutter.dart";

import "driver_flow.dart";
import "driver_theme.dart";
import "location_editor.dart";
import "pilot_api.dart";

Future<void> _copyToClipboard(BuildContext context, String label, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied $label")));
}

Widget _legendStripe(BuildContext context, Color color, double thickness, String label) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: 36,
        height: thickness,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

/// ISO-8601 local wall time with explicit `+05:30` offset (API examples use IST).
String _formatIst(DateTime utc) {
  final ist = utc.toUtc().add(const Duration(hours: 5, minutes: 30));
  String p2(int n) => n.toString().padLeft(2, "0");
  return "${ist.year.toString().padLeft(4, "0")}-${p2(ist.month)}-${p2(ist.day)}T${p2(ist.hour)}:${p2(ist.minute)}:${p2(ist.second)}+05:30";
}

/// Default trip window: IST calendar day **today** 00:00 through **tomorrow** 23:59:59.
void _defaultAnchorTripWindow(TextEditingController w1, TextEditingController w2) {
  final utc = DateTime.now().toUtc();
  final istNow = utc.add(const Duration(hours: 5, minutes: 30));
  final y = istNow.year;
  final m = istNow.month;
  final d = istNow.day;
  final startUtc = DateTime.utc(y, m, d).subtract(const Duration(hours: 5, minutes: 30));
  final endUtc = DateTime.utc(y, m, d + 2).subtract(const Duration(hours: 5, minutes: 30)).subtract(const Duration(seconds: 1));
  w1.text = _formatIst(startUtc);
  w2.text = _formatIst(endUtc);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  api = Api(resolveApiBaseUrl());
  runApp(const DriverPilotApp());
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class DriverPilotApp extends StatelessWidget {
  const DriverPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: "/driver",
      routes: [
        ...driverFlowRoutes(),
        GoRoute(path: "/pilot-lab", builder: (_, __) => const HomeScreen()),
        GoRoute(path: "/", redirect: (_, __) => "/driver"),
        GoRoute(path: "/register", builder: (_, __) => const RegisterScreen()),
        GoRoute(path: "/login", builder: (_, __) => const LoginScreen()),
        GoRoute(path: "/trips", builder: (_, __) => const MyTripsScreen()),
        GoRoute(
          path: "/trips/:tripId",
          builder: (_, state) => TripDetailScreen(tripId: state.pathParameters["tripId"] ?? ""),
        ),
        GoRoute(path: "/customer", builder: (_, __) => const CustomerHomeScreen()),
        GoRoute(path: "/customer/register", builder: (_, __) => const CustomerRegisterScreen()),
        GoRoute(path: "/customer/trips", builder: (_, __) => const CustomerBrowseTripsScreen()),
        GoRoute(path: "/customer/book", builder: (_, __) => const CustomerBookShipmentScreen()),
        GoRoute(path: "/customer/eligible", builder: (_, __) => const CustomerEligibleTripsScreen()),
        GoRoute(path: "/customer/shipments", builder: (_, __) => const CustomerShipmentsScreen()),
        GoRoute(
          path: "/customer/shipments/:shipmentId",
          builder: (_, state) => CustomerShipmentDetailScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
        ),
        GoRoute(path: "/publish", builder: (_, __) => const PublishTripScreen()),
      ],
    );

    return MaterialApp.router(
      title: "NaviG8r Driver",
      theme: DriverTheme.theme(),
      routerConfig: router,
    );
  }
}

class PilotScaffold extends StatelessWidget {
  const PilotScaffold({
    required this.title,
    required this.currentPath,
    required this.body,
    this.actions,
    super.key,
  });

  final String title;
  final String currentPath;
  final Widget body;
  final List<Widget>? actions;

  int _indexForPath(String path) {
    switch (path) {
      case "/register":
        return 1;
      case "/login":
        return 2;
      case "/trips":
        return 3;
      case "/publish":
        return 4;
      case "/pilot-lab":
      default:
        return 0;
    }
  }

  String _pathForIndex(int index) {
    switch (index) {
      case 1:
        return "/register";
      case 2:
        return "/login";
      case 3:
        return "/trips";
      case 4:
        return "/publish";
      case 0:
      default:
        return "/pilot-lab";
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexForPath(currentPath);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          final target = _pathForIndex(index);
          if (target != currentPath) context.go(target);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Home"),
          NavigationDestination(icon: Icon(Icons.person_add_alt_1_outlined), selectedIcon: Icon(Icons.person_add_alt_1), label: "Register"),
          NavigationDestination(icon: Icon(Icons.lock_open_outlined), selectedIcon: Icon(Icons.lock_open), label: "Login"),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: "Trips"),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: "Publish"),
        ],
      ),
    );
  }
}

class CustomerScaffold extends StatelessWidget {
  const CustomerScaffold({
    required this.title,
    required this.currentPath,
    required this.body,
    this.actions,
    super.key,
  });

  final String title;
  final String currentPath;
  final Widget body;
  final List<Widget>? actions;

  int _indexForPath(String path) {
    if (path.startsWith("/customer/trips")) return 1;
    if (path.startsWith("/customer/book")) return 2;
    if (path.startsWith("/customer/shipments")) return 3;
    if (path.startsWith("/customer/eligible")) return 1;
    return 0; // /customer (home) and anything else
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: "Switch to driver",
            onPressed: () => context.go("/"),
            icon: const Icon(Icons.local_shipping_outlined),
          ),
          ...?actions,
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
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: "Customer"),
          NavigationDestination(icon: Icon(Icons.travel_explore_outlined), selectedIcon: Icon(Icons.travel_explore), label: "Trips"),
          NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: "Book"),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: "Shipments"),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _health = "—";
  bool _loading = false;
  bool _loadingMe = false;
  String _me = "—";

  Future<void> _loadMe() async {
    setState(() => _loadingMe = true);
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      final user = r.data?["user"];
      final phone = (user is Map<String, dynamic>) ? user["phone"] : null;
      final name = (user is Map<String, dynamic>) ? user["fullName"] : null;
      final orgId = firstCarrierOrgIdFromPilotMe(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      setState(() => _me = "user: ${name ?? "?"} (${phone ?? "?"})\ncarrierOrg: ${orgId ?? "—"}");
    } catch (e) {
      setState(() => _me = formatApiError(e));
    } finally {
      setState(() => _loadingMe = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    await api.clearToken();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logged out (token cleared).")));
  }

  Future<void> _ping() async {
    setState(() => _loading = true);
    try {
      final dns = await diagnoseApiDns(api.baseUrl);
      if (dns.startsWith("DNS failed")) {
        setState(() => _health = dns);
        return;
      }
      final r = await api.get<Map<String, dynamic>>("/health");
      setState(() => _health = "$dns\n${r.data}");
    } catch (e) {
      setState(() => _health = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _ping();
  }

  @override
  Widget build(BuildContext context) {
    return PilotScaffold(
      title: "Driver Pilot",
      currentPath: "/pilot-lab",
      actions: [
        IconButton(
          tooltip: "Logout",
          onPressed: () => _logout(context),
          icon: const Icon(Icons.logout),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go("/driver"),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Back to driver app (welcome)"),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("API health", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text("Base URL: ${api.baseUrl}", style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Text("GET /health → $_health"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _ping,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text("Retry health"),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Session", style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(_me),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _loadingMe ? null : _loadMe,
                    icon: _loadingMe
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.badge),
                    label: const Text("Load /v1/pilot/me"),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text("Quick actions", style: Theme.of(context).textTheme.titleMedium),
          Text("Base URL: ${api.baseUrl}", style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go("/register"),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text("Register (solo org)"),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go("/login"),
            icon: const Icon(Icons.lock_open),
            label: const Text("Login (OTP)"),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go("/trips"),
            icon: const Icon(Icons.route),
            label: const Text("My anchor trips"),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go("/publish"),
            icon: const Icon(Icons.local_shipping),
            label: const Text("Publish anchor trip"),
          ),
          const SizedBox(height: 12),
          Text("Customer marketplace", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go("/customer"),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text("Open customer flow"),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController(text: "9876543210");
  final _org = TextEditingController(text: "Ravi Transport");
  final _reg = TextEditingController(text: "HR26AB1234");
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _capKg = TextEditingController(text: "5000");
  String _out = "";
  bool _submitting = false;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    _reg.dispose();
    _vehClass.dispose();
    _capKg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      if (phone.length != 10) {
        setState(() => _out = "Phone must be 10 digits.");
        return;
      }
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/driver/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": phone,
          "orgDisplayName": _org.text.trim(),
          "vehicleRegistrationNumber": _reg.text.trim(),
          "vehicleClass": _vehClass.text.trim(),
          "vehicleCapacityKg": int.tryParse(_capKg.text.trim()) ?? 0,
        },
      );
      final orgId = orgIdFromRegisterResponse(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PilotScaffold(
      title: "Register",
      currentPath: "/register",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Full name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone (10 digit IN)")),
          TextField(controller: _org, decoration: const InputDecoration(labelText: "Org display name")),
          TextField(controller: _reg, decoration: const InputDecoration(labelText: "Vehicle reg")),
          TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "Vehicle class (SMALL|MEDIUM|LARGE)")),
          TextField(controller: _capKg, decoration: const InputDecoration(labelText: "Vehicle capacity kg")),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text("POST /v1/pilot/driver/register"),
          ),
          const SizedBox(height: 12),
          SelectableText(_out),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController(text: "9876543210");
  final _challengeId = TextEditingController();
  final _code = TextEditingController(text: "123456");
  String _startOut = "";
  String _verifyOut = "";
  String? _debugCode;
  bool _starting = false;
  bool _verifying = false;
  /** After OTP verify returned an access token (used for customer-flow CTA). */
  bool _verifyIssuedToken = false;

  String? _extractChallengeId(dynamic data) {
    if (data is! Map<String, dynamic>) return null;
    final direct = data["challengeId"];
    if (direct is String && direct.trim().isNotEmpty) return direct.trim();

    // Tolerate common response wrappers: { data: { challengeId: "..." } } etc.
    final nestedData = data["data"];
    if (nestedData is Map<String, dynamic>) {
      final nested = nestedData["challengeId"];
      if (nested is String && nested.trim().isNotEmpty) return nested.trim();
    }

    final challenge = data["challenge"];
    if (challenge is Map<String, dynamic>) {
      final nested = challenge["id"] ?? challenge["challengeId"];
      if (nested is String && nested.trim().isNotEmpty) return nested.trim();
    }
    return null;
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    final phone = digitsOnly(_phone.text.trim());
    if (phone.length != 10) {
      setState(() {
        _startOut = "Phone must be 10 digits.";
        _starting = false;
      });
      return;
    }
    try {
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": phone});
      setState(() {
        _startOut = r.data?.toString() ?? "{}";
        final id = _extractChallengeId(r.data);
        if (id != null) _challengeId.text = id;
        final debugCode = r.data?["debugCode"];
        _debugCode = debugCode is String && debugCode.trim().isNotEmpty ? debugCode.trim() : null;
        if (_debugCode != null) _code.text = _debugCode!;
      });
    } catch (e) {
      setState(() => _startOut = formatApiError(e));
    } finally {
      setState(() => _starting = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final phone = digitsOnly(_phone.text.trim());
    final challengeId = _challengeId.text.trim();
    final code = _code.text.trim();
    if (phone.length != 10 || challengeId.isEmpty || code.isEmpty) {
      setState(() {
        _verifyOut = "Enter valid phone (10 digits), challengeId, and code.";
        _verifying = false;
        _verifyIssuedToken = false;
      });
      return;
    }
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {"phone": phone, "challengeId": challengeId, "code": code},
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      setState(() {
        _verifyOut = r.data?.toString() ?? "{}";
        _verifyIssuedToken = token != null;
      });
    } catch (e) {
      setState(() {
        _verifyOut = formatApiError(e);
        _verifyIssuedToken = false;
      });
    } finally {
      setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _challengeId.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = GoRouterState.of(context).uri.queryParameters["mode"];
    final isCustomer = mode == "customer";

    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _debugCode != null
                  ? "Using debug OTP from server response: $_debugCode"
                  : "On hosted environments, OTP code 123456 only works if the server has OTP debug mode enabled. "
                      "If /otp/start does not return debugCode, you likely need a real SMS flow or a server-side debug setting.",
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone")),
        FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sms),
          label: const Text("POST /v1/auth/otp/start"),
        ),
        const SizedBox(height: 8),
        SelectableText(_startOut),
        const SizedBox(height: 16),
        TextField(controller: _challengeId, decoration: const InputDecoration(labelText: "challengeId")),
        TextField(controller: _code, decoration: const InputDecoration(labelText: "code (use OTP_DEBUG=123456 locally)")),
        FilledButton.icon(
          onPressed: _verifying ? null : _verify,
          icon: _verifying
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.verified_user),
          label: const Text("POST /v1/auth/otp/verify"),
        ),
        const SizedBox(height: 8),
        SelectableText(_verifyOut),
        if (isCustomer && _verifyIssuedToken) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go("/customer"),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text("Continue to customer home"),
          ),
        ],
      ],
    );

    if (isCustomer) {
      // Use real route so bottom "Customer" tab navigates to `/customer`
      // (was `/login?mode=customer` but scaffold claimed `/customer`, blocking `go`).
      final loc = GoRouterState.of(context).matchedLocation;
      return CustomerScaffold(
        title: "Sign in (OTP)",
        currentPath: loc.isEmpty ? "/login" : loc,
        body: body,
      );
    }

    return PilotScaffold(
      title: "Login (OTP)",
      currentPath: "/login",
      body: body,
    );
  }
}

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  List<Map<String, dynamic>> _trips = [];
  String? _error;
  bool _loading = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips");
      final raw = r.data?["trips"];
      final list = <Map<String, dynamic>>[];
      if (raw is List<dynamic>) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _trips = list);
    } catch (e) {
      setState(() {
        _error = formatApiError(e);
        _trips = [];
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    // RefreshIndicator expects a Future even if we're already loading.
    if (_loading) return;
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return PilotScaffold(
      title: "My trips",
      currentPath: "/trips",
      actions: [
        IconButton(
          tooltip: "Logout",
          onPressed: () async {
            await api.clearToken();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logged out (token cleared).")));
          },
          icon: const Icon(Icons.logout),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                "Lists anchor trips for carrier orgs you belong to. Requires OTP login (Bearer token). "
                "Uses GET /v1/pilot/anchor-trips — deploy the latest API for this route.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: const Text("Refresh"),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_trips.isEmpty && !_loading && _error == null) ...[
            const SizedBox(height: 24),
            Text("No trips yet. Publish one from the Publish tab.", style: Theme.of(context).textTheme.bodyLarge),
          ],
          ..._trips.map((t) {
            final id = t["id"]?.toString() ?? "—";
            final route = "${t["originCity"]} → ${t["destCity"]}";
            final window = "${t["windowStart"]}\n… ${t["windowEnd"]}";
            final status = t["status"]?.toString() ?? "—";
            final cap = t["capacityKg"];
            final res = t["reservedKg"];
            final vclass = t["vehicleClass"]?.toString() ?? "—";
            final org = t["carrierId"]?.toString() ?? "—";
            return Card(
              margin: const EdgeInsets.only(top: 12),
              child: InkWell(
                onTap: id == "—" ? null : () => context.go("/trips/$id"),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(route, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text("id: $id", style: Theme.of(context).textTheme.bodySmall),
                      Text("org: $org", style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(window, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(
                        "$status · $vclass · capacity ${cap}kg (reserved ${res}kg)",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          ],
        ),
      ),
    );
  }
}

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({required this.tripId, super.key});
  final String tripId;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Map<String, dynamic>? _trip;
  String? _error;
  bool _loading = false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}");
      final t = r.data?["trip"];
      setState(() => _trip = (t is Map<String, dynamic>) ? t : null);
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
    final trip = _trip;
    final title = trip == null ? "Trip" : "${trip["originCity"]} → ${trip["destCity"]}";
    final routeOrigin = trip != null ? latLngFromTripField(trip, "origin") : null;
    final routeDest = trip != null ? latLngFromTripField(trip, "destination") : null;
    return PilotScaffold(
      title: title,
      currentPath: "/trips",
      actions: [
        IconButton(
          tooltip: "Refresh",
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("tripId: ${widget.tripId}", style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (_error != null) SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (trip != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text("status: ${trip["status"]}"),
                    Text("vehicleClass: ${trip["vehicleClass"]}"),
                    Text("capacityKg: ${trip["capacityKg"]} (reserved ${trip["reservedKg"]})"),
                    const SizedBox(height: 8),
                    Text("windowStart: ${trip["windowStart"]}", style: Theme.of(context).textTheme.bodySmall),
                    Text("windowEnd: ${trip["windowEnd"]}", style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text("org/carrierId: ${trip["carrierId"]}", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            if (routeOrigin != null && routeDest != null) ...[
              const SizedBox(height: 12),
              Text("Route preview", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              routePreviewMap(a: routeOrigin, b: routeDest),
            ],
            const SizedBox(height: 12),
            Text("Raw JSON", style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(trip.toString()),
          ],
        ],
      ),
    );
  }
}

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Customer demo",
      currentPath: "/customer",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Customer marketplace demo:\n"
                "• Browse trips & book (quote/book) — open.\n"
                "• Shipments list, detail, POD, refund — use the same phone as customer register, then "
                "Sign in (OTP) so the app sends a Bearer token; only your org’s shipments are returned.",
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.go("/login?mode=customer"),
            icon: const Icon(Icons.login),
            label: const Text("Sign in (OTP) — required for shipments"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/register"),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text("Register customer org (pilot)"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/trips"),
            icon: const Icon(Icons.travel_explore),
            label: const Text("Browse open trips"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/book"),
            icon: const Icon(Icons.shopping_cart_outlined),
            label: const Text("Quote + book a shipment"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/eligible"),
            icon: const Icon(Icons.tune),
            label: const Text("Eligible lanes (Phase A)"),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => context.go("/customer/shipments"),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text("Shipments"),
          ),
        ],
      ),
    );
  }
}

class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _fullName = TextEditingController(text: "ACME Ops");
  final _phone = TextEditingController(text: "9123456789");
  final _org = TextEditingController(text: "ACME Manufacturing Pvt Ltd");
  bool _submitting = false;
  String _out = "";

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": phone,
          "orgDisplayName": _org.text.trim(),
        },
      );
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Customer register",
      currentPath: "/customer/register",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Full name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone (10 digit IN)")),
          TextField(controller: _org, decoration: const InputDecoration(labelText: "Org display name")),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text("POST /v1/pilot/customer/register"),
          ),
          const SizedBox(height: 12),
          SelectableText(_out),
        ],
      ),
    );
  }
}

class CustomerBrowseTripsScreen extends StatefulWidget {
  const CustomerBrowseTripsScreen({super.key});

  @override
  State<CustomerBrowseTripsScreen> createState() => _CustomerBrowseTripsScreenState();
}

class _CustomerBrowseTripsScreenState extends State<CustomerBrowseTripsScreen> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _trips = [];

  int _statusRank(String status) {
    switch (status) {
      case "OPEN":
        return 0;
      case "FULL":
        return 1;
      case "COMPLETED":
        return 2;
      default:
        return 3;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips");
      final raw = r.data?["trips"];
      final list = <Map<String, dynamic>>[];
      if (raw is List<dynamic>) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
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
      setState(() => _trips = list);
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Browse trips",
      currentPath: "/customer/trips",
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text("Refresh"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            ..._trips.map((t) {
              final id = t["id"]?.toString() ?? "—";
              final route = "${t["originCity"]} → ${t["destCity"]}";
              final status = tripStatusLabel(t["status"]?.toString() ?? "—");
              final carrier = t["carrierDisplayName"]?.toString() ?? "Carrier";
              final cap = t["capacityKg"];
              final res = t["reservedKg"];
              final isBookable = t["status"]?.toString() == "OPEN";
              return Card(
                margin: const EdgeInsets.only(top: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(route, style: Theme.of(context).textTheme.titleMedium)),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(status),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text("Carrier: $carrier", style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text("$status · capacity ${cap}kg (reserved ${res}kg)"),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: (!isBookable || id == "—") ? null : () => context.go("/customer/book?anchorTripId=$id"),
                        icon: const Icon(Icons.shopping_cart_outlined),
                        label: Text(isBookable ? "Book against this trip" : "Not bookable"),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class CustomerEligibleTripsScreen extends StatefulWidget {
  const CustomerEligibleTripsScreen({super.key});

  @override
  State<CustomerEligibleTripsScreen> createState() => _CustomerEligibleTripsScreenState();
}

class _CustomerEligibleTripsScreenState extends State<CustomerEligibleTripsScreen> {
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
        setState(() => _error = "Enter weightKg > 0.");
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
      if (raw is List<dynamic>) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _rows = list);
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
    return CustomerScaffold(
      title: "Eligible lanes",
      currentPath: "/customer/eligible",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                "Phase A eligibility = distance from your pickup/drop to each trip’s origin/destination. "
                "Set locations with search or by dragging pins; coordinates are sent to the API.",
              ),
            ),
          ),
          const SizedBox(height: 12),
          LocationEndpointEditor(
            title: "Your pickup (approx.)",
            hint: "City, area, or address",
            labelController: _pickupLabel,
            markerId: "eligible_pickup",
            markerHue: BitmapDescriptor.hueGreen,
            position: _pickupPos,
            onPositionChanged: (p) => setState(() => _pickupPos = p),
          ),
          const SizedBox(height: 20),
          LocationEndpointEditor(
            title: "Your drop (approx.)",
            hint: "City, area, or address",
            labelController: _dropLabel,
            markerId: "eligible_drop",
            markerHue: BitmapDescriptor.hueRed,
            position: _dropPos,
            onPositionChanged: (p) => setState(() => _dropPos = p),
          ),
          const SizedBox(height: 12),
          routePreviewMap(a: _pickupPos, b: _dropPos),
          const SizedBox(height: 12),
          TextField(controller: _weightKg, decoration: const InputDecoration(labelText: "weightKg")),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text("Find eligible trips"),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          ..._rows.map((row) {
            final trip = row["trip"];
            final elig = row["eligibility"];
            if (trip is! Map<String, dynamic> || elig is! Map<String, dynamic>) return const SizedBox.shrink();
            final id = trip["id"]?.toString() ?? "—";
            final route = "${trip["originCity"]} → ${trip["destCity"]}";
            final carrier = trip["carrierDisplayName"]?.toString() ?? "Carrier";
            final eligible = elig["eligible"] == true;
            final reason = elig["reason"]?.toString() ?? "—";
            final pickupKm = elig["pickupDistanceKm"]?.toString() ?? "—";
            final dropKm = elig["dropDistanceKm"]?.toString() ?? "—";
            return Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(route, style: Theme.of(context).textTheme.titleMedium)),
                        const SizedBox(width: 8),
                        Chip(label: Text(eligible ? "ELIGIBLE" : "NO"), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text("Carrier: $carrier", style: Theme.of(context).textTheme.bodyMedium),
                    Text("reason: $reason · pickup ${pickupKm}km · drop ${dropKm}km", style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: eligible && id != "—" ? () => context.go("/customer/book?anchorTripId=$id") : null,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text("Book this trip"),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({super.key});

  @override
  State<CustomerBookShipmentScreen> createState() => _CustomerBookShipmentScreenState();
}

String? lastBookedShipmentId;

class _CustomerBookShipmentScreenState extends State<CustomerBookShipmentScreen> {
  final _anchorTripId = TextEditingController();
  final _customerOrgName = TextEditingController(text: "ACME Manufacturing");
  final _customerPhone = TextEditingController();
  final _weightKg = TextEditingController(text: "200");
  final _pickup = TextEditingController(text: "Sector 44, Gurugram");
  final _drop = TextEditingController(text: "Sitapura, Jaipur");
  LatLng _pickupPos = const LatLng(28.4700, 77.0300);
  LatLng _dropPos = const LatLng(26.9000, 75.8200);
  bool _quoting = false;
  bool _booking = false;
  String _out = "";
  Map<String, dynamic>? _anchorTrip;
  bool _loadingTrip = false;
  String? _tripLoadError;
  Timer? _tripLoadDebounce;

  Razorpay? _rzp;
  String? _pendingShipmentIdForCheckout;

  @override
  void initState() {
    super.initState();
    _anchorTripId.addListener(_onAnchorTripIdChanged);
    _rzp = Razorpay();
    _rzp!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRzpPaymentSuccess);
    _rzp!.on(Razorpay.EVENT_PAYMENT_ERROR, _onRzpPaymentError);
    _rzp!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onRzpExternalWallet);
    _prefillLoggedInPhone();
  }

  Future<void> _prefillLoggedInPhone() async {
    if (_customerPhone.text.trim().isNotEmpty) return;
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/auth/me");
      final phone = r.data?["user"];
      if (phone is Map<String, dynamic>) {
        final p = phone["phone"]?.toString().trim() ?? "";
        if (p.isNotEmpty && mounted) setState(() => _customerPhone.text = p);
      }
    } catch (_) {}
  }

  void _onAnchorTripIdChanged() {
    _tripLoadDebounce?.cancel();
    _tripLoadDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _loadAnchorTrip();
    });
  }

  Future<void> _loadAnchorTrip() async {
    final id = _anchorTripId.text.trim();
    if (id.isEmpty) {
      setState(() {
        _anchorTrip = null;
        _tripLoadError = null;
      });
      return;
    }
    setState(() {
      _loadingTrip = true;
      _tripLoadError = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/anchor-trips/$id");
      final t = r.data?["trip"];
      if (!mounted) return;
      setState(() {
        _anchorTrip = t is Map<String, dynamic> ? t : null;
        if (_anchorTrip == null) _tripLoadError = "Trip not found.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tripLoadError = formatApiError(e);
        _anchorTrip = null;
      });
    } finally {
      if (mounted) setState(() => _loadingTrip = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = GoRouterState.of(context).uri.queryParameters["anchorTripId"];
    if (id != null && id.isNotEmpty && _anchorTripId.text.isEmpty) {
      _anchorTripId.text = id;
      scheduleMicrotask(_loadAnchorTrip);
    }
  }

  @override
  void dispose() {
    _tripLoadDebounce?.cancel();
    _rzp?.clear();
    _anchorTripId.removeListener(_onAnchorTripIdChanged);
    _anchorTripId.dispose();
    _customerOrgName.dispose();
    _customerPhone.dispose();
    _weightKg.dispose();
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _onRzpPaymentSuccess(PaymentSuccessResponse response) async {
    final id = _pendingShipmentIdForCheckout;
    if (!mounted) return;
    final paymentId = response.paymentId?.trim() ?? "";
    final orderId = response.orderId?.trim() ?? "";
    final signature = response.signature?.trim() ?? "";
    if (id != null && id.isNotEmpty && paymentId.isNotEmpty && orderId.isNotEmpty && signature.isNotEmpty) {
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
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Payment authorized in Razorpay but server confirm failed: ${formatApiError(e)}")),
          );
        }
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Authorized ${response.paymentId ?? "ok"} — funds captured at POD.")),
    );
    if (id != null && id.isNotEmpty) {
      lastBookedShipmentId = id;
      context.go("/customer/shipments/$id");
    }
    _pendingShipmentIdForCheckout = null;
  }

  void _onRzpPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Razorpay error: ${response.message ?? response.code?.toString() ?? "?"}")),
    );
  }

  void _onRzpExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("External wallet: ${response.walletName ?? "—"}")),
    );
  }

  void _openRazorpayCheckout({
    required String keyId,
    required int amountPaise,
    required String orderId,
    required String shipmentId,
  }) {
    final rzp = _rzp;
    if (rzp == null) return;
    _pendingShipmentIdForCheckout = shipmentId;
    rzp.open({
      "key": keyId,
      "amount": amountPaise,
      "currency": "INR",
      "name": "Navig8r pilot",
      "description": "Shipment $shipmentId — authorize hold",
      "order_id": orderId,
    });
  }

  Future<void> _quote() async {
    setState(() => _quoting = true);
    try {
      final w = int.tryParse(_weightKg.text.trim()) ?? 0;
      final id = _anchorTripId.text.trim();
      final payload = <String, dynamic>{
        "weightKg": w,
        "pickup": {
          "lat": _pickupPos.latitude,
          "lng": _pickupPos.longitude,
          "label": _pickup.text.trim(),
        },
        "drop": {
          "lat": _dropPos.latitude,
          "lng": _dropPos.longitude,
          "label": _drop.text.trim(),
        },
      };
      if (id.isNotEmpty) payload["anchorTripId"] = id;

      final r = await api.post<Map<String, dynamic>>("/shipments/quote", data: payload);

      final q = r.data?["quote"];
      if (q is Map<String, dynamic>) {
        final b = q["breakdown"];
        final buf = StringBuffer();
        buf.writeln("grossPaise: ${q["grossPaise"]}");
        if (b is Map<String, dynamic>) {
          buf.writeln("pricingMode: ${b["pricingMode"]}");
          buf.writeln("laneKm: ${b["laneKm"]} · shipmentKm: ${b["shipmentKm"]} · priced on ${b["distanceKmForPrice"]} km "
              "(paise/km: ${b["paisePerKm"]})");
          buf.writeln("distanceComponentPaise: ${b["distanceComponentPaise"]} · "
              "weightComponentPaise: ${b["weightComponentPaise"]}");
          buf.writeln("vehicleClass: ${b["vehicleClass"]} · modelVersion: ${b["modelVersion"]}");
        }
        setState(() => _out = buf.toString());
      } else {
        setState(() => _out = r.data?.toString() ?? "{}");
      }
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _quoting = false);
    }
  }

  Future<void> _book() async {
    setState(() => _booking = true);
    try {
      final w = int.tryParse(_weightKg.text.trim()) ?? 0;
      final bookBody = <String, dynamic>{
          "anchorTripId": _anchorTripId.text.trim(),
          "customerOrgName": _customerOrgName.text.trim(),
          "weightKg": w,
          "pickupAddress": _pickup.text.trim(),
          "dropAddress": _drop.text.trim(),
          "pickup": {
            "lat": _pickupPos.latitude,
            "lng": _pickupPos.longitude,
            "label": _pickup.text.trim(),
          },
          "drop": {
            "lat": _dropPos.latitude,
            "lng": _dropPos.longitude,
            "label": _drop.text.trim(),
          },
      };
      final phone = _customerPhone.text.trim();
      if (phone.isNotEmpty) bookBody["customerPhone"] = phone;
      final r = await api.post<Map<String, dynamic>>(
        "/shipments/book",
        data: bookBody,
      );
      final raw = r.data;
      final s = raw?["shipment"];
      final pay = raw?["payment"];
      final shipmentId = (s is Map<String, dynamic>) ? s["id"]?.toString() : null;
      final keyId = raw?["razorpayKeyId"]?.toString();
      final orderId = pay is Map<String, dynamic> ? pay["razorpayOrderId"]?.toString() : null;
      final payStatus = pay is Map<String, dynamic> ? pay["status"]?.toString() : null;
      final amountObj = pay is Map<String, dynamic> ? pay["amountPaise"] : null;
      final amountPaise = amountObj is num ? amountObj.toInt() : int.tryParse("$amountObj") ?? 0;

      setState(() => _out = raw?.toString() ?? "{}");
      if (!mounted) return;

      if (shipmentId != null &&
          shipmentId.isNotEmpty &&
          keyId != null &&
          orderId != null &&
          orderId.isNotEmpty &&
          payStatus == "CREATED" &&
          amountPaise > 0 &&
          _rzp != null) {
        lastBookedShipmentId = shipmentId;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authorize payment — capture happens when you mark POD.")),
        );
        _openRazorpayCheckout(
          keyId: keyId,
          amountPaise: amountPaise,
          orderId: orderId,
          shipmentId: shipmentId,
        );
      } else if (shipmentId != null && shipmentId.isNotEmpty) {
        lastBookedShipmentId = shipmentId;
        context.go("/customer/shipments/$shipmentId");
      }
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Quote + book",
      currentPath: "/customer/book",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: () => context.go("/customer/trips"),
            icon: const Icon(Icons.travel_explore),
            label: const Text("Pick an anchorTripId from Trips"),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _anchorTripId,
                  decoration: const InputDecoration(labelText: "anchorTripId"),
                  onSubmitted: (_) => _loadAnchorTrip(),
                ),
              ),
              IconButton(
                tooltip: "Refresh trip details",
                onPressed: _loadingTrip || _anchorTripId.text.trim().isEmpty ? null : _loadAnchorTrip,
                icon: _loadingTrip
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: "Copy trip id",
                onPressed: _anchorTripId.text.trim().isEmpty
                    ? null
                    : () => _copyToClipboard(context, "trip id", _anchorTripId.text.trim()),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          if (_tripLoadError != null && _anchorTripId.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(_tripLoadError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
          ],
          if (_anchorTrip != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("You’re booking against", style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    Text(
                      "${_anchorTrip!["originCity"]} → ${_anchorTrip!["destCity"]}",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Carrier: ${_anchorTrip!["carrierDisplayName"] ?? "—"}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${tripStatusLabel(_anchorTrip!["status"]?.toString() ?? "")} · ${_anchorTrip!["vehicleClass"]} · "
                      "capacity ${_anchorTrip!["capacityKg"]}kg (reserved ${_anchorTrip!["reservedKg"]}kg)",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      "window ${_anchorTrip!["windowStart"]} → ${_anchorTrip!["windowEnd"]}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          TextField(controller: _customerOrgName, decoration: const InputDecoration(labelText: "customerOrgName")),
          TextField(
            controller: _customerPhone,
            decoration: const InputDecoration(
              labelText: "Your mobile (optional)",
              helperText: "Same number as OTP login to list this booking without org match",
            ),
            keyboardType: TextInputType.phone,
          ),
          TextField(controller: _weightKg, decoration: const InputDecoration(labelText: "weightKg")),
          const SizedBox(height: 8),
          Text("Pickup & drop (maps)", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LocationEndpointEditor(
            title: "Pickup",
            hint: "Pickup address or area",
            labelController: _pickup,
            markerId: "book_pickup",
            markerHue: BitmapDescriptor.hueGreen,
            position: _pickupPos,
            onPositionChanged: (p) => setState(() => _pickupPos = p),
          ),
          const SizedBox(height: 20),
          LocationEndpointEditor(
            title: "Drop",
            hint: "Drop address or area",
            labelController: _drop,
            markerId: "book_drop",
            markerHue: BitmapDescriptor.hueRed,
            position: _dropPos,
            onPositionChanged: (p) => setState(() => _dropPos = p),
          ),
          const SizedBox(height: 16),
          Text("Review on map before booking", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          if (latLngFromTripField(_anchorTrip, "origin") == null || latLngFromTripField(_anchorTrip, "destination") == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _anchorTrip == null
                    ? "Enter an anchor trip id to load the carrier route (orange), or only your pickup→drop (blue) is shown."
                    : "This trip has no stored origin/destination coordinates; the map shows your shipment pickup→drop only.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legendStripe(context, const Color(0xFFE65100), 9, "Anchor trip (carrier)"),
                    const SizedBox(height: 6),
                    _legendStripe(context, const Color(0xFF0D47A1), 4, "Your pickup → drop"),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final ao = latLngFromTripField(_anchorTrip, "origin");
            final ad = latLngFromTripField(_anchorTrip, "destination");
            return bookShipmentRouteMap(
              key: ValueKey(
                "${_pickupPos.latitude},${_pickupPos.longitude},${_dropPos.latitude},${_dropPos.longitude},"
                "${ao?.latitude},${ao?.longitude},${ad?.latitude},${ad?.longitude}",
              ),
              shipmentPickup: _pickupPos,
              shipmentDrop: _dropPos,
              anchorOrigin: ao,
              anchorDestination: ad,
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _quoting ? null : _quote,
                  icon: _quoting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.calculate_outlined),
                  label: const Text("Quote"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _booking ? null : _book,
                  icon: _booking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.shopping_cart_outlined),
                  label: const Text("Book"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(_out),
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
  List<Map<String, dynamic>> _shipments = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments");
      final raw = r.data?["shipments"];
      final list = <Map<String, dynamic>>[];
      if (raw is List<dynamic>) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _shipments = list);
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
    final shipmentId = lastBookedShipmentId;
    return CustomerScaffold(
      title: "Shipments",
      currentPath: "/customer/shipments",
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: () => context.go("/login?mode=customer"),
              icon: const Icon(Icons.login),
              label: const Text("Sign in (OTP)"),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: const Text("Refresh"),
            ),
            const SizedBox(height: 12),
            if (shipmentId != null && shipmentId.isNotEmpty) ...[
              Card(
                child: ListTile(
                  title: const Text("Last booked shipment"),
                  subtitle: Text(shipmentId),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go("/customer/shipments/$shipmentId"),
                ),
              ),
            ] else ...[
              const Text("No shipment booked in this app session yet."),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => context.go("/customer/book"),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text("Book a shipment"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            ..._shipments.map((s) {
              final id = s["id"]?.toString() ?? "—";
              final status = shipmentStatusLabel(s["status"]?.toString() ?? "—");
              final carrier = s["carrierDisplayName"]?.toString() ?? "Carrier";
              final route = "${s["pickupAddress"]} → ${s["dropAddress"]}";
              return Card(
                margin: const EdgeInsets.only(top: 12),
                child: InkWell(
                  onTap: id == "—" ? null : () => context.go("/customer/shipments/$id"),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(carrier, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text("$status · ${s["weightKg"]} kg", style: Theme.of(context).textTheme.bodySmall),
                        Text(route, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
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
  Timer? _trackingPoll;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments/${widget.shipmentId}");
      final s = r.data?["shipment"];
      final p = r.data?["payment"];
      setState(() {
        _shipment = (s is Map<String, dynamic>) ? s : null;
        _payment = (p is Map<String, dynamic>) ? p : null;
      });
      await _loadTracking();
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadTracking() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/shipments/${widget.shipmentId}/tracking");
      final trip = r.data?["trip"];
      final loc = r.data?["liveLocation"];
      if (!mounted) return;
      setState(() {
        _trip = trip is Map<String, dynamic> ? trip : null;
        _liveLocation = loc is Map<String, dynamic> ? loc : null;
        _isLive = r.data?["isLive"] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _trip = null;
        _liveLocation = null;
        _isLive = false;
      });
    }
  }

  void _scheduleTrackingPoll() {
    _trackingPoll?.cancel();
    if (_shipment?["status"]?.toString() != "BOOKED") return;
    _trackingPoll = Timer.periodic(const Duration(seconds: 15), (_) => _loadTracking());
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
    _load().then((_) => _scheduleTrackingPoll());
  }

  @override
  void dispose() {
    _trackingPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Shipment detail",
      currentPath: "/customer/shipments/${widget.shipmentId}",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text("shipmentId: ${widget.shipmentId}", style: Theme.of(context).textTheme.bodySmall),
              ),
              IconButton(
                tooltip: "Copy shipment id",
                onPressed: () => _copyToClipboard(context, "shipment id", widget.shipmentId),
                icon: const Icon(Icons.copy, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null) SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_shipment != null) ...[
            if (_trip != null) ...[
              Text(
                _isLive ? "Live trip tracking" : "Trip tracking",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_latLngFromGeo(_trip!["origin"] as Map<String, dynamic>?) != null &&
                  _latLngFromGeo(_trip!["destination"] as Map<String, dynamic>?) != null)
                tripTrackingMap(
                  origin: _latLngFromGeo(_trip!["origin"] as Map<String, dynamic>?)!,
                  destination: _latLngFromGeo(_trip!["destination"] as Map<String, dynamic>?)!,
                  pickup: _latLngFromGeo(_shipment!["pickup"] as Map<String, dynamic>?),
                  drop: _latLngFromGeo(_shipment!["drop"] as Map<String, dynamic>?),
                  driver: _isLive ? _latLngFromGeo(_liveLocation) : null,
                )
              else
                Text(
                  "Map unavailable until the carrier republishes the trip with map pins.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 8),
              Text(
                    _isLive
                    ? "Driver location updates every ~30s while the trip is in progress."
                    : _shipment!["status"] == "BOOKED" || _shipment!["status"] == "PENDING_CARRIER_ACCEPT"
                        ? "Live tracking starts after the carrier accepts and starts the load."
                        : "Live tracking ends after delivery is confirmed.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Carrier: ${_shipment!["carrierDisplayName"] ?? "—"}", style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text("Status: ${shipmentStatusLabel(_shipment!["status"]?.toString() ?? "")}"),
                    Text("Your org: ${_shipment!["customerOrgName"]}"),
                    Text("Weight: ${_shipment!["weightKg"]} kg"),
                    if (_trip != null)
                      Text(
                        "Lane: ${_trip!["originCity"]} → ${_trip!["destCity"]} (${tripStatusLabel(_trip!["status"]?.toString() ?? "")})",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    Text("pickup: ${_shipment!["pickupAddress"]}", style: Theme.of(context).textTheme.bodySmall),
                    Text("drop: ${_shipment!["dropAddress"]}", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
          if (_payment != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("payment: ${_payment!["status"]} · ${_payment!["amountPaise"]} paise"),
                    Text("provider: ${_payment!["provider"]}", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    await _load();
                    _scheduleTrackingPoll();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text("Refresh status"),
          ),
        ],
      ),
    );
  }
}

class PublishTripScreen extends StatefulWidget {
  const PublishTripScreen({super.key});

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  final _orgId = TextEditingController();
  final _origin = TextEditingController(text: "Gurugram, Haryana");
  final _dest = TextEditingController(text: "Jaipur, Rajasthan");
  LatLng _originPos = const LatLng(28.4595, 77.0266);
  LatLng _destPos = const LatLng(26.9124, 75.7873);
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  String _out = "";
  bool _submitting = false;
  bool _loadingMe = false;
  Timer? _rateDebounce;
  Map<String, dynamic>? _rateEstimate;
  String _rateError = "";
  bool _loadingRates = false;

  @override
  void initState() {
    super.initState();
    final oid = lastRegisteredOrgId;
    if (oid != null && oid.isNotEmpty) _orgId.text = oid;
    _defaultAnchorTripWindow(_w1, _w2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRateFetch());
  }

  @override
  void dispose() {
    _rateDebounce?.cancel();
    _orgId.dispose();
    _origin.dispose();
    _dest.dispose();
    _w1.dispose();
    _w2.dispose();
    _vehClass.dispose();
    _cap.dispose();
    super.dispose();
  }

  void _scheduleRateFetch() {
    _rateDebounce?.cancel();
    _rateDebounce = Timer(const Duration(milliseconds: 550), () {
      _fetchSuggestedRates();
    });
  }

  Future<void> _fetchSuggestedRates() async {
    final vc = _vehClass.text.trim().toUpperCase();
    if (vc != "SMALL" && vc != "MEDIUM" && vc != "LARGE") return;
    setState(() {
      _loadingRates = true;
      _rateError = "";
    });
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/rates/estimate",
        data: {
          "origin": {"lat": _originPos.latitude, "lng": _originPos.longitude},
          "destination": {"lat": _destPos.latitude, "lng": _destPos.longitude},
          "vehicleClass": vc,
          "sampleWeightsKg": [100, 250, 500],
        },
      );
      final d = r.data;
      if (!mounted) return;
      setState(() {
        _rateEstimate = d is Map<String, dynamic> ? d : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rateEstimate = null;
        _rateError = formatApiError(e);
      });
    } finally {
      if (mounted) setState(() => _loadingRates = false);
    }
  }

  Future<void> _loadPilotMe() async {
    setState(() => _loadingMe = true);
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      final oid = firstCarrierOrgIdFromPilotMe(r.data);
      if (oid != null) {
        lastRegisteredOrgId = oid;
        _orgId.text = oid;
      }
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _loadingMe = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final orgId = _orgId.text.trim();
      if (orgId.isEmpty) {
        setState(() => _out = "Set orgId (from register response, or tap “Load org from /v1/pilot/me”).");
        return;
      }
      final cap = int.tryParse(_cap.text.trim()) ?? 0;
      if (cap <= 0) {
        setState(() => _out = "capacityKg must be a positive number.");
        return;
      }
      final vc = _vehClass.text.trim().toUpperCase();
      if (vc != "SMALL" && vc != "MEDIUM" && vc != "LARGE") {
        setState(() => _out = "vehicleClass must be SMALL, MEDIUM, or LARGE.");
        return;
      }
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/anchor-trips",
        data: {
          "orgId": orgId,
          "originCity": _origin.text.trim(),
          "destCity": _dest.text.trim(),
          "origin": {
            "lat": _originPos.latitude,
            "lng": _originPos.longitude,
            "label": _origin.text.trim(),
          },
          "destination": {
            "lat": _destPos.latitude,
            "lng": _destPos.longitude,
            "label": _dest.text.trim(),
          },
          "windowStart": _w1.text.trim(),
          "windowEnd": _w2.text.trim(),
          "vehicleClass": vc,
          "capacityKg": cap,
        },
      );
      setState(() => _out = r.data?.toString() ?? "{}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trip published.")));
      context.go("/trips");
    } catch (e) {
      setState(() => _out = formatApiError(e));
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PilotScaffold(
      title: "Publish trip",
      currentPath: "/publish",
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                "Publish needs:\n"
                "• OTP verify first (Bearer token).\n"
                "• orgId for an org where your user has a pilot role (solo register → org.id).\n"
                "• Same phone for register + OTP on this server.\n"
                "API errors return JSON like {\"error\":\"membership_not_found\"}.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadingMe ? null : _loadPilotMe,
            icon: _loadingMe
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.badge_outlined),
            label: const Text("Load org from GET /v1/pilot/me"),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _defaultAnchorTripWindow(_w1, _w2)),
            icon: const Icon(Icons.schedule),
            label: const Text("Reset trip window (today–tomorrow, IST)"),
          ),
          const SizedBox(height: 12),
          TextField(controller: _orgId, decoration: const InputDecoration(labelText: "orgId (org.id)")),
          const SizedBox(height: 8),
          Text("Origin & destination", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Search sets the pin; dragging updates coordinates. Text is sent as originCity / destCity and as map labels.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          LocationEndpointEditor(
            title: "Origin",
            hint: "Origin city or address",
            labelController: _origin,
            markerId: "publish_origin",
            markerHue: BitmapDescriptor.hueGreen,
            position: _originPos,
            onPositionChanged: (p) {
              setState(() => _originPos = p);
              _scheduleRateFetch();
            },
          ),
          const SizedBox(height: 20),
          LocationEndpointEditor(
            title: "Destination",
            hint: "Destination city or address",
            labelController: _dest,
            markerId: "publish_dest",
            markerHue: BitmapDescriptor.hueRed,
            position: _destPos,
            onPositionChanged: (p) {
              setState(() => _destPos = p);
              _scheduleRateFetch();
            },
          ),
          const SizedBox(height: 12),
          routePreviewMap(a: _originPos, b: _destPos),
          TextField(
            controller: _vehClass,
            decoration: const InputDecoration(labelText: "vehicleClass (SMALL|MEDIUM|LARGE)"),
            onChanged: (_) => _scheduleRateFetch(),
          ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.45),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Suggested freight (lane reference)",
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Advisory — customer quotes use shipment pickup→drop when booked. "
                    "Tune server env FREIGHT_PAISE_PER_KM_*.",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  if (_loadingRates)
                    const SizedBox(
                      height: 28,
                      width: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_rateError.isNotEmpty)
                    Text(_rateError, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13))
                  else if (_rateEstimate != null) ...[
                    Text(
                      "Lane ≈ ${_rateEstimate!["laneKm"]} km · ${_rateEstimate!["modelVersion"] ?? ""}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ...(List<dynamic>.from(_rateEstimate!["samples"] as List? ?? const [])
                        .whereType<Map>()
                        .map((s) {
                          final m = Map<String, dynamic>.from(s);
                          final w = m["weightKg"];
                          final gp = m["grossPaise"];
                          final rupees = (gp is num)
                              ? (gp / 100).toStringAsFixed((gp.remainder(100).abs() < 1e-6) ? 0 : 2)
                              : "?";
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text("≈ ₹$rupees total at ${w ?? "?"} kg"),
                          );
                        })),
                  ]
                  else
                    Text("Sign in as a driver and adjust pins to load estimates.", style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          TextField(controller: _w1, decoration: const InputDecoration(labelText: "windowStart (ISO +05:30)")),
          TextField(controller: _w2, decoration: const InputDecoration(labelText: "windowEnd (ISO +05:30)")),
          TextField(controller: _cap, decoration: const InputDecoration(labelText: "capacityKg")),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text("POST /v1/pilot/anchor-trips"),
          ),
          const SizedBox(height: 12),
          SelectableText(_out),
        ],
      ),
    );
  }
}
