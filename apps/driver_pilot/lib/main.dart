import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:go_router/go_router.dart";

/// Android emulator → host machine API:
/// `http://10.0.2.2:3000`
///
/// Physical Android on same LAN:
/// `http://<YOUR_PC_LAN_IP>:3000`
const String kDefaultBaseUrl = "https://navig8r.onrender.com";

final _storage = const FlutterSecureStorage();

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
        GoRoute(path: "/publish", builder: (_, __) => const PublishTripScreen()),
      ],
    );

    return MaterialApp.router(
      title: "Driver Pilot",
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      routerConfig: router,
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

  Future<void> _ping() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/health");
      setState(() => _health = "${r.data}");
    } catch (e) {
      setState(() => _health = "error: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _ping();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Pilot")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Base URL: ${api.baseUrl}", style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text("GET /health → $_health"),
          const SizedBox(height: 16),
          FilledButton(onPressed: _ping, child: const Text("Retry health")),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => context.go("/register"), child: const Text("Register (solo org)")),
          OutlinedButton(onPressed: () => context.go("/login"), child: const Text("Login (OTP)")),
          OutlinedButton(onPressed: () => context.go("/publish"), child: const Text("Publish anchor trip")),
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
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/driver/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": _phone.text.trim(),
          "orgDisplayName": _org.text.trim(),
          "vehicleRegistrationNumber": _reg.text.trim(),
          "vehicleClass": _vehClass.text.trim(),
          "vehicleCapacityKg": int.tryParse(_capKg.text.trim()) ?? 0,
        },
      );
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = "error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
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
          FilledButton(onPressed: _submit, child: const Text("POST /v1/pilot/driver/register")),
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

  Future<void> _start() async {
    try {
      final r = await api.post<Map<String, dynamic>>("/v1/auth/otp/start", data: {"phone": _phone.text.trim()});
      setState(() {
        _startOut = r.data?.toString() ?? "{}";
        final id = r.data?["challengeId"];
        if (id is String) _challengeId.text = id;
      });
    } catch (e) {
      setState(() => _startOut = "error: $e");
    }
  }

  Future<void> _verify() async {
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/auth/otp/verify",
        data: {"phone": _phone.text.trim(), "challengeId": _challengeId.text.trim(), "code": _code.text.trim()},
      );
      final token = r.data?["accessToken"] as String?;
      if (token != null) await api.setToken(token);
      setState(() => _verifyOut = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _verifyOut = "error: $e");
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
    return Scaffold(
      appBar: AppBar(title: const Text("Login (OTP)")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone")),
          FilledButton(onPressed: _start, child: const Text("POST /v1/auth/otp/start")),
          const SizedBox(height: 8),
          SelectableText(_startOut),
          const SizedBox(height: 16),
          TextField(controller: _challengeId, decoration: const InputDecoration(labelText: "challengeId")),
          TextField(controller: _code, decoration: const InputDecoration(labelText: "code (use OTP_DEBUG=123456 locally)")),
          FilledButton(onPressed: _verify, child: const Text("POST /v1/auth/otp/verify")),
          const SizedBox(height: 8),
          SelectableText(_verifyOut),
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
  final _w1 = TextEditingController(text: "2026-04-24T00:00:00+05:30");
  final _w2 = TextEditingController(text: "2026-04-25T23:59:59+05:30");
  final _vehClass = TextEditingController(text: "MEDIUM");
  final _cap = TextEditingController(text: "1000");
  String _out = "";

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

  Future<void> _submit() async {
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/anchor-trips",
        data: {
          "orgId": _orgId.text.trim(),
          "originCity": _origin.text.trim(),
          "destCity": _dest.text.trim(),
          "windowStart": _w1.text.trim(),
          "windowEnd": _w2.text.trim(),
          "vehicleClass": _vehClass.text.trim(),
          "capacityKg": int.tryParse(_cap.text.trim()) ?? 0,
        },
      );
      setState(() => _out = r.data?.toString() ?? "{}");
    } catch (e) {
      setState(() => _out = "error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Publish trip")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Requires Bearer token from OTP verify. Paste orgId from register response."),
          TextField(controller: _orgId, decoration: const InputDecoration(labelText: "orgId")),
          TextField(controller: _origin, decoration: const InputDecoration(labelText: "originCity")),
          TextField(controller: _dest, decoration: const InputDecoration(labelText: "destCity")),
          TextField(controller: _w1, decoration: const InputDecoration(labelText: "windowStart")),
          TextField(controller: _w2, decoration: const InputDecoration(labelText: "windowEnd")),
          TextField(controller: _vehClass, decoration: const InputDecoration(labelText: "vehicleClass")),
          TextField(controller: _cap, decoration: const InputDecoration(labelText: "capacityKg")),
          const SizedBox(height: 12),
          FilledButton(onPressed: _submit, child: const Text("POST /v1/pilot/anchor-trips")),
          const SizedBox(height: 12),
          SelectableText(_out),
        ],
      ),
    );
  }
}
