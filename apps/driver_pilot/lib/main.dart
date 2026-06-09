import "dart:async";

import "package:dio/dio.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter/services.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:go_router/go_router.dart";

import "customer_flow.dart";
import "customer_session.dart";
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
      initialLocation: kIsWeb ? "/customer" : "/driver",
      refreshListenable: CustomerSession.listenable,
      routes: [
        ...driverFlowRoutes(),
        ...customerFlowRoutes(),
        GoRoute(path: "/pilot-lab", builder: (_, __) => const HomeScreen()),
        GoRoute(path: "/", redirect: (_, __) => kIsWeb ? "/customer" : "/driver"),
        GoRoute(path: "/register", builder: (_, __) => const RegisterScreen()),
        GoRoute(
          path: "/login",
          redirect: (context, state) {
            if (state.uri.queryParameters["mode"] == "customer") return "/customer/login";
            return null;
          },
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(path: "/trips", builder: (_, __) => const MyTripsScreen()),
        GoRoute(
          path: "/trips/:tripId",
          builder: (_, state) => TripDetailScreen(tripId: state.pathParameters["tripId"] ?? ""),
        ),
        GoRoute(path: "/publish", builder: (_, __) => const PublishTripScreen()),
      ],
    );

    return MaterialApp.router(
      title: kIsWeb ? "NaviG8r Customer" : "NaviG8r Driver",
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
        bodyBuilder: (_) => body,
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
