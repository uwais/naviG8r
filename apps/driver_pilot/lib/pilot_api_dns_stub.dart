Future<String> diagnoseApiDns(String baseUrl) async {
  Uri uri;
  try {
    uri = Uri.parse(baseUrl);
  } catch (e) {
    return "Invalid API base URL: $baseUrl ($e)";
  }
  return "Web client — DNS check skipped for ${uri.host}.";
}
