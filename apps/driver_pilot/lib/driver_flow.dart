import "dart:async";

import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:go_router/go_router.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "driver_session.dart";
import "driver_theme.dart";
import "location_editor.dart";
import "pilot_api.dart";

/// Bottom-nav shell for the carrier driver journey.
class DriverShell extends StatelessWidget {
  const DriverShell({
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
    if (path.startsWith("/driver/loads")) return 1;
    if (path.startsWith("/driver/track")) return 2;
    if (path.startsWith("/driver/profile") ||
        path.startsWith("/driver/earnings") ||
        path.startsWith("/driver/payout")) {
      return 3;
    }
    return 0;
  }

  String _pathForIndex(int index) {
    switch (index) {
      case 1:
        return "/driver/loads";
      case 2:
        return "/driver/track";
      case 3:
        return "/driver/profile";
      case 0:
      default:
        return "/driver";
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _indexForPath(currentPath);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 26)),
        actions: [
          if (actions != null) ...actions!,
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CircleAvatar(backgroundColor: DriverTheme.navy, radius: 18),
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
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: "Home"),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: "Loads",
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: "Track"),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

class DriverWelcomeScreen extends StatelessWidget {
  const DriverWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DriverShell(
      title: "NaviG8r",
      currentPath: "/driver",
      body: Padding(
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
              child: const Text("Get started"),
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
            TextButton(onPressed: () => context.go("/pilot-lab"), child: const Text("Developer lab")),
          ],
        ),
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
        context.go("/driver/onboarding/register");
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
  final _fullName = TextEditingController(text: "Ravi Transport");
  final _phone = TextEditingController();
  final _org = TextEditingController(text: "Ravi Transport");
  final _reg = TextEditingController(text: "HR26AB1234");
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (DriverSession.userPhone != null) _phone.text = DriverSession.userPhone!;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    _reg.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final phone = digitsOnly(_phone.text.trim());
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/driver/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": phone,
          "orgDisplayName": _org.text.trim(),
          "vehicleRegistrationNumber": _reg.text.trim(),
          "vehicleClass": "MEDIUM",
          "vehicleCapacityKg": 1000,
        },
      );
      final orgId = orgIdFromRegisterResponse(r.data);
      if (orgId != null) lastRegisteredOrgId = orgId;
      await DriverSession.refresh();
      if (!mounted) return;
      context.go("/driver/loads");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Carrier organization")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Solo carrier or fleet admin name as customers see it. Banking is collected later before your first payout.",
            style: TextStyle(color: DriverTheme.muted),
          ),
          const SizedBox(height: 16),
          TextField(controller: _fullName, decoration: const InputDecoration(labelText: "Your full name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone")),
          TextField(controller: _org, decoration: const InputDecoration(labelText: "Organization display name")),
          TextField(controller: _reg, decoration: const InputDecoration(labelText: "Vehicle registration")),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create carrier profile"),
          ),
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
  String _filter = "All";

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

  List<Map<String, dynamic>> get _filtered {
    if (_filter == "All") return _trips;
    return _trips.where((t) => (t["vehicleClass"]?.toString() ?? "") == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _trips.isNotEmpty
        ? "${_trips.first["originCity"]} → ${_trips.first["destCity"]} · Today · ${_trips.first["vehicleClass"]}"
        : "No lanes yet · publish a trip";

    return DriverShell(
      title: "Loads",
      currentPath: "/driver/loads",
      body: RefreshIndicator(
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ["All", "SMALL", "MEDIUM", "LARGE"].map((label) {
                  final active = _filter == label;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label == "All" ? "All" : label[0] + label.substring(1).toLowerCase()),
                      selected: active,
                      onSelected: (_) => setState(() => _filter = label),
                      selectedColor: DriverTheme.navy,
                      labelStyle: TextStyle(color: active ? Colors.white : DriverTheme.navy),
                      showCheckmark: false,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text("Best match", style: TextStyle(fontSize: 12, color: DriverTheme.muted, fontWeight: FontWeight.w600)),
                const Spacer(),
                OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)), child: const Text("Fast pay")),
                const SizedBox(width: 6),
                OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32)), child: const Text("Drop & hook")),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            ..._filtered.map((t) => _LoadCard(trip: t, onView: () => context.go("/driver/trip/${t["id"]}/active"))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _LoadCard extends StatelessWidget {
  const _LoadCard({required this.trip, required this.onView});

  final Map<String, dynamic> trip;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final route = "${trip["originCity"]} → ${trip["destCity"]}";
    final cap = trip["capacityKg"];
    final res = trip["reservedKg"];
    final status = trip["status"]?.toString() ?? "";
    final grossHint = status == "FULL" ? "Trip full" : "Open capacity";
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
                Text(status, style: const TextStyle(fontWeight: FontWeight.w700, color: DriverTheme.navy)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "${trip["vehicleClass"]} · ${cap}kg cap · ${res}kg reserved",
              style: const TextStyle(fontSize: 12, color: DriverTheme.muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                if (status == "FULL") const Chip(label: Text("Fast pay"), visualDensity: VisualDensity.compact),
                Chip(label: Text(grossHint), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Window ${trip["windowStart"]}",
                    style: const TextStyle(fontSize: 11, color: DriverTheme.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilledButton(onPressed: onView, child: const Text("View")),
              ],
            ),
          ],
        ),
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

  Future<void> _load() async {
    setState(() => _loading = true);
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
    return DriverShell(
      title: "Track",
      currentPath: "/driver/track",
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "Trips with reserved capacity — open for live GPS tracking while in progress.",
              style: TextStyle(color: DriverTheme.muted),
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            ..._trips.map(
              (t) => ListTile(
                title: Text("${t["originCity"]} → ${t["destCity"]}"),
                subtitle: Text("Reserved ${t["reservedKg"]}kg · ${t["status"]}"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go("/driver/trip/${t["id"]}/active"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DriverShell(
      title: "Profile",
      currentPath: "/driver/profile",
      body: ListView(
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
            onTap: () => context.go("/driver/earnings"),
          ),
          ListTile(
            leading: const Icon(Icons.add_road, color: DriverTheme.navy),
            title: const Text("Publish anchor trip"),
            onTap: () => context.go("/publish"),
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
      ),
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
  String? _error;
  bool _loading = true;

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
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(distanceFilter: 25),
    ).listen((p) {
      if (mounted) setState(() => _driverPos = LatLng(p.latitude, p.longitude));
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/anchor-trips/${widget.tripId}");
      final t = r.data?["trip"];
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
      setState(() {
        _trip = t is Map<String, dynamic> ? t : null;
        _shipments = ships;
      });
    } catch (e) {
      setState(() => _error = formatApiError(e));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final origin = trip != null ? latLngFromTripField(trip, "origin") : null;
    final dest = trip != null ? latLngFromTripField(trip, "destination") : null;
    final next = _shipments.isNotEmpty ? _shipments.first : null;
    final nextPickup = next != null ? latLngFromTripField(next, "pickup") : null;

    return Scaffold(
      appBar: AppBar(title: Text(trip == null ? "Active trip" : "${trip["originCity"]} → ${trip["destCity"]}")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 220,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _driverPos ?? origin ?? const LatLng(28.47, 77.03),
                      zoom: 10,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    markers: {
                      if (origin != null)
                        Marker(markerId: const MarkerId("o"), position: origin, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
                      if (dest != null)
                        Marker(markerId: const MarkerId("d"), position: dest, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
                      if (nextPickup != null)
                        Marker(markerId: const MarkerId("next"), position: nextPickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
                    },
                    polylines: origin != null && dest != null
                        ? {
                            Polyline(
                              polylineId: const PolylineId("route"),
                              points: [origin, dest],
                              width: 4,
                              color: DriverTheme.navy,
                            ),
                          }
                        : {},
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                      const Text("Trip in progress", style: TextStyle(color: DriverTheme.muted, fontWeight: FontWeight.w600)),
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
                            subtitle: Text("$st · ${formatInrFromPaise(s["netToCarrierPaise"] as num? ?? 0)} net"),
                            trailing: st == "BOOKED"
                                ? TextButton(
                                    onPressed: () => context.go("/driver/shipment/$id/pod"),
                                    child: const Text("POD"),
                                  )
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
                                  ? () => context.go("/driver/shipment/${next["id"]}/pod")
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
            ),
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
      await api.post<Map<String, dynamic>>("/shipments/${widget.shipmentId}/pod", data: {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("POD recorded — payout clock started after cooling-off.")),
      );
      context.go("/driver/earnings");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Proof of delivery")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Confirming POD captures payment (if authorized) and sets your payout eligibility after the cooling-off period.",
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

    return Scaffold(
      appBar: AppBar(title: const Text("Earnings")),
      body: _loading
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
                  onPressed: () => context.go("/driver/payout-setup"),
                  child: Text(kyc == "NOT_STARTED" ? "Set up payouts" : "Update payout method"),
                ),
                OutlinedButton(onPressed: () => context.go("/driver/payout-history"), child: const Text("Payout history")),
              ],
            ),
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
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _ifsc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final orgId = DriverSession.carrierOrgId ?? lastRegisteredOrgId ?? "";
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/carrier/payout-setup",
        data: {"orgId": orgId, "accountHolderName": _name.text.trim(), "ifsc": _ifsc.text.trim()},
      );
      final msg = r.data?["message"]?.toString() ?? "Saved.";
      await DriverSession.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.go("/driver/payout-history");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(formatApiError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Payout method")),
      body: Padding(
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
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Save and verify"),
            ),
          ],
        ),
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
    return Scaffold(
      appBar: AppBar(title: const Text("Payout history")),
      body: _loading
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
                OutlinedButton(onPressed: () => context.go("/driver/earnings"), child: const Text("Back to earnings")),
              ],
            ),
    );
  }
}

/// Routes for the integrated driver onboarding + payout flow.
List<RouteBase> driverFlowRoutes() {
  return [
    GoRoute(path: "/driver", builder: (_, __) => const DriverWelcomeScreen()),
    GoRoute(path: "/driver/onboarding/phone", builder: (_, __) => const DriverPhoneScreen()),
    GoRoute(path: "/driver/onboarding/otp", builder: (_, __) => const DriverOtpScreen()),
    GoRoute(path: "/driver/onboarding/register", builder: (_, __) => const DriverRegisterScreen()),
    GoRoute(path: "/driver/loads", builder: (_, __) => const DriverLoadsScreen()),
    GoRoute(path: "/driver/track", builder: (_, __) => const DriverTrackScreen()),
    GoRoute(path: "/driver/profile", builder: (_, __) => const DriverProfileScreen()),
    GoRoute(
      path: "/driver/trip/:tripId/active",
      builder: (_, state) => DriverActiveTripScreen(tripId: state.pathParameters["tripId"] ?? ""),
    ),
    GoRoute(
      path: "/driver/shipment/:shipmentId/pod",
      builder: (_, state) => DriverPodScreen(shipmentId: state.pathParameters["shipmentId"] ?? ""),
    ),
    GoRoute(path: "/driver/earnings", builder: (_, __) => const DriverEarningsScreen()),
    GoRoute(path: "/driver/payout-setup", builder: (_, __) => const DriverPayoutSetupScreen()),
    GoRoute(path: "/driver/payout-history", builder: (_, __) => const DriverPayoutHistoryScreen()),
  ];
}
