import "dart:io";

Future<String> diagnoseApiDns(String baseUrl) async {
  Uri uri;
  try {
    uri = Uri.parse(baseUrl);
  } catch (e) {
    return "Invalid API base URL: $baseUrl ($e)";
  }
  final host = uri.host;
  if (host.isEmpty) return "Invalid API base URL (no host): $baseUrl";
  try {
    final ips = await InternetAddress.lookup(host);
    return "DNS ok for $host → ${ips.map((a) => a.address).join(", ")}";
  } on SocketException catch (e) {
    return "DNS failed from Flutter for $host: ${e.message}. "
        "Emulator Chrome can still work (it may use its own DNS). "
        "Try: Settings → Network → Private DNS → Off, cold-boot the AVD, "
        "or run with --dart-define=API_BASE_URL=http://10.0.2.2:3000 against a local API.";
  }
}
