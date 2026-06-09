import "dart:async";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter/services.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:go_router/go_router.dart";

import "customer_flow.dart";
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
        ...customerFlowRoutes(),
        GoRoute(path: "/pilot-lab", builder: (_, __) => const HomeScreen()),
        GoRoute(path: "/", redirect: (_, __) => "/driver"),
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
