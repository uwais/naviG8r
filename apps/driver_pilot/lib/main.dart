import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";

/// Android emulator → host machine API:
/// `http://10.0.2.2:3000`
///
/// Physical Android on same LAN:
/// `http://<YOUR_PC_LAN_IP>:3000`
const String kDefaultBaseUrl = "https://navig8r.onrender.com";

const _storage = FlutterSecureStorage();

class Api {
  Api(this.baseUrl) : dio = Dio(BaseOptions(baseUrl: baseUrl, headers: {"content-type": "application/json"})) {
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await _storage.read(key: "access_token");
      if (token != null && token.isNotEmpty) {
        options.headers["authorization"] = "Bearer $token";
      }
      handler.next(options);
    }));
  }

  final String baseUrl;
  final Dio dio;

  Future<void> setToken(String token) => _storage.write(key: "access_token", value: token);
  Future<void> clearToken() => _storage.delete(key: "access_token");

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? query}) => dio.get<T>(path, queryParameters: query);
  Future<Response<T>> post<T>(String path, {Object? data}) => dio.post<T>(path, data: data);
}

late Api api;

String _formatApiError(Object e) {
  if (e is DioException) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    return "HTTP ${status ?? "?"}: ${body ?? e.message ?? e.toString()}";
  }
  return e.toString();
}

Future<void> _copyToClipboard(BuildContext context, String label, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Copied $label")));
}

/// Last `org.id` from a successful `POST /v1/pilot/driver/register` (same isolate / app session).
String? lastRegisteredOrgId;

String _digitsOnly(String input) => input.replaceAll(RegExp(r"\D"), "");

String? _orgIdFromRegisterResponse(Map<String, dynamic>? data) {
  final org = data?["org"];
  if (org is Map<String, dynamic>) {
    final id = org["id"];
    if (id is String && id.trim().isNotEmpty) return id.trim();
  }
  return null;
}

String? _firstCarrierOrgIdFromPilotMe(Map<String, dynamic>? data) {
  final orgs = data?["organizations"];
  if (orgs is! List<dynamic>) return null;
  for (final o in orgs) {
    if (o is Map<String, dynamic>) {
      final kind = o["kind"] as String?;
      final id = o["id"] as String?;
      if (id == null || id.isEmpty) continue;
      if (kind == "CARRIER_SOLO" || kind == "CARRIER_FLEET" || kind == "CARRIER_LEGACY") return id;
    }
  }
  if (orgs.isNotEmpty && orgs.first is Map<String, dynamic>) {
    final id = (orgs.first as Map<String, dynamic>)["id"] as String?;
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
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
  api = Api(kDefaultBaseUrl);
  runApp(const DriverPilotApp());
}

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class DriverPilotApp extends StatelessWidget {
  const DriverPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      navigatorKey: _rootNavigatorKey,
      routes: [
        GoRoute(path: "/", builder: (_, __) => const HomeScreen()),
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
        GoRoute(path: "/customer/shipments", builder: (_, __) => const CustomerShipmentsScreen()),
        GoRoute(
          path: "/customer/shipments/:shipmentId",
          builder: (_, state) => CustomerShipmentDetailScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
        ),
        GoRoute(path: "/publish", builder: (_, __) => const PublishTripScreen()),
      ],
    );

    return MaterialApp.router(
      title: "Driver Pilot",
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
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
      case "/":
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
        return "/";
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
        actions: actions,
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
      final orgId = _firstCarrierOrgIdFromPilotMe(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      setState(() => _me = "user: ${name ?? "?"} (${phone ?? "?"})\ncarrierOrg: ${orgId ?? "—"}");
    } catch (e) {
      setState(() => _me = _formatApiError(e));
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
      final r = await api.get<Map<String, dynamic>>("/health");
      setState(() => _health = "${r.data}");
    } catch (e) {
      setState(() => _health = "error: $e");
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
      currentPath: "/",
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
          Text("Customer demo (no auth)", style: Theme.of(context).textTheme.titleMedium),
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
      final phone = _digitsOnly(_phone.text.trim());
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
      final orgId = _orgIdFromRegisterResponse(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = _formatApiError(e));
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
    final phone = _digitsOnly(_phone.text.trim());
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
      setState(() => _startOut = _formatApiError(e));
    } finally {
      setState(() => _starting = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    final phone = _digitsOnly(_phone.text.trim());
    final challengeId = _challengeId.text.trim();
    final code = _code.text.trim();
    if (phone.length != 10 || challengeId.isEmpty || code.isEmpty) {
      setState(() {
        _verifyOut = "Enter valid phone (10 digits), challengeId, and code.";
        _verifying = false;
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
      setState(() => _verifyOut = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _verifyOut = _formatApiError(e));
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
    return PilotScaffold(
      title: "Login (OTP)",
      currentPath: "/login",
      body: ListView(
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
        ],
      ),
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
        _error = _formatApiError(e);
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
      setState(() => _error = _formatApiError(e));
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
                "This is a lightweight customer-side demo using the marketplace endpoints:\n"
                "• GET /anchor-trips\n"
                "• POST /shipments/quote\n"
                "• POST /shipments/book\n"
                "• GET /shipments (+ details, POD, refund)\n\n"
                "It does not use Bearer auth in this MVP.",
              ),
            ),
          ),
          const SizedBox(height: 12),
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
      final phone = _digitsOnly(_phone.text.trim());
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
      setState(() => _out = _formatApiError(e));
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
      setState(() => _error = _formatApiError(e));
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
              final status = t["status"]?.toString() ?? "—";
              final cap = t["capacityKg"];
              final res = t["reservedKg"];
              final isBookable = status == "OPEN";
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
                      Row(
                        children: [
                          Expanded(child: Text("id: $id", style: Theme.of(context).textTheme.bodySmall)),
                          IconButton(
                            tooltip: "Copy trip id",
                            onPressed: id == "—" ? null : () => _copyToClipboard(context, "trip id", id),
                            icon: const Icon(Icons.copy, size: 18),
                          ),
                        ],
                      ),
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

class CustomerBookShipmentScreen extends StatefulWidget {
  const CustomerBookShipmentScreen({super.key});

  @override
  State<CustomerBookShipmentScreen> createState() => _CustomerBookShipmentScreenState();
}

class _CustomerBookShipmentScreenState extends State<CustomerBookShipmentScreen> {
  final _anchorTripId = TextEditingController();
  final _customerOrgName = TextEditingController(text: "ACME Manufacturing");
  final _weightKg = TextEditingController(text: "200");
  final _pickup = TextEditingController(text: "Sector 44, Gurugram");
  final _drop = TextEditingController(text: "Sitapura, Jaipur");
  bool _quoting = false;
  bool _booking = false;
  String _out = "";

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = GoRouterState.of(context).uri.queryParameters["anchorTripId"];
    if (id != null && id.isNotEmpty && _anchorTripId.text.isEmpty) _anchorTripId.text = id;
  }

  @override
  void dispose() {
    _anchorTripId.dispose();
    _customerOrgName.dispose();
    _weightKg.dispose();
    _pickup.dispose();
    _drop.dispose();
    super.dispose();
  }

  Future<void> _quote() async {
    setState(() => _quoting = true);
    try {
      final w = int.tryParse(_weightKg.text.trim()) ?? 0;
      final r = await api.post<Map<String, dynamic>>("/shipments/quote", data: {"weightKg": w});
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = _formatApiError(e));
    } finally {
      setState(() => _quoting = false);
    }
  }

  Future<void> _book() async {
    setState(() => _booking = true);
    try {
      final w = int.tryParse(_weightKg.text.trim()) ?? 0;
      final r = await api.post<Map<String, dynamic>>(
        "/shipments/book",
        data: {
          "anchorTripId": _anchorTripId.text.trim(),
          "customerOrgName": _customerOrgName.text.trim(),
          "weightKg": w,
          "pickupAddress": _pickup.text.trim(),
          "dropAddress": _drop.text.trim(),
        },
      );
      final s = r.data?["shipment"];
      final shipmentId = (s is Map<String, dynamic>) ? s["id"]?.toString() : null;
      setState(() => _out = r.data?.toString() ?? "{}");
      if (!mounted) return;
      if (shipmentId != null && shipmentId.isNotEmpty) context.go("/customer/shipments/$shipmentId");
    } catch (e) {
      setState(() => _out = _formatApiError(e));
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
                child: TextField(controller: _anchorTripId, decoration: const InputDecoration(labelText: "anchorTripId")),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Copy trip id",
                onPressed: _anchorTripId.text.trim().isEmpty
                    ? null
                    : () => _copyToClipboard(context, "trip id", _anchorTripId.text.trim()),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
          TextField(controller: _customerOrgName, decoration: const InputDecoration(labelText: "customerOrgName")),
          TextField(controller: _weightKg, decoration: const InputDecoration(labelText: "weightKg")),
          TextField(controller: _pickup, decoration: const InputDecoration(labelText: "pickupAddress")),
          TextField(controller: _drop, decoration: const InputDecoration(labelText: "dropAddress")),
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
      setState(() => _error = _formatApiError(e));
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
      title: "Shipments",
      currentPath: "/customer/shipments",
      body: RefreshIndicator(
        onRefresh: () async => _load(),
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
            ..._shipments.map((s) {
              final id = s["id"]?.toString() ?? "—";
              final status = s["status"]?.toString() ?? "—";
              final org = s["customerOrgName"]?.toString() ?? "—";
              final tripId = s["anchorTripId"]?.toString() ?? "—";
              return Card(
                margin: const EdgeInsets.only(top: 12),
                child: InkWell(
                  onTap: id == "—" ? null : () => context.go("/customer/shipments/$id"),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Shipment $id", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text("$status · $org", style: Theme.of(context).textTheme.bodySmall),
                        Text("anchorTripId: $tripId", style: Theme.of(context).textTheme.bodySmall),
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
  String _actionOut = "";
  bool _acting = false;

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
    } catch (e) {
      setState(() => _error = _formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pod() async {
    setState(() => _acting = true);
    try {
      final r = await api.post<Map<String, dynamic>>("/shipments/${widget.shipmentId}/pod", data: {});
      setState(() => _actionOut = r.data?.toString() ?? "{}");
      await _load();
    } catch (e) {
      setState(() => _actionOut = _formatApiError(e));
    } finally {
      setState(() => _acting = false);
    }
  }

  Future<void> _failRefund() async {
    setState(() => _acting = true);
    try {
      final r = await api.post<Map<String, dynamic>>("/shipments/${widget.shipmentId}/fail-refund", data: {});
      setState(() => _actionOut = r.data?.toString() ?? "{}");
      await _load();
    } catch (e) {
      setState(() => _actionOut = _formatApiError(e));
    } finally {
      setState(() => _acting = false);
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("status: ${_shipment!["status"]}"),
                    Text("customerOrgName: ${_shipment!["customerOrgName"]}"),
                    Text("anchorTripId: ${_shipment!["anchorTripId"]}"),
                    Text("weightKg: ${_shipment!["weightKg"]}"),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_acting || _loading) ? null : _pod,
                  icon: _acting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fact_check_outlined),
                  label: const Text("Mark POD"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_acting || _loading) ? null : _failRefund,
                  icon: const Icon(Icons.undo),
                  label: const Text("Fail + refund"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_actionOut.isNotEmpty) SelectableText(_actionOut),
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
  final _origin = TextEditingController(text: "Gurugram");
  final _dest = TextEditingController(text: "Jaipur");
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  String _out = "";
  bool _submitting = false;
  bool _loadingMe = false;

  @override
  void initState() {
    super.initState();
    final oid = lastRegisteredOrgId;
    if (oid != null && oid.isNotEmpty) _orgId.text = oid;
    _defaultAnchorTripWindow(_w1, _w2);
  }

  @override
  void dispose() {
    _orgId.dispose();
    _origin.dispose();
    _dest.dispose();
    _w1.dispose();
    _w2.dispose();
    _vehClass.dispose();
    _cap.dispose();
    super.dispose();
  }

  Future<void> _loadPilotMe() async {
    setState(() => _loadingMe = true);
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      final oid = _firstCarrierOrgIdFromPilotMe(r.data);
      if (oid != null) {
        lastRegisteredOrgId = oid;
        _orgId.text = oid;
      }
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = _formatApiError(e));
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
      setState(() => _out = _formatApiError(e));
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
          TextField(controller: _origin, decoration: const InputDecoration(labelText: "originCity")),
          TextField(controller: _dest, decoration: const InputDecoration(labelText: "destCity")),
          TextField(controller: _w1, decoration: const InputDecoration(labelText: "windowStart (ISO +05:30)")),
          TextField(controller: _w2, decoration: const InputDecoration(labelText: "windowEnd (ISO +05:30)")),
          TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "vehicleClass (SMALL|MEDIUM|LARGE)")),
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
